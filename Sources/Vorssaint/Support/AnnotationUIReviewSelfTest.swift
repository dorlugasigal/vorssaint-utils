// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum AnnotationUIReviewSelfTest {
    static func runAndExit() -> Never {
        _ = NSApplication.shared
        let suite = "com.vorssaint.annotation-ui-review.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fail("isolated defaults") }
        let choices: [(String, AnnotationToolChoice)] = [
            ("select", .tool(.select)), ("rectangle", .shape(.standard)), ("diamond", .shape(.diamond)),
            ("ellipse", .tool(.ellipse)), ("arrow", .tool(.arrow)), ("line", .tool(.line)),
            ("pen", .tool(.pen)), ("highlighter", .tool(.highlighter)), ("text", .tool(.text)),
            ("eraser", .tool(.eraser)), ("database", .shape(.database)), ("queue", .shape(.queue)),
            ("person", .shape(.person)), ("grid", .shape(.grid)), ("axes", .shape(.axes)),
            ("redact", .tool(.redact))
        ]
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            defaults.set(true, forKey: DefaultsKey.screenAnnotationShortcutEnabled)
            defaults.set(GlobalShortcut.screenAnnotationDefault.storageValue, forKey: DefaultsKey.screenAnnotationShortcut)
            for (name, choice) in choices {
                let service = ScreenAnnotationService.makeUIReviewService(defaults: defaults, choice: choice)
                render("toolbar-\(name)-\(suffix)", host: ScreenAnnotationToolbar.makeController(service: service),
                       dark: dark, maximumHeight: choice.tool == .line ? 340 : 600)
            }
            defaults.set("control+option+command:103", forKey: DefaultsKey.screenAnnotationShortcut)
            let interact = ScreenAnnotationService.makeUIReviewService(defaults: defaults, choice: .tool(.select), drawing: false)
            render("interact-shortcut-\(suffix)", host: ScreenAnnotationToolbar.makeController(service: interact), dark: dark)
            defaults.set(false, forKey: DefaultsKey.screenAnnotationShortcutEnabled)
            let disabled = ScreenAnnotationService.makeUIReviewService(defaults: defaults, choice: .tool(.pen))
            render("shortcut-disabled-\(suffix)", host: ScreenAnnotationToolbar.makeController(service: disabled), dark: dark)
            render("palette-\(suffix)", host: NSHostingController(rootView: AnnotationColorPaletteView(
                state: AnnotationPaletteState(color: .blue), title: "Stroke color", allowsAlpha: true,
                select: { _ in }, sample: {}, done: {})), dark: dark)
            render("short-viewport-\(suffix)", host: NSHostingController(rootView:
                AnnotationInspectorViewport(maximumHeight: 120) {
                    AnnotationInspector(style: .constant(AnnotationStyle(color: .blue, width: 4)),
                                        editingChanged: { _ in }, tool: .freehand)
                }.frame(width: 616).background(.regularMaterial)), dark: dark, maximumHeight: 120)
        }
        var style = AnnotationStyle(color: .blue, width: 4)
        style.textAlignment = .center
        let editor = AnnotationNativeTextEditor(element: AnnotationElement(tool: .text, text: "Centered", style: style), scale: 1)
        editor.frame = CGRect(x: 0, y: 0, width: 300, height: 160)
        editor.layoutSubtreeIfNeeded()
        guard let textView = editor.documentView as? NSTextView, textView.alignment == .center,
              textView.textContainerInset.height > 0,
              abs((textView.textContainer?.containerSize.width ?? 0) + 4 - editor.contentSize.width) < 1 else {
            fail("centered native text container")
        }
        defaults.removePersistentDomain(forName: suite)
        print("ANNOTATION UI OK: all tools, both appearances, constrained viewport and native text")
        exit(0)
    }

    private static func render(_ name: String, host: NSViewController, dark: Bool, maximumHeight: CGFloat = 900) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.view.appearance = appearance
        let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 648, height: 600),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentViewController = host
        let view = host.view
        // Let geometry preferences settle without showing or activating any window.
        for _ in 0..<6 {
            view.layoutSubtreeIfNeeded()
            view.setFrameSize(view.fittingSize)
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let size = view.fittingSize
        print("ANNOTATION UI: \(name) \(size)")
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              size.width <= 648.5, size.height <= maximumHeight + 0.5 else { fail("bounds for \(name): \(size)") }
        view.setFrameSize(size)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fail("bitmap for \(name)") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let directory = ProcessInfo.processInfo.environment["VORSSAINT_ANNOTATION_UI_OUTPUT"] {
            guard let data = bitmap.representation(using: .png, properties: [:]) else { fail("encoding \(name)") }
            do {
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            } catch { fail("writing \(name): \(error)") }
        }
        window.contentViewController = nil
        window.close()
    }

    private static func fail(_ message: String) -> Never {
        print("ANNOTATION UI FAILED: \(message)")
        exit(1)
    }
}
