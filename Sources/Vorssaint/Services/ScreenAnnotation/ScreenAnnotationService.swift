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
    private(set) var strokes: [AnnotationElement] = []
    @Published private(set) var selectedID: UUID?
    private var draftID: UUID?
    private var dragStart = CGPoint.zero
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
        strokes.removeAll()
        selectedID = nil
        drawingView?.needsDisplay = true
    }

    @objc func undo() {
        if !strokes.isEmpty { strokes.removeLast() }
        selectedID = nil
        drawingView?.needsDisplay = true
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
        strokes.removeAll()
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
        self.toolbarPanel = p
    }

    // MARK: - Show

    private func showPanels() {
        guard let canvas = canvasPanel,
              let toolbar = toolbarPanel else { return }
        canvas.orderFrontRegardless()
        toolbar.orderFrontRegardless()
    }

    // MARK: - Key monitors (pattern from ScreenshotSelectionController)

    private func installKeyMonitors() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, event.window is AnnotationCanvasPanel else { return event }
                if event.type == .keyDown {
                    switch Int(event.keyCode) {
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
        tool = t
        UserDefaults.standard.set(t.rawValue, forKey: DefaultsKey.screenAnnotationTool)
    }

    func setColor(_ c: AnnotationColor) {
        color = c
        UserDefaults.standard.set("\(c.red),\(c.green),\(c.blue)",
                                   forKey: DefaultsKey.screenAnnotationColor)
    }

    func setWidth(_ w: Double) {
        width = min(max(w, 1), 40)
        UserDefaults.standard.set(width, forKey: DefaultsKey.screenAnnotationWidth)
    }

    func colorForPreference(_ value: String) -> AnnotationColor {
        let parts = value.split(separator: ",").compactMap { Double($0) }
        if parts.count == 3 {
            return AnnotationColor(red: parts[0], green: parts[1], blue: parts[2]).clamped()
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

    fileprivate func beginStroke(at p: NSPoint, bounds: CGRect) {
        draftID = nil
        dragStart = p
        if tool == .text {
            drawingView?.beginTextEditor(at: p)
            return
        }
        if tool == .select || tool == .eraser {
            let id = hitTest(p, bounds: bounds)
            selectedID = tool == .select ? id : nil
            if tool == .eraser { strokes.removeAll { $0.id == id } }
            drawingView?.needsDisplay = true
            return
        }
        guard let elementTool = tool.elementTool else { return }
        selectedID = nil
        let element = AnnotationElement(tool: elementTool, rect: CGRect(origin: p, size: .zero),
            points: tool.isRectangular ? [] : [p, p], style: creationStyle)
        strokes.append(element)
        draftID = element.id
    }

    private var creationStyle: AnnotationStyle {
        AnnotationStyle(color: color, width: width, opacity: tool == .highlighter ? 0.35 : 1,
                        smooth: false, textSize: max(14, width * 3), mediumTextWeight: true)
    }

    fileprivate func commitText(_ value: String, at p: NSPoint, bounds: CGRect) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var element = AnnotationElement(tool: .text, rect: CGRect(origin: p, size: .zero),
                                        text: text, style: creationStyle)
        element.rect = AnnotationRenderer.textBounds(element, scale: 1)
        strokes.append(element)
        drawingView?.needsDisplay = true
    }

    private func hitTest(_ point: CGPoint, bounds: CGRect) -> UUID? {
        strokes.last { AnnotationGeometry.hit($0, at: point, scale: 1, imageSize: bounds.size) }?.id
    }

    fileprivate func continueStroke(at p: NSPoint, bounds: CGRect) {
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
        continueStroke(at: point, bounds: bounds)
        if tool == .arrow { selectedID = draftID }
        draftID = nil
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
private final class AnnotationDrawingView: NSView, NSTextFieldDelegate {
    private weak var service: ScreenAnnotationService?
    private var isDragging = false
    private var textField: NSTextField?
    private var textOrigin: NSPoint?

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

    func beginTextEditor(at point: NSPoint) {
        textField?.removeFromSuperview()
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y,
                                               width: 300, height: 34))
        field.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        field.textColor = .white
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.focusRingType = .none
        field.target = self
        field.action = #selector(commitTextEditor)
        field.delegate = self
        addSubview(field)
        textField = field
        textOrigin = point
        window?.makeFirstResponder(field)
    }

    func cancelTextEditor() {
        let field = textField
        textField = nil
        textOrigin = nil
        field?.delegate = nil
        field?.removeFromSuperview()
        window?.makeFirstResponder(self)
    }

    func dismissTextEditor() -> Bool {
        guard textField != nil else { return false }
        cancelTextEditor()
        return true
    }

    func cancelInteraction() {
        isDragging = false
        cancelTextEditor()
    }

    @objc private func commitTextEditor() {
        guard let field = textField, let origin = textOrigin, let service else { return }
        service.commitText(field.stringValue, at: origin, bounds: bounds)
        cancelTextEditor()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitTextEditor()
    }

    override var acceptsFirstResponder: Bool { true }
    /// Flipped so origin is top-left, matching screen pixels.
    override var isFlipped: Bool { true }
    

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let svc = service,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        for stroke in svc.strokes {
            AnnotationRenderer.draw(stroke, in: ctx, scale: 1, shadowsEnabled: false)
            if svc.selectedID == stroke.id {
                ctx.saveGState()
                ctx.setStrokeColor(NSColor.systemBlue.cgColor)
                ctx.setLineWidth(2)
                ctx.setLineDash(phase: 0, lengths: [5, 3])
                ctx.stroke(AnnotationGeometry.bounds(stroke).insetBy(dx: -6, dy: -6))
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }


    // MARK: Mouse events — pattern from ScreenshotOverlayView

    override func mouseDown(with event: NSEvent) {
        guard let svc = service, svc.isDrawingActive else { return }
        if svc.tool == .text || svc.tool == .select || svc.tool == .eraser {
            isDragging = false
            let point = convert(event.locationInWindow, from: nil)
            svc.beginStroke(at: point, bounds: bounds)
            return
        }
        isDragging = true
        let point = convert(event.locationInWindow, from: nil)
        svc.beginStroke(at: point, bounds: bounds)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let svc = service, svc.isDrawingActive, isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        svc.continueStroke(at: point, bounds: bounds)
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
