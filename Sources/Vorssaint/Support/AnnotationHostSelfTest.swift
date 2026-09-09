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
        let model = ScreenshotEditorModel(image: image, scale: 1, defaults: defaults)
        expect(!model.smartDrawEnabled, "Smart Draw defaults off")
        model.tool = .arrow
        model.beginDrag(at: CGPoint(x: 30, y: 40))
        model.endDrag(at: CGPoint(x: 170, y: 120), isTap: false)
        guard let arrow = model.annotations.first else { return ["annotation host: arrow creation"] }
        expect(model.selectedID == arrow.id && model.tool == .arrow, "arrow selected without switching creation tool")
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
        model.selectedID = nil
        style = model.inspectorStyle
        style.multiClick = true
        model.setInspectorStyle(style)
        let beforePath = model.annotations
        model.beginDrag(at: CGPoint(x: 30, y: 200))
        model.endDrag(at: CGPoint(x: 30, y: 200), isTap: true)
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
