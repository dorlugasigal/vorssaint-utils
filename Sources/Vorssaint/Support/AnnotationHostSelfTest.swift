// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum AnnotationHostSelfTest {
    static func run() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ label: String) {
            if !condition { failures.append("annotation host: \(label)") }
        }
        let suite = "com.vorssaint.annotation-selftest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite),
              let context = CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 1280,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { return ["annotation host: fixture creation"] }
        defer { defaults.removePersistentDomain(forName: suite) }
        failures.append(contentsOf: ScreenAnnotationService.runDataSelfTest(defaults: defaults))
        let typing = ScreenshotEditorModel(image: image, scale: 1, defaults: defaults)
        typing.tool = .text
        typing.beginDrag(at: CGPoint(x: 20, y: 20))
        typing.endDrag(at: CGPoint(x: 20, y: 20), isTap: true)
        if let id = typing.editingTextID {
            typing.updateTextDraft(id, text: "Keep this\ntext")
            typing.tool = .rect
            expect(typing.editingTextID == nil && typing.annotations.first?.text == "Keep this\ntext",
                   "switching screenshot tools commits the current text draft")
            typing.undo()
            expect(typing.annotations.isEmpty, "tool-switch text commit is one undo step")
        } else { expect(false, "tool-switch text fixture opens") }
        for tool in [ScreenshotSupport.Tool.rect, .ellipse, .arrow, .line] {
            let shapes = ScreenshotEditorModel(image: image, scale: 1, defaults: defaults)
            shapes.tool = tool
            shapes.beginDrag(at: CGPoint(x: 40, y: 40))
            shapes.endDrag(at: CGPoint(x: 160, y: 120), isTap: false)
            expect(shapes.tool == .select && shapes.selectedID == shapes.annotations.first?.id,
                   "\(tool) creation switches to Select and retains the element")
            shapes.undo()
            expect(shapes.annotations.isEmpty, "\(tool) creation undo remains atomic")
        }
        for tool in [ScreenshotSupport.Tool.select, .rect, .ellipse, .freehand] {
            let text = ScreenshotEditorModel(image: image, scale: 1, defaults: defaults)
            text.tool = tool
            text.beginDrag(at: CGPoint(x: 200, y: 150))
            text.endDrag(at: CGPoint(x: 200, y: 150), isTap: true, clickCount: 2)
            expect(text.editingTextID != nil && text.annotations.count == 1 && text.annotations[0].tool == .text,
                   "double click enters text from \(tool) without a leftover draft")
            if let id = text.editingTextID { text.commitText(id, text: "Note") }
            text.undo()
            expect(text.annotations.isEmpty, "double-click text creation is one undo step")
        }
        let labels = ScreenshotEditorModel(image: image, scale: 1, defaults: defaults)
        labels.tool = .rect
        labels.beginDrag(at: CGPoint(x: 40, y: 40))
        labels.endDrag(at: CGPoint(x: 160, y: 120), isTap: false)
        let shape = labels.annotations
        labels.beginDrag(at: CGPoint(x: 42, y: 80))
        labels.endDrag(at: CGPoint(x: 42, y: 80), isTap: true, clickCount: 2)
        expect(labels.editingTextID != nil && labels.annotations.count == 2, "shape double click starts a label")
        if let id = labels.editingTextID {
            labels.commitText(id, text: "Centered\nlabel")
            expect(labels.annotations.last?.rect.midX == 100 && labels.annotations.last?.rect.midY == 80,
                   "shape label remains centered after commit")
        }
        labels.undo()
        expect(labels.annotations == shape, "label undo preserves its shape")
        for tool in [ScreenshotSupport.Tool.select, .text] {
            let clicks = ScreenshotEditorModel(image: image, scale: 1, defaults: defaults)
            clicks.tool = .text
            clicks.beginDrag(at: CGPoint(x: 30, y: 30))
            clicks.endDrag(at: CGPoint(x: 30, y: 30), isTap: true)
            guard let id = clicks.editingTextID else { return failures + ["annotation host: text click fixture"] }
            clicks.commitText(id, text: "Edit this text")
            clicks.tool = tool
            if tool == .select { clicks.selectedID = nil }
            let rect = clicks.annotations[0].rect
            let point = CGPoint(x: rect.midX, y: rect.midY)
            clicks.beginDrag(at: point)
            clicks.continueDrag(to: point)
            clicks.endDrag(at: point, isTap: true)
            expect(clicks.editingTextID == id, "stationary first pointer event reopens text with \(tool)")
            clicks.cancelActiveEdit()
        }
        let model = ScreenshotEditorModel(image: image, scale: 1, defaults: defaults)
        expect(model.smartDrawEnabled, "Smart Draw defaults on")
        model.smartDrawEnabled = false
        expect(!ScreenshotEditorModel(image: image, scale: 1, defaults: defaults).smartDrawEnabled,
               "explicit Smart Draw opt-out is preserved")
        model.smartDrawEnabled = true
        model.tool = .arrow
        model.beginDrag(at: CGPoint(x: 30, y: 40))
        model.endDrag(at: CGPoint(x: 170, y: 120), isTap: false)
        guard let arrow = model.annotations.first else { return ["annotation host: arrow creation"] }
        expect(model.selectedID == arrow.id && model.tool == .select, "arrow completion switches to Select")
        model.beginDrag(at: CGPoint(x: 170, y: 120))
        model.endDrag(at: CGPoint(x: 210, y: 150), isTap: false)
        expect(model.annotations.count == 1 && model.annotations[0].points.last == CGPoint(x: 210, y: 150),
               "selected arrow endpoint edits instead of creating another arrow")
        model.undo()
        expect(model.annotations == [arrow], "one undo restores the endpoint edit")
        model.undo()
        expect(model.annotations.isEmpty, "next undo removes creation")
        model.redo()
        model.redo()
        model.tool = .text
        model.beginDrag(at: CGPoint(x: 20, y: 180))
        model.endDrag(at: CGPoint(x: 20, y: 180), isTap: true)
        guard let textID = model.editingTextID else { return ["annotation host: text edit opening"] }
        model.commitText(textID, text: "  first\nsecond  \n")
        expect(model.annotations.last?.text == "  first\nsecond  \n", "native text commit preserves whitespace")
        model.undo()
        expect(model.annotations.count == 1, "new multiline text is one undo step")
        model.redo()
        model.performSelectionAction(.selectAll)
        model.performSelectionAction(.lock)
        let locked = model.annotations
        model.deleteSelected()
        expect(model.annotations == locked, "locked annotations cannot be deleted")
        model.performSelectionAction(.unlock)
        model.tool = .crop
        model.cropDraft = CGRect(x: 10, y: 10, width: 200, height: 180)
        let beforeCrop = model.annotations
        model.applyCrop()
        expect(model.baseImage.width == 200 && model.baseImage.height == 180, "crop keeps pixel dimensions")
        model.undo()
        expect(model.baseImage === image && model.annotations == beforeCrop, "crop and annotations restore atomically")
        let exported = model.exportImage(withBackdrop: false)
        expect(exported?.width == 320 && exported?.height == 240, "shared annotation export retains source pixel size")
        model.selectedID = arrow.id
        model.tool = .arrow
        model.selectedID = arrow.id
        var style = model.inspectorStyle
        style.curved = true
        model.setInspectorStyle(style)
        guard let curved = model.annotations.first(where: { $0.id == arrow.id }) else { return failures }
        let control = AnnotationLinear.controls(curved)[0]
        model.beginDrag(at: control)
        model.endDrag(at: CGPoint(x: control.x, y: control.y - 35), isTap: false)
        expect(model.annotations.count == 2 && model.annotations[0].controls.count == 2,
               "curve control editing works while Arrow stays active")
        model.undo()
        let beforePath = model.annotations
        model.beginDrag(at: CGPoint(x: 30, y: 200))
        model.endDrag(at: CGPoint(x: 30, y: 200), isTap: true)
        expect(model.hasLinearConstruction
            && Array(model.annotations.prefix(beforePath.count)) == beforePath,
               "click starts a new path without a mode switch or changing existing annotations")
        model.beginDrag(at: CGPoint(x: 150, y: 200))
        model.endDrag(at: CGPoint(x: 150, y: 200), isTap: true)
        expect(model.hasLinearConstruction, "multi-click creation remains pending until finish")
        model.finishLinearConstruction()
        expect(model.annotations.count == beforePath.count + 1, "multi-click finish creates exactly one path")
        model.undo()
        expect(model.annotations == beforePath, "multi-click path undo is atomic")
        model.beginDrag(at: CGPoint(x: 10, y: 10))
        model.cancelActiveEdit()
        model.continueDrag(to: CGPoint(x: 100, y: 100))
        model.endDrag(at: CGPoint(x: 100, y: 100), isTap: false)
        expect(model.annotations == beforePath && model.canRedo, "cancelled gestures ignore remaining drag events and preserve redo")
        model.tool = .freehand
        style = model.inspectorStyle
        style.isHighlighter = true
        style.opacity = 0.35
        model.setInspectorStyle(style)
        model.beginDrag(at: CGPoint(x: 5, y: 30))
        for index in 1...1500 { model.continueDrag(to: CGPoint(x: index + 5, y: 30)) }
        model.endDrag(at: CGPoint(x: 1506, y: 30), isTap: false)
        expect(model.annotations.last?.points.count == 1502 && model.annotations.last?.resolvedStyle.isHighlighter == true,
               "screenshot freehand highlighter keeps long strokes distinct from rectangular Highlight")
        return failures
    }
}
