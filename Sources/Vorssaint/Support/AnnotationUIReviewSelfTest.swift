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
                select: { _ in }, opacityChanged: { _ in }, sample: {}, done: {})), dark: dark)
            render("short-viewport-\(suffix)", host: NSHostingController(rootView:
                AnnotationInspectorViewport(maximumHeight: 120) {
                    AnnotationInspector(style: .constant(AnnotationStyle(color: .blue, width: 4)),
                                        editingChanged: { _ in }, tool: .freehand)
                }.frame(width: 616).background(.regularMaterial)), dark: dark, maximumHeight: 120)
        }
        guard let context = CGContext(data: nil, width: 640, height: 400, bitsPerComponent: 8, bytesPerRow: 2560,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { fail("screenshot fixture") }
        context.setFillColor(CGColor(gray: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
        guard let image = context.makeImage() else { fail("screenshot fixture image") }
        let capture = ScreenshotSelectionController.Capture(image: image, scale: 1, anchorRect: .zero)
        let screenshot = ScreenshotEditorController(capture: capture, defaults: defaults)
        screenshot.model.tool = .rect
        screenshot.model.beginDrag(at: CGPoint(x: 40, y: 40))
        screenshot.model.endDrag(at: CGPoint(x: 200, y: 140), isTap: false)
        render("screenshot-bottom-preferences", host: NSHostingController(rootView:
            ScreenshotEditorView(model: screenshot.model, controller: screenshot).frame(width: 1000, height: 700)),
               dark: true, maximumWidth: 1000)
        render("rough-rectangle-comparison", host: NSHostingController(rootView:
            Canvas { context, _ in
                context.withCGContext { cg in
                    for (index, rounded) in [false, true].enumerated() {
                        var rectangle = AnnotationElement(tool: .rect,
                            rect: CGRect(x: 30 + index * 370, y: 50, width: 300, height: 300),
                            style: AnnotationStyle(color: .red, width: 3, roundness: rounded ? 0.5 : 0, character: .cartoonist))
                        rectangle.roughSeed = 42
                        AnnotationRenderer.draw(rectangle, in: cg, scale: 1, shadowsEnabled: false)
                    }
                }
                context.draw(Text("Sharp / per-edge strokes").foregroundColor(.white), at: CGPoint(x: 170, y: 22))
                context.draw(Text("Rounded / per-edge strokes").foregroundColor(.white), at: CGPoint(x: 550, y: 22))
            }.frame(width: 730, height: 390).background(Color(white: 0.08))),
               dark: true, maximumWidth: 730)
        render("all-rough-shapes", host: NSHostingController(rootView:
            Canvas { context, _ in
                let shapes: [(String, ScreenshotSupport.Tool, AnnotationStyle.Shape, CGFloat)] = [
                    ("Square", .rect, .standard, 0), ("Rounded", .rect, .standard, 0.5),
                    ("Ellipse", .ellipse, .standard, 0), ("Diamond", .rect, .diamond, 0),
                    ("Database", .rect, .database, 0), ("Queue", .rect, .queue, 0),
                    ("Person", .rect, .person, 0), ("Grid", .rect, .grid, 0)
                ]
                for (index, item) in shapes.enumerated() {
                    let x = CGFloat(index % 4) * 230 + 20, y = CGFloat(index / 4) * 250 + 40
                    context.draw(Text(item.0).foregroundColor(.white), at: CGPoint(x: x + 95, y: y - 20))
                    context.withCGContext { cg in
                        var shape = AnnotationElement(tool: item.1, rect: CGRect(x: x, y: y, width: 190, height: 190),
                            style: AnnotationStyle(color: .green, width: 3, shape: item.2,
                                                   roundness: item.3, character: .cartoonist))
                        shape.roughSeed = 42
                        AnnotationRenderer.draw(shape, in: cg, scale: 1, shadowsEnabled: false)
                    }
                }
            }.frame(width: 920, height: 500).background(Color(white: 0.08))),
               dark: true, maximumWidth: 920)
        render("selected-shape-handles", host: NSHostingController(rootView:
            Canvas { context, _ in
                context.withCGContext { cg in
                    var shape = AnnotationElement(tool: .rect, rect: CGRect(x: 80, y: 100, width: 250, height: 160),
                        style: AnnotationStyle(color: .green, width: 3, roundness: 0.5, character: .cartoonist))
                    shape.rotation = CGFloat.pi / 6
                    shape.roughSeed = 42
                    AnnotationRenderer.draw(shape, in: cg, scale: 1, shadowsEnabled: false)
                    cg.concatenate(AnnotationGeometry.transform(shape))
                    cg.setStrokeColor(NSColor.systemBlue.cgColor)
                    cg.setLineWidth(1)
                    cg.setLineDash(phase: 0, lengths: [5, 3])
                    cg.stroke(shape.rect.insetBy(dx: -3, dy: -3))
                    AnnotationRenderer.drawLocalResizeHandles(shape, in: cg)
                }
            }.frame(width: 420, height: 360).background(Color(white: 0.08))), dark: true)
        var style = AnnotationStyle(color: .blue, width: 4)
        style.textAlignment = .center
        let editor = AnnotationNativeTextEditor(element: AnnotationElement(tool: .text, text: "Centered",
                                                                          style: style, centersTextVertically: true), scale: 1)
        editor.frame = CGRect(x: 0, y: 0, width: 300, height: 160)
        editor.layoutSubtreeIfNeeded()
        let textView = editor.textView
        guard textView.alignment == .center,
              textView.textContainerInset.height > 0,
              abs((textView.textContainer?.containerSize.width ?? 0) + 4 - editor.bounds.width) < 1 else {
            fail("centered native text container")
        }
        editor.text = "Longer line\nshort"
        let secondLine = (editor.text as NSString).range(of: "short").location
        for alignment in AnnotationStyle.Alignment.allCases {
            style.textAlignment = alignment
            textView.setSelectedRange(NSRange(location: secondLine, length: 0))
            editor.applyStyle(AnnotationElement(tool: .text, text: editor.text, style: style), scale: 1)
            for location in [0, secondLine] {
                let paragraph = textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
                guard paragraph?.alignment == AnnotationRenderer.alignment(alignment) else {
                    fail("alignment applies to every paragraph")
                }
            }
            guard textView.selectedRange().location == secondLine, textView.textContainerInset.height == 0 else {
                fail("alignment preserves caret and ordinary top anchoring")
            }
        }
        var largeStyle = AnnotationStyle(color: .blue, width: 4, textSize: 120)
        largeStyle.fontFamily = .serif
        var largeText = AnnotationElement(tool: .text, rect: CGRect(x: 100, y: 100, width: 0, height: 0),
                                         text: "Large text\nSecond line\nThird line", style: largeStyle)
        largeText.rect = AnnotationRenderer.textBounds(largeText, scale: 1)
        let largeEditor = AnnotationNativeTextEditor(element: largeText, scale: 1)
        largeEditor.frame = AnnotationTextPlacement.editorFrame(for: largeText,
            bounds: CGRect(x: 0, y: 0, width: 2000, height: 1500))
        largeEditor.layoutSubtreeIfNeeded()
        guard let container = largeEditor.textView.textContainer, let manager = largeEditor.textView.layoutManager else {
            fail("large text layout")
        }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        guard largeEditor.textView.enclosingScrollView == nil,
              largeEditor.frame.width > 400, largeEditor.frame.height > 200,
              used.maxX + largeEditor.textView.textContainerInset.width <= largeEditor.bounds.width + 1,
              used.maxY + largeEditor.textView.textContainerInset.height <= largeEditor.bounds.height + 1 else {
            fail("large text must fit without an inner scrolling editor")
        }
        defaults.removePersistentDomain(forName: suite)
        print("ANNOTATION UI OK: all tools, both appearances, constrained viewport and native text")
        exit(0)
    }

    private static func render(_ name: String, host: NSViewController, dark: Bool,
                               maximumHeight: CGFloat = 900, maximumWidth: CGFloat = 648) {
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
              size.width <= maximumWidth + 0.5, size.height <= maximumHeight + 0.5 else { fail("bounds for \(name): \(size)") }
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
