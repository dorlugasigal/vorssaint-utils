// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct AnnotationInspector: View {
    @Binding var style: AnnotationStyle
    var editingChanged: (Bool) -> Void
    var tool: ScreenshotSupport.Tool
    var editPoints: (Bool) -> Void = { _ in }
    @ObservedObject private var localization = L10n.shared

    private var strings: ScreenshotFeatureStrings { FeatureStrings.screenshot(localization.language) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
            AnnotationColorControl(color: Binding(get: { style.color }, set: { style.color = $0 }),
                                   editingChanged: editingChanged)
                .frame(width: 32, height: 24)
                .help(strings.colorLabel)
            Image(systemName: "lineweight").help(strings.strokeLabel)
            Slider(value: $style.width, in: 1...40, onEditingChanged: editingChanged)
                .frame(width: 85)
                .accessibilityLabel(strings.strokeLabel)
            Image(systemName: "circle.lefthalf.filled")
            Slider(value: $style.opacity, in: 0...1, onEditingChanged: editingChanged)
                .frame(width: 85)
                .accessibilityLabel(AnnotationSessionStrings.opacity(localization.language))
            }
            if tool == .rect || tool == .ellipse || tool == .line || tool == .arrow || tool == .freehand {
                HStack(spacing: 10) {
                    Picker(AnnotationStyleStrings.pattern(localization.language), selection: $style.pattern) {
                        ForEach(AnnotationStyle.Pattern.allCases, id: \.rawValue) { pattern in
                            Text(AnnotationStyleStrings.patternName(pattern, localization.language)).tag(pattern)
                        }
                    }
                    .frame(width: 145)
                    if tool == .rect || tool == .ellipse {
                        Picker(AnnotationStyleStrings.fill(localization.language), selection: $style.fill) {
                            ForEach(AnnotationStyle.Fill.allCases, id: \.rawValue) { fill in
                                Text(AnnotationStyleStrings.fillName(fill, localization.language)).tag(fill)
                            }
                        }
                        .frame(width: 160)
                        AnnotationColorControl(color: $style.fillColor, editingChanged: editingChanged)
                            .frame(width: 32, height: 24)
                            .help(AnnotationStyleStrings.fill(localization.language))
                    }
                }
            }
            if tool == .rect {
                HStack {
                    Picker(strings.toolRect, selection: $style.shape) {
                        Text(strings.toolRect).tag(AnnotationStyle.Shape.standard)
                        Text(AnnotationStyleStrings.diamond(localization.language)).tag(AnnotationStyle.Shape.diamond)
                    }
                    .frame(width: 160)
                    Slider(value: $style.roundness, in: 0...1, onEditingChanged: editingChanged)
                        .frame(width: 100)
                        .accessibilityLabel(AnnotationStyleStrings.roundness(localization.language))
                }
            }
            if tool == .line || tool == .arrow {
                let labels = AnnotationLinearStrings.labels(localization.language)
                HStack {
                    Toggle(labels[14], isOn: $style.curved)
                    Toggle(labels[15], isOn: $style.multiClick)
                    Button { editPoints(true) } label: { Image(systemName: "plus.circle") }.help(labels[19])
                    Button { editPoints(false) } label: { Image(systemName: "minus.circle") }.help(labels[20])
                }
                HStack {
                    Picker(labels[16], selection: $style.startHead) {
                        ForEach(AnnotationArrowhead.allCases, id: \.rawValue) { head in
                            Text(AnnotationLinearStrings.head(head, localization.language)).tag(head)
                        }
                    }
                    Picker(labels[17], selection: $style.endHead) {
                        ForEach(AnnotationArrowhead.allCases, id: \.rawValue) { head in
                            Text(AnnotationLinearStrings.head(head, localization.language)).tag(head)
                        }
                    }
                }
                Slider(value: $style.headSize, in: 1...1.75, onEditingChanged: editingChanged)
                    .frame(width: 120)
                    .accessibilityLabel(labels[18])
            }
        }
    }
}

private struct AnnotationColorControl: NSViewRepresentable {
    @Binding var color: AnnotationColor
    var editingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.bezelStyle = .rounded
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.control = self
        button.image = NSImage(systemSymbolName: "paintpalette.fill", accessibilityDescription: nil)
        button.contentTintColor = AnnotationRenderer.color(AnnotationStyle(color: color, width: 1))
    }

    func makeCoordinator() -> Coordinator { Coordinator(control: self) }

    static func dismantleNSView(_ nsView: NSButton, coordinator: Coordinator) { coordinator.close() }

    final class Coordinator: NSObject {
        private static weak var active: Coordinator?
        var control: AnnotationColorControl
        private weak var owner: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var panel: NSColorPanel?

        init(control: AnnotationColorControl) { self.control = control }

        @objc func open(_ button: NSButton) {
            guard let owner = button.window, let screen = owner.screen else {
                NSSound.beep()
                return
            }
            Self.active?.close()
            // A private panel leaves every other feature's shared color panel
            // target, action and active wells untouched.
            let panel = NSColorPanel(contentRect: CGRect(x: 0, y: 0, width: 280, height: 420),
                                     styleMask: [.titled, .closable, .utilityWindow],
                                     backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            self.panel = panel
            self.owner = owner
            Self.active = self
            control.editingChanged(true)
            panel.parent?.removeChildWindow(panel)
            owner.addChildWindow(panel, ordered: .above)
            panel.level = NSWindow.Level(rawValue: owner.level.rawValue + 1)
            panel.showsAlpha = true
            panel.isContinuous = true
            panel.setTarget(self)
            panel.setAction(#selector(changed(_:)))
            panel.color = AnnotationRenderer.color(AnnotationStyle(color: control.color, width: 1))
            let anchor = owner.convertToScreen(button.convert(button.bounds, to: nil))
            panel.setFrameOrigin(AnnotationPanelPlacement.origin(anchor: anchor, size: panel.frame.size,
                                                                 visibleFrame: screen.visibleFrame))
            for window in [owner, panel] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                        self?.close()
                    })
            }
            panel.makeKeyAndOrderFront(nil)
        }

        @objc private func changed(_ panel: NSColorPanel) {
            guard let rgb = panel.color.usingColorSpace(.sRGB) else { NSSound.beep(); return }
            control.color = AnnotationColor(red: rgb.redComponent, green: rgb.greenComponent,
                                            blue: rgb.blueComponent, alpha: rgb.alphaComponent)
        }

        func close() {
            guard let panel else { return }
            self.panel = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            panel.orderOut(nil)
            panel.parent?.removeChildWindow(panel)
            panel.setTarget(nil)
            panel.setAction(nil)
            panel.close()
            control.editingChanged(false)
            owner?.makeKey()
            owner = nil
            if Self.active === self { Self.active = nil }
        }
    }
}
