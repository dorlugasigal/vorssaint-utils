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
    private(set) var strokes: [AnnotationStroke] = []
    @Published private(set) var selectedStrokeIndex: Int?
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
        strokes = ScreenAnnotationSupport.clear(strokes)
        drawingView?.needsDisplay = true
    }

    @objc func undo() {
        strokes = ScreenAnnotationSupport.undo(strokes)
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
        selectedStrokeIndex = nil
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
        if tool == .text {
            drawingView?.beginTextEditor(at: p)
            return
        }
        if tool == .select || tool == .eraser {
            let index = strokeIndex(at: p, bounds: bounds)
            selectedStrokeIndex = tool == .select ? index : nil
            if tool == .eraser, let index { strokes.remove(at: index) }
            drawingView?.needsDisplay = true
            return
        }
        let n = ScreenAnnotationSupport.normalized(
            point: AnnotationPoint(x: p.x, y: p.y),
            in: (Double(bounds.width), Double(bounds.height)))
        strokes.append(AnnotationStroke(tool: tool, color: color, width: width, points: [n, n]))
    }

    fileprivate func commitText(_ value: String, at p: NSPoint, bounds: CGRect) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let n = ScreenAnnotationSupport.normalized(
            point: AnnotationPoint(x: p.x, y: p.y),
            in: (Double(bounds.width), Double(bounds.height)))
        strokes.append(AnnotationStroke(tool: .text, color: color, width: width,
                                        points: [n], text: text))
        drawingView?.needsDisplay = true
    }

    private func strokeIndex(at p: NSPoint, bounds: CGRect) -> Int? {
        let point = CGPoint(x: p.x, y: p.y)
        for index in strokes.indices.reversed() {
            let stroke = strokes[index]
            let points = stroke.points.map {
                CGPoint(x: $0.x * Double(bounds.width), y: $0.y * Double(bounds.height))
            }
            guard let first = points.first else { continue }
            var hit = CGRect(x: first.x, y: first.y, width: 1, height: 1)
            for candidate in points.dropFirst() { hit = hit.union(CGRect(x: candidate.x, y: candidate.y, width: 1, height: 1)) }
            if stroke.tool == .text {
                hit.size.width = max(40, CGFloat(stroke.text.count) * max(8, stroke.width * 2.2))
                hit.size.height = max(24, stroke.width * 4)
            }
            let tolerance = max(12, stroke.width * 2)
            if hit.insetBy(dx: -tolerance, dy: -tolerance).contains(point) { return index }
        }
        return nil
    }

    fileprivate func continueStroke(at p: NSPoint, bounds: CGRect) {
        guard let i = strokes.indices.last else { return }
        let n = ScreenAnnotationSupport.normalized(
            point: AnnotationPoint(x: p.x, y: p.y),
            in: (Double(bounds.width), Double(bounds.height)))
        let s = strokes[i]
        let nextPoints: [AnnotationPoint]
        if s.tool.isFreehand {
            nextPoints = ScreenAnnotationSupport.append(n, to: s.points)
        } else {
            nextPoints = [s.points[0], n]
        }
        strokes[i] = AnnotationStroke(tool: s.tool, color: s.color, width: s.width,
                                       points: nextPoints)
    }

    fileprivate func strokeColor(for stroke: AnnotationStroke) -> NSColor {
        NSColor(calibratedRed: stroke.color.red,
                green: stroke.color.green,
                blue: stroke.color.blue,
                alpha: stroke.tool == .highlighter ? 0.35 : 1)
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
        for (index, stroke) in svc.strokes.enumerated() where !stroke.points.isEmpty {
            if stroke.tool == .text {
                let point = CGPoint(x: stroke.points[0].x * Double(bounds.width),
                                    y: stroke.points[0].y * Double(bounds.height))
                let font = NSFont.systemFont(ofSize: max(14, stroke.width * 3), weight: .medium)
                let textSize = (stroke.text as NSString).size(withAttributes: [.font: font])
                NSAttributedString(string: stroke.text,
                                    attributes: [.font: font,
                                                 .foregroundColor: svc.strokeColor(for: stroke)])
                    .draw(at: point)
                if svc.selectedStrokeIndex == index {
                    ctx.setStrokeColor(NSColor.systemBlue.cgColor)
                    ctx.setLineWidth(2)
                    ctx.setLineDash(phase: 0, lengths: [5, 3])
                    ctx.stroke(CGRect(x: point.x - 4, y: point.y - 4,
                                      width: textSize.width + 8, height: textSize.height + 8))
                }
                continue
            }
            guard stroke.points.count > 1 else { continue }
            let path = CGMutablePath()
            for (i, pt) in stroke.points.enumerated() {
                let x = pt.x * Double(bounds.width)
                let y = pt.y * Double(bounds.height)
                if i == 0 { path.move(to: .init(x: x, y: y)) }
                else       { path.addLine(to: .init(x: x, y: y)) }
            }
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(stroke.width)
            ctx.setStrokeColor(svc.strokeColor(for: stroke).cgColor)
            let start = CGPoint(x: stroke.points[0].x * Double(bounds.width),
                                y: stroke.points[0].y * Double(bounds.height))
            let end = CGPoint(x: stroke.points[1].x * Double(bounds.width),
                              y: stroke.points[1].y * Double(bounds.height))
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                              width: abs(end.x - start.x), height: abs(end.y - start.y))
            switch stroke.tool {
            case .rectangle:
                ctx.addRect(rect)
                ctx.strokePath()
            case .ellipse:
                ctx.strokeEllipse(in: rect)
            case .redact:
                ctx.setFillColor(svc.strokeColor(for: stroke).cgColor)
                ctx.fill(rect)
            case .arrow:
                ctx.setFillColor(svc.strokeColor(for: stroke).cgColor)
                ctx.addPath(ScreenshotSupport.arrowSilhouette(from: start, to: end,
                                                               strokeWidth: stroke.width))
                ctx.fillPath()
            case .line, .pen, .highlighter:
                ctx.addPath(path)
                ctx.strokePath()
            case .select, .text, .eraser:
                break
            }
            if svc.selectedStrokeIndex == index {
                ctx.setStrokeColor(NSColor.systemBlue.cgColor)
                ctx.setLineWidth(2)
                ctx.setLineDash(phase: 0, lengths: [5, 3])
                ctx.stroke(rect.insetBy(dx: -6, dy: -6))
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
        isDragging = false
        needsDisplay = true
    }
}
