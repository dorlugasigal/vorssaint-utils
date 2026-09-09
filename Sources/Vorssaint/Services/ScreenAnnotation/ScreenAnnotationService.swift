// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine

/// Screen annotation overlay — draw on top of everything.
///
/// Architecture mirrors `ScreenshotSelectionController`:
/// - Full-screen borderless panel that can become key.
/// - View owns all mouse handlers (mouseDown/Dragged/Up).
/// - `NSTrackingArea(.activeAlways)` so `mouseDragged` fires even in
///   nonactivating panels.
/// - No `wantsLayer` on the view — transparent panel + layer = blank output.
final class ScreenAnnotationService: NSObject, ObservableObject {
    static let shared = ScreenAnnotationService()

    // MARK: - Panels

    private var canvasPanel: AnnotationCanvasPanel?
    private var toolbarPanel: NSPanel?
    private var drawingView: AnnotationDrawingView?

    // MARK: - State

    @Published private(set) var isDrawingActive = false
    private var document = AnnotationDocument()
    private(set) var strokes: [AnnotationElement] {
        get { document.state.elements }
        _modify { yield &document.state.elements }
    }
    private(set) var selectedID: UUID? {
        get { strokes.first(where: { document.selectedIDs.contains($0.id) })?.id }
        set {
            objectWillChange.send()
            document.selectedIDs = Set(newValue.map { [$0] } ?? [])
        }
    }
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    private var draftID: UUID?
    private var dragStart = CGPoint.zero
    private var editGesture: AnnotationEditGesture?
    private var groupGestures: [AnnotationEditGesture] = []
    private(set) var marquee: CGRect?
    private var marqueeSelection: Set<UUID> = []
    private var linearConstruction: AnnotationLinearConstruction?
    private(set) var editingTextID: UUID?
    var hasLinearConstruction: Bool { linearConstruction != nil }
    var selectedIDs: Set<UUID> { document.selectedIDs }
    private var toolStyles: [AnnotationTool: AnnotationStyle] = [:]
    enum Background: Int { case transparent, white, black }
    @Published private(set) var background = Background.transparent

    func cycleBackground() {
        background = Background(rawValue: (background.rawValue + 1) % 3) ?? .transparent
        drawingView?.needsDisplay = true
    }
    @Published private(set) var shortcutRegistrationFailed = false

    // Preferences (kept in sync with UserDefaults)
    @Published private(set) var tool: AnnotationTool = .pen
    @Published private(set) var color: AnnotationColor = .red
    @Published private(set) var width = ScreenAnnotationSupport.defaultWidth

    // MARK: - Monitors

    private var keyMonitor: Any?
    private var sessionScreen: NSScreen?
    private var sessionGeometry: AnnotationDisplayGeometry?
    private var sessionObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private let hotkey = QuickToolHotkey(id: 7)

    private override init() { super.init() }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        guard AppFeature.screenAnnotation.isAvailable else { teardown(); return }
        syncShortcut()
        loadPreferences()
    }

    // Entry point from menu / shortcut
    @objc func toggleDrawing() {
        guard AppFeature.screenAnnotation.isAvailable else { return }
        if canvasPanel == nil {
            guard let screen = NSScreen.withMouse else {
                NSSound.beep()
                return
            }
            buildPanels(screen: screen)
        }
        isDrawingActive ? exitDrawingMode() : enterDrawingMode()
    }

    @objc func clearAll() {
        cancelGesture()
        document.edit { $0.elements.removeAll(); $0.selection.removeAll() }
        refreshDocument()
    }

    @objc func undo() {
        cancelGesture()
        document.undo()
        refreshDocument()
    }

    @objc func redo() {
        cancelGesture()
        document.redo()
        refreshDocument()
    }

    func deleteSelected() {
        performSelectionAction(.delete)
    }

    func performSelectionAction(_ action: AnnotationSelectionAction) {
        cancelGesture()
        document.edit { AnnotationSelection.apply(action, to: &$0) }
        refreshDocument()
    }

    private func refreshDocument() {
        canUndo = document.history.canUndo
        canRedo = document.history.canRedo
        drawingView?.needsDisplay = true
        if let element = strokes.first(where: { $0.id == editingTextID }) {
            drawingView?.updateTextEditor(element)
        }
        DispatchQueue.main.async { [weak self] in self?.fitToolbar() }
    }

    fileprivate func cancelGesture() {
        document.cancel()
        editingTextID = nil
        drawingView?.cancelTextEditor()
        draftID = nil
        editGesture = nil
        groupGestures.removeAll()
        marquee = nil
        linearConstruction = nil
        refreshDocument()
    }

    @objc func hideOverlay() {
        closeSession()
    }

    private func closeSession() {
        exitDrawingMode()
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        sessionObservers.removeAll()
        workspaceObservers.removeAll()
        canvasPanel?.orderOut(nil)
        toolbarPanel?.orderOut(nil)
        canvasPanel?.contentView = nil
        canvasPanel = nil
        toolbarPanel?.orderOut(nil)
        toolbarPanel?.contentViewController = nil
        toolbarPanel = nil
        drawingView = nil
        document = AnnotationDocument()
        background = .transparent
        refreshDocument()
        selectedID = nil
        draftID = nil
        sessionScreen = nil
        sessionGeometry = nil
    }

    func teardown() {
        closeSession()
        unregisterShortcut()
    }

    // MARK: - Drawing mode

    private func enterDrawingMode() {
        isDrawingActive = true
        canvasPanel?.ignoresMouseEvents = ScreenAnnotationSupport.canvasIgnoresMouseEvents(isDrawing: true)
        showPanels()
        // Pattern from ScreenshotSelectionController:
        // 1) orderFrontRegardless
        // 2) makeKey — routes NSEvent.addLocalMonitor to this window
        canvasPanel?.makeKey()
        installKeyMonitors()
    }

    private func exitDrawingMode() {
        drawingView?.cancelInteraction()
        isDrawingActive = false
        // Keep the strokes visible, but restore pass-through to the app below.
        canvasPanel?.ignoresMouseEvents = ScreenAnnotationSupport.canvasIgnoresMouseEvents(isDrawing: false)
        removeKeyMonitors()
        canvasPanel?.resignKey()
        drawingView?.needsDisplay = true
    }

    // MARK: - Panel building

    private func buildPanels(screen: NSScreen) {
        sessionScreen = screen
        sessionGeometry = AnnotationDisplayGeometry(id: screen.displayID, frame: screen.frame,
                                                    scale: screen.backingScaleFactor)
        buildCanvasPanel(screen: screen)
        buildToolbarPanel(screen: screen)
        sessionObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self, let geometry = self.sessionGeometry else { return }
                let displays = NSScreen.screens.map {
                    AnnotationDisplayGeometry(id: $0.displayID, frame: $0.frame, scale: $0.backingScaleFactor)
                }
                guard geometry.isCompatible(with: displays) else {
                    self.closeSession()
                    return
                }
            })
        for name in [NSWorkspace.willSleepNotification,
                     NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.exitDrawingMode()
                })
        }
    }


    /// Builds the full-screen drawing surface.
    /// Mirrors `ScreenshotOverlayPanel` from `ScreenshotSelectionController`.
    private func buildCanvasPanel(screen: NSScreen) {
        let p = AnnotationCanvasPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        // Shielding-1 so it sits just below the toolbar
        p.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true   // critical for mouseMoved delivery
        p.ignoresMouseEvents = false

        let view = AnnotationDrawingView(service: self)
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.autoresizingMask = [.width, .height]
        p.contentView = view
        self.canvasPanel = p
        self.drawingView = view
    }

    private func buildToolbarPanel(screen: NSScreen) {
        let host = ScreenAnnotationToolbar.makeController(service: self)
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        let rect = AnnotationDisplayGeometry.toolbarFrame(size: size, visibleFrame: screen.visibleFrame)

        let p = NSPanel(contentRect: rect,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.ignoresMouseEvents = false
        p.contentViewController = host
        p.isMovableByWindowBackground = true
        self.toolbarPanel = p
        sessionObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
                guard let self, let toolbar = self.toolbarPanel, let screen = self.sessionScreen else { return }
                let frame = toolbar.frame
                let visible = screen.visibleFrame
                let origin = CGPoint(x: min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width)),
                                     y: min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height)))
                if frame.origin != origin { toolbar.setFrameOrigin(origin) }
            })
    }

    // MARK: - Show

    private func showPanels() {
        guard let canvas = canvasPanel,
              let toolbar = toolbarPanel else { return }
        canvas.orderFrontRegardless()
        toolbar.orderFrontRegardless()
    }

    private func fitToolbar() {
        guard let toolbar = toolbarPanel, let screen = sessionScreen,
              let view = toolbar.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let fitted = view.fittingSize
        let visible = screen.visibleFrame
        let size = CGSize(width: min(fitted.width, visible.width), height: min(fitted.height, visible.height))
        let origin = CGPoint(x: min(max(toolbar.frame.minX, visible.minX), visible.maxX - size.width),
                             y: min(max(toolbar.frame.minY, visible.minY), visible.maxY - size.height))
        let frame = CGRect(origin: origin, size: size)
        if toolbar.frame != frame { toolbar.setFrame(frame, display: true) }
    }

    // MARK: - Key monitors (pattern from ScreenshotSelectionController)

    private func installKeyMonitors() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, event.window is AnnotationCanvasPanel else { return event }
                if event.type == .keyDown {
                    if event.window?.firstResponder is NSTextView { return event }
                    if event.modifierFlags.contains(.command),
                       event.charactersIgnoringModifiers?.lowercased() == "z" {
                        event.modifierFlags.contains(.shift) ? self.redo() : self.undo()
                        return nil
                    }
                    switch Int(event.keyCode) {
                    case kVK_Return, kVK_ANSI_KeypadEnter:
                        if self.hasLinearConstruction { self.finishLinearConstruction(); return nil }
                    case kVK_Delete, kVK_ForwardDelete:
                        self.deleteSelected()
                        return nil
                    case kVK_Escape:
                        if self.drawingView?.dismissTextEditor() != true {
                            self.exitDrawingMode()
                        }
                        return nil
                    default:
                        break
                    }
                    return event
                }
                return event
            }
    }

    private func removeKeyMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    // MARK: - Preferences

    func loadPreferences() {
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.screenAnnotationTool),
           let t = AnnotationTool(rawValue: raw) { tool = t }
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.screenAnnotationColor) {
            color = colorForPreference(raw)
        }
        let w = UserDefaults.standard.double(forKey: DefaultsKey.screenAnnotationWidth)
        width = w > 0 ? min(max(w, 1), 40) : ScreenAnnotationSupport.defaultWidth
    }

    func setTool(_ t: AnnotationTool) {
        cancelGesture()
        tool = t
        UserDefaults.standard.set(t.rawValue, forKey: DefaultsKey.screenAnnotationTool)
        DispatchQueue.main.async { [weak self] in self?.fitToolbar() }
    }

    func setColor(_ c: AnnotationColor) {
        var style = inspectorStyle
        style.color = c
        setInspectorStyle(style)
    }

    func setWidth(_ w: Double) {
        var style = inspectorStyle
        style.width = w
        setInspectorStyle(style)
    }

    var inspectorStyle: AnnotationStyle {
        strokes.first(where: { $0.id == selectedID })?.resolvedStyle ?? creationStyle
    }
    var inspectorTool: ScreenshotSupport.Tool {
        strokes.first(where: { $0.id == selectedID })?.tool ?? tool.elementTool ?? .select
    }

    func styleEditingChanged(_ editing: Bool) {
        if editing { document.begin() } else {
            if editingTextID == nil { document.commit() }
            refreshDocument()
            if editingTextID != nil { canvasPanel?.makeKey(); drawingView?.focusTextEditor() }
        }
    }

    func setInspectorStyle(_ value: AnnotationStyle) {
        let style = value.sanitized()
        let continuous = document.history.isEditing
        if !continuous { document.begin() }
        if selectedID != nil {
            for index in strokes.indices where selectedIDs.contains(strokes[index].id) && !strokes[index].isLocked {
                strokes[index].style = style
                if !style.bindEndpoints { strokes[index].startBinding = nil; strokes[index].endBinding = nil }
                if strokes[index].tool == .text { strokes[index].rect = AnnotationRenderer.textBounds(strokes[index], scale: 1) }
            }
        } else {
            toolStyles[tool] = style
            color = style.color
            width = style.width
            UserDefaults.standard.set("\(color.red),\(color.green),\(color.blue),\(color.alpha)",
                                      forKey: DefaultsKey.screenAnnotationColor)
            UserDefaults.standard.set(width, forKey: DefaultsKey.screenAnnotationWidth)
        }
        if !continuous { document.commit() }
        AnnotationBindings.finishEdit(selectedIDs, elements: &strokes, tolerance: 14)
        refreshDocument()
    }

    func colorForPreference(_ value: String) -> AnnotationColor {
        let parts = value.split(separator: ",").compactMap { Double($0) }
        if parts.count == 3 || parts.count == 4 {
            return AnnotationColor(red: parts[0], green: parts[1], blue: parts[2],
                                   alpha: parts.count == 4 ? parts[3] : 1).clamped()
        }
        switch value {
        case "orange": return .orange
        case "yellow": return .yellow
        case "green":  return .green
        case "blue":   return .blue
        case "purple": return .purple
        case "black":  return .black
        case "white":  return .white
        default:       return .red
        }
    }

    // MARK: - Stroke entry points (called from AnnotationDrawingView)

    fileprivate func beginStroke(at p: NSPoint, bounds: CGRect, extendingSelection: Bool = false) {
        drawingView?.commitTextEditorIfNeeded()
        if var construction = linearConstruction {
            construction.add(p)
            linearConstruction = construction
            updateLinearPreview()
            return
        }
        cancelGesture()
        dragStart = p
        if tool == .text {
            beginTextEditing(at: p, bounds: bounds)
            return
        }
        if tool == .select, extendingSelection, let hit = hitTest(p, bounds: bounds) {
            let ids = AnnotationSelection.expandingGroups([hit], in: strokes)
            document.selectedIDs = ids.isSubset(of: selectedIDs)
                ? selectedIDs.subtracting(ids) : selectedIDs.union(ids)
            refreshDocument()
            return
        }
        let selected = strokes.first { $0.id == selectedID }
        if let selected {
            let handle = AnnotationEditGesture.handle(for: selected, at: p, tolerance: 12)
            if tool != .eraser,
               handle != nil || AnnotationGeometry.hit(selected, at: p, scale: 1, imageSize: bounds.size) {
                document.begin()
                if selectedIDs.count > 1 {
                    groupGestures = strokes.filter { selectedIDs.contains($0.id) }
                        .map { AnnotationEditGesture(original: $0, anchor: p, handle: .move) }
                } else {
                    editGesture = AnnotationEditGesture(original: selected, anchor: p, handle: handle ?? .move)
                }
                return
            }
        }
        if tool == .select || tool == .eraser {
            let id = hitTest(p, bounds: bounds)
            if tool == .select {
                if let id {
                    document.selectedIDs = AnnotationSelection.expandingGroups([id], in: strokes)
                } else {
                    marqueeSelection = extendingSelection ? selectedIDs : []
                    document.selectedIDs = marqueeSelection
                    marquee = CGRect(origin: p, size: .zero)
                }
            } else { selectedID = nil }
            document.begin()
            if tool == .select, let element = strokes.first(where: { $0.id == id }) {
                groupGestures = strokes.filter { selectedIDs.contains($0.id) }
                    .map { AnnotationEditGesture(original: $0, anchor: p, handle: .move) }
                if groupGestures.isEmpty { editGesture = AnnotationEditGesture(original: element, anchor: p, handle: .move) }
            }
            if tool == .eraser { strokes.removeAll { $0.id == id && !$0.isLocked } }
            drawingView?.needsDisplay = true
            return
        }
        guard let elementTool = tool.elementTool else { return }
        selectedID = nil
        document.begin()
        let element = AnnotationElement(tool: elementTool, rect: CGRect(origin: p, size: .zero),
            points: tool.isRectangular ? [] : [p, p], style: creationStyle)
        strokes.append(element)
        draftID = element.id
        if (elementTool == .arrow || elementTool == .line) && creationStyle.multiClick {
            linearConstruction = AnnotationLinearConstruction(element: element, at: p)
            refreshDocument()
        }
    }

    private var creationStyle: AnnotationStyle {
        toolStyles[tool] ?? AnnotationStyle(color: color, width: width, opacity: tool == .highlighter ? 0.35 : 1,
                        smooth: false, textSize: max(14, width * 3), mediumTextWeight: true)
    }

    fileprivate func beginTextEditing(at point: CGPoint, bounds: CGRect) {
        drawingView?.commitTextEditorIfNeeded()
        let existing = hitTest(point, bounds: bounds).flatMap { id in strokes.first { $0.id == id && $0.tool == .text } }
        guard existing?.isLocked != true else { return }
        document.begin()
        var element = existing ?? AnnotationElement(tool: .text, rect: CGRect(origin: point, size: .zero),
                                                    style: creationStyle)
        element.rect = AnnotationRenderer.textBounds(element, scale: 1)
        if existing == nil { strokes.append(element) }
        selectedID = element.id
        editingTextID = element.id
        drawingView?.beginTextEditor(element)
        refreshDocument()
    }

    fileprivate func commitText(_ value: String) {
        guard let id = editingTextID, let index = strokes.firstIndex(where: { $0.id == id }) else { return }
        if value.isEmpty { strokes.remove(at: index); selectedID = nil } else {
            strokes[index].text = value
            strokes[index].rect = AnnotationRenderer.textBounds(strokes[index], scale: 1)
        }
        editingTextID = nil
        drawingView?.cancelTextEditor()
        document.commit()
        refreshDocument()
    }

    private func hitTest(_ point: CGPoint, bounds: CGRect) -> UUID? {
        strokes.last { AnnotationGeometry.hit($0, at: point, scale: 1, imageSize: bounds.size) }?.id
    }

    fileprivate func selectContextTarget(at point: CGPoint, bounds: CGRect) {
        if let id = hitTest(point, bounds: bounds), !selectedIDs.contains(id) {
            document.selectedIDs = AnnotationSelection.expandingGroups([id], in: strokes)
            refreshDocument()
        }
    }

    fileprivate func continueStroke(at p: NSPoint, bounds: CGRect) {
        defer { AnnotationBindings.resolve(&strokes) }
        let p = NSEvent.modifierFlags.contains(.shift) && (tool == .arrow || tool == .line)
            && editGesture == nil && groupGestures.isEmpty ? AnnotationLinear.constrained(p, from: dragStart) : p
        if linearConstruction != nil {
            linearConstruction?.preview = p
            updateLinearPreview()
            return
        }
        if marquee != nil {
            marquee = ScreenshotSupport.selectionRect(from: dragStart, to: p)
            document.selectedIDs = marqueeSelection.union(AnnotationSelection.marquee(marquee!, elements: strokes))
            return
        }
        if !groupGestures.isEmpty {
            for gesture in groupGestures {
                if let index = strokes.firstIndex(where: { $0.id == gesture.original.id }) {
                    strokes[index] = gesture.updated(to: p)
                }
            }
            return
        }
        if let editGesture, let index = strokes.firstIndex(where: { $0.id == editGesture.original.id }) {
            strokes[index] = editGesture.updated(to: p)
            return
        }
        if tool == .eraser {
            if let id = hitTest(p, bounds: bounds) { strokes.removeAll { $0.id == id && !$0.isLocked } }
            return
        }
        guard let draftID, let i = strokes.firstIndex(where: { $0.id == draftID }) else { return }
        if strokes[i].tool == .freehand {
            strokes[i].points.append(p)
        } else if strokes[i].tool.dragsRect {
            strokes[i].rect = ScreenshotSupport.selectionRect(from: dragStart, to: p)
        } else {
            strokes[i].points = [dragStart, p]
        }
    }

    fileprivate func finishStroke(at point: CGPoint, bounds: CGRect) {
        if editingTextID != nil { return }
        if linearConstruction != nil {
            linearConstruction?.add(point)
            updateLinearPreview()
            return
        }
        continueStroke(at: point, bounds: bounds)
        if let draftID, hypot(point.x - dragStart.x, point.y - dragStart.y) < 1,
           tool != .pen && tool != .highlighter {
            strokes.removeAll { $0.id == draftID }
        } else if tool == .arrow, let draftID {
            selectedID = draftID
        }
        AnnotationBindings.finishEdit(selectedIDs.union(Set(draftID.map { [$0] } ?? [])), elements: &strokes, tolerance: 14)
        document.commit()
        draftID = nil
        editGesture = nil
        groupGestures.removeAll()
        marquee = nil
        refreshDocument()
    }

    private func updateLinearPreview() {
        guard let construction = linearConstruction,
              let index = strokes.firstIndex(where: { $0.id == construction.element.id }) else { return }
        strokes[index] = construction.displayed
        drawingView?.needsDisplay = true
    }

    func finishLinearConstruction() {
        guard let construction = linearConstruction else { return }
        guard let element = construction.completed,
              let index = strokes.firstIndex(where: { $0.id == element.id }) else {
            cancelGesture()
            return
        }
        strokes[index] = element
        selectedID = element.id
        AnnotationBindings.finishEdit([element.id], elements: &strokes, tolerance: 14)
        document.commit()
        linearConstruction = nil
        draftID = nil
        refreshDocument()
    }

    func cancelLinearConstruction() { cancelGesture() }

    func editLinearPoints(_ insert: Bool) {
        document.edit { state in
            for index in state.elements.indices where state.selection.contains(state.elements[index].id) {
                AnnotationLinear.editPoints(insert, in: &state.elements[index])
            }
        }
        refreshDocument()
    }

    // MARK: - Carbon shortcut

    func syncShortcut() {
        let on = AppFeature.screenAnnotation.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.screenAnnotationShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.screenAnnotationShortcut,
                                            fallback: .screenAnnotationDefault)
        hotkey.onPress = { [weak self] in self?.toggleDrawing() }
        shortcutRegistrationFailed = !hotkey.sync(enabled: on, shortcut: shortcut)
    }

    private func unregisterShortcut() {
        hotkey.unregister()
        shortcutRegistrationFailed = false
    }
}

// MARK: - Canvas panel

/// Full-screen drawing surface. Must return `canBecomeKey = true` so
/// `makeKey()` succeeds and the local event monitor filters work.
/// Pattern identical to `ScreenshotOverlayPanel`.
private final class AnnotationCanvasPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Drawing view

/// Freehand stroke receiver.
///
/// Key patterns from `ScreenshotOverlayView`:
/// - No `wantsLayer` — transparent NSPanel + CALayer conflict → blank output.
/// - `NSTrackingArea(.activeAlways, .inVisibleRect)` so `mouseDragged` fires
///   in non-activating panels.
/// - `acceptsFirstResponder = true`.
/// - `isFlipped = true` so coordinate origin matches screen pixels.
private final class AnnotationDrawingView: NSView {
    private weak var service: ScreenAnnotationService?
    private var isDragging = false
    private var textEditor: AnnotationNativeTextEditor?

    init(service: ScreenAnnotationService) {
        self.service = service
        super.init(frame: .zero)
        // Pattern from ScreenshotOverlayView: exact same options
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self)
        addTrackingArea(tracking)
    }

    required init?(coder: NSCoder) { nil }

    func beginTextEditor(_ element: AnnotationElement) {
        cancelTextEditor()
        let editor = AnnotationNativeTextEditor(element: element, scale: 1)
        editor.frame = CGRect(x: min(element.rect.minX, bounds.maxX - min(400, bounds.width)),
                              y: min(element.rect.minY, bounds.maxY - min(200, bounds.height)),
                              width: min(400, bounds.width), height: min(200, bounds.height))
        editor.committed = { [weak service] in service?.commitText($0) }
        editor.cancelled = { [weak service] in service?.cancelGesture() }
        addSubview(editor)
        textEditor = editor
        editor.focus()
    }

    func cancelTextEditor() {
        let editor = textEditor
        textEditor = nil
        editor?.removeFromSuperview()
        if editor != nil { window?.makeFirstResponder(self) }
    }

    func dismissTextEditor() -> Bool {
        guard textEditor != nil else { return false }
        service?.cancelGesture()
        return true
    }

    func updateTextEditor(_ element: AnnotationElement) { textEditor?.applyStyle(element, scale: 1) }
    func focusTextEditor() { textEditor?.focus() }
    func commitTextEditorIfNeeded() {
        if let textEditor { service?.commitText(textEditor.text) }
    }

    func cancelInteraction() {
        isDragging = false
        service?.cancelGesture()
        cancelTextEditor()
    }

    override var acceptsFirstResponder: Bool { true }
    /// Flipped so origin is top-left, matching screen pixels.
    override var isFlipped: Bool { true }
    

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let svc = service,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        if svc.background != .transparent {
            ctx.setFillColor((svc.background == .white ? NSColor.white : NSColor.black).cgColor)
            ctx.fill(bounds)
        }
        for stroke in svc.strokes {
            if stroke.id == svc.editingTextID { continue }
            AnnotationRenderer.draw(stroke, in: ctx, scale: 1, shadowsEnabled: false)
            if svc.selectedIDs.contains(stroke.id) {
                ctx.saveGState()
                ctx.setStrokeColor(NSColor.systemBlue.cgColor)
                ctx.setLineWidth(2)
                ctx.setLineDash(phase: 0, lengths: [5, 3])
                ctx.stroke(AnnotationGeometry.visualBounds(stroke).insetBy(dx: -6, dy: -6))
                if !stroke.isLocked && (stroke.tool == .arrow || stroke.tool == .line) {
                    ctx.setLineDash(phase: 0, lengths: [])
                    ctx.setFillColor(NSColor.white.cgColor)
                    let handles = stroke.points + (stroke.resolvedStyle.curved ? AnnotationLinear.controls(stroke) : [])
                    for point in handles {
                        let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                        ctx.fillEllipse(in: rect)
                        ctx.strokeEllipse(in: rect)
                    }
                }
                ctx.restoreGState()
            }
        }
        if let marquee = svc.marquee {
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(marquee)
        }
        ctx.restoreGState()
    }


    // MARK: Mouse events — pattern from ScreenshotOverlayView

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let service, service.isDrawingActive else { return nil }
        service.selectContextTarget(at: convert(event.locationInWindow, from: nil), bounds: bounds)
        let menu = NSMenu()
        for action in AnnotationSelectionAction.allCases {
            let item = NSMenuItem(title: AnnotationCommandStrings.title(action, L10n.shared.language),
                                  action: #selector(selectionAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = action.rawValue
            item.isEnabled = action == .selectAll || !service.selectedIDs.isEmpty
            menu.addItem(item)
        }
        return menu
    }

    @objc private func selectionAction(_ item: NSMenuItem) {
        guard let action = AnnotationSelectionAction(rawValue: item.tag) else { return }
        service?.performSelectionAction(action)
    }

    override func mouseDown(with event: NSEvent) {
        guard let svc = service, svc.isDrawingActive else { return }
        if event.clickCount == 2, svc.selectedID != nil,
           svc.inspectorTool == .text {
            svc.beginTextEditing(at: convert(event.locationInWindow, from: nil), bounds: bounds)
            return
        }
        if svc.tool == .text {
            isDragging = true
            let point = convert(event.locationInWindow, from: nil)
            svc.beginStroke(at: point, bounds: bounds, extendingSelection: event.modifierFlags.contains(.shift))
            return
        }
        isDragging = true
        let point = convert(event.locationInWindow, from: nil)
        svc.beginStroke(at: point, bounds: bounds, extendingSelection: event.modifierFlags.contains(.shift))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let svc = service, svc.isDrawingActive, isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        svc.continueStroke(at: point, bounds: bounds)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard let service, service.hasLinearConstruction else { return }
        service.continueStroke(at: convert(event.locationInWindow, from: nil), bounds: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            service?.finishStroke(at: convert(event.locationInWindow, from: nil), bounds: bounds)
        }
        isDragging = false
        needsDisplay = true
    }
}
