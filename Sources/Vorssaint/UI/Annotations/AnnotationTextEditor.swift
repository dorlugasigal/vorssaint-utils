// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Both hosts use the same native text system, including marked text, native
/// selection and multiline insertion. Inspector focus does not end the edit.
final class AnnotationNativeTextEditor: NSScrollView, NSTextViewDelegate {
    private final class TextView: NSTextView {
        var commit: (() -> Void)?
        var cancel: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.contains(.command), event.keyCode == 36, !hasMarkedText() {
                commit?()
            } else { super.keyDown(with: event) }
        }

        override func cancelOperation(_ sender: Any?) {
            if hasMarkedText() { super.cancelOperation(sender) } else { cancel?() }
        }
    }

    private let editor = TextView()
    var changed: ((String) -> Void)?
    var committed: ((String) -> Void)?
    var cancelled: (() -> Void)?
    var text: String {
        get { editor.string }
        set { if editor.string != newValue && !editor.hasMarkedText() { editor.string = newValue } }
    }

    init(element: AnnotationElement, scale: CGFloat) {
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = true
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = true
        editor.textContainerInset = NSSize(width: 2, height: 0)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: 100_000, height: 100_000)
        editor.minSize = NSSize(width: 100, height: 40)
        editor.maxSize = NSSize(width: 100_000, height: 100_000)
        editor.delegate = self
        editor.string = element.text
        editor.commit = { [weak self] in
            guard let self else { return }
            self.committed?(self.editor.string)
        }
        editor.cancel = { [weak self] in self?.cancelled?() }
        documentView = editor
        applyStyle(element, scale: scale)
    }

    required init?(coder: NSCoder) { nil }

    func applyStyle(_ element: AnnotationElement, scale: CGFloat) {
        let font = AnnotationRenderer.font(element, scale: scale)
        if editor.font != font { editor.font = font }
        editor.textColor = AnnotationRenderer.color(element.resolvedStyle)
        editor.insertionPointColor = editor.textColor ?? .textColor
        editor.alignment = AnnotationRenderer.alignment(element.resolvedStyle.textAlignment)
        sizeTextContainer()
    }

    func focus() { window?.makeFirstResponder(editor) }
    func textDidChange(_ notification: Notification) {
        sizeTextContainer()
        changed?(editor.string)
    }

    private func sizeTextContainer() {
        let text = editor.string.isEmpty ? " " : editor.string
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: 100_000, height: 100_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: editor.font ?? NSFont.systemFont(ofSize: 19)]).size
        let width = max(20, ceil(measured.width) + 8)
        editor.textContainer?.containerSize = NSSize(width: width, height: 100_000)
        editor.setFrameSize(NSSize(width: max(100, width), height: max(80, ceil(measured.height) + 20)))
    }
}

struct AnnotationTextEditor: NSViewRepresentable {
    @Binding var text: String
    var element: AnnotationElement
    var scale: CGFloat
    var commit: (String) -> Void
    var cancel: () -> Void

    func makeNSView(context: Context) -> AnnotationNativeTextEditor {
        let view = AnnotationNativeTextEditor(element: element, scale: scale)
        view.changed = { text = $0 }
        view.committed = commit
        view.cancelled = cancel
        DispatchQueue.main.async { view.focus() }
        return view
    }

    func updateNSView(_ view: AnnotationNativeTextEditor, context: Context) {
        view.applyStyle(element, scale: scale)
        view.changed = { text = $0 }
        view.committed = commit
        view.cancelled = cancel
    }
}
