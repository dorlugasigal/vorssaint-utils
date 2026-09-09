// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct AnnotationInspector: View {
    @Binding var style: AnnotationStyle
    var editingChanged: (Bool) -> Void
    var tool: ScreenshotSupport.Tool
    var editPoints: (Bool) -> Void = { _ in }
    var smartDraw: Binding<Bool> = .constant(false)
    @ObservedObject private var localization = L10n.shared

    private var strings: ScreenshotFeatureStrings { FeatureStrings.screenshot(localization.language) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
            AnnotationColorControl(color: Binding(get: { style.color }, set: { style.color = $0 }),
                                   editingChanged: editingChanged)
                .frame(width: 32, height: 24)
                .help(strings.colorLabel)
            AnnotationVisualChoices(values: [CGFloat(2), 4, 7], selection: $style.width,
                label: { "\(strings.strokeLabel): \($0.formatted())" },
                preview: { .width($0) })
            Slider(value: $style.width, in: 1...40, onEditingChanged: editingChanged)
                .frame(width: 60)
                .accessibilityLabel(strings.strokeLabel)
            Image(systemName: "circle.lefthalf.filled")
            Slider(value: $style.opacity, in: 0...1, onEditingChanged: editingChanged)
                .frame(width: 85)
                .accessibilityLabel(AnnotationSessionStrings.opacity(localization.language))
            }
            if tool == .rect || tool == .ellipse || tool == .line || tool == .arrow || tool == .freehand {
                let characters = AnnotationStyleStrings.characters(localization.language)
                Picker(characters[0], selection: $style.character) {
                    ForEach(AnnotationStyle.Character.allCases, id: \.rawValue) { character in
                        Text(characters[character.rawValue + 1]).tag(character)
                    }
                }
                .frame(width: 210)
                HStack(spacing: 10) {
                    AnnotationVisualChoices(values: AnnotationStyle.Pattern.allCases, selection: $style.pattern,
                        label: { AnnotationStyleStrings.patternName($0, localization.language) },
                        preview: { .pattern($0) })
                    if tool == .ellipse || (tool == .rect && style.shape != .axes) {
                        Divider().frame(height: 24)
                        AnnotationVisualChoices(values: AnnotationStyle.Fill.allCases, selection: $style.fill,
                            label: { AnnotationStyleStrings.fillName($0, localization.language) },
                            preview: { .fill($0) })
                        AnnotationColorControl(color: $style.fillColor, editingChanged: editingChanged)
                            .frame(width: 32, height: 24)
                            .help(AnnotationStyleStrings.fill(localization.language))
                    }
                }
            }
            if tool == .rect {
                HStack {
                    AnnotationVisualChoices(values: AnnotationStyle.Shape.allCases, selection: $style.shape,
                        label: { AnnotationDiagramStrings.title($0, localization.language) },
                        preview: { .shape($0) })
                    Slider(value: $style.roundness, in: 0...1, onEditingChanged: editingChanged)
                        .frame(width: 100)
                        .disabled(style.shape != .standard)
                        .accessibilityLabel(AnnotationStyleStrings.roundness(localization.language))
                }
                if style.shape == .grid {
                    let labels = AnnotationDiagramStrings.labels(localization.language)
                    HStack {
                        Stepper(value: $style.gridRows, in: 1...12) {
                            Label("\(style.gridRows)", systemImage: "rectangle.split.3x1")
                        }.help(labels[5]).accessibilityLabel(labels[5])
                        Stepper(value: $style.gridColumns, in: 1...12) {
                            Label("\(style.gridColumns)", systemImage: "rectangle.split.1x3")
                        }.help(labels[6]).accessibilityLabel(labels[6])
                    }
                    .fixedSize()
                }
                if style.shape == .axes {
                    Toggle(AnnotationDiagramStrings.labels(localization.language)[7], isOn: $style.axisTicks)
                }
            }
            if tool == .line || tool == .arrow {
                let labels = AnnotationLinearStrings.labels(localization.language)
                HStack {
                    AnnotationVisualChoices(values: [false, true], selection: $style.curved,
                        label: { $0 ? labels[14] : strings.toolLine },
                        preview: { .route(curved: $0) })
                    Toggle(isOn: $style.multiClick) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    .toggleStyle(.button)
                    .help(labels[15])
                    .accessibilityLabel(labels[15])
                    Button { editPoints(true) } label: { Image(systemName: "plus.circle") }.help(labels[19])
                    Button { editPoints(false) } label: { Image(systemName: "minus.circle") }.help(labels[20])
                }
                HStack {
                    AnnotationArrowheadChoice(selection: $style.startHead, isStart: true, label: labels[16])
                    AnnotationArrowheadChoice(selection: $style.endHead, isStart: false, label: labels[17])
                }
                Slider(value: $style.headSize, in: 1...1.75, onEditingChanged: editingChanged)
                    .frame(width: 120)
                    .accessibilityLabel(labels[18])
                Toggle(AnnotationLinearStrings.bindings(localization.language), isOn: $style.bindEndpoints)
            }
            if tool == .text {
                let labels = AnnotationTextStrings.labels(localization.language)
                HStack {
                    Picker(labels[0], selection: $style.fontFamily) {
                        ForEach(AnnotationStyle.FontFamily.allCases, id: \.rawValue) { family in
                            Text(labels[family.rawValue + 1]).tag(family)
                        }
                    }
                    .frame(width: 160)
                    Toggle(labels[6], isOn: $style.boldText)
                }
                HStack {
                    Slider(value: Binding(get: { style.textSize ?? 19 }, set: { style.textSize = $0 }),
                           in: 6...240, onEditingChanged: editingChanged)
                        .frame(width: 110)
                        .accessibilityLabel(labels[5])
                    Picker(labels[7], selection: $style.textAlignment) {
                        ForEach(AnnotationStyle.Alignment.allCases, id: \.rawValue) { alignment in
                            Text(labels[alignment.rawValue + 8]).tag(alignment)
                        }
                    }
                    .frame(width: 150)
                }
            }
            if tool == .freehand {
                let labels = AnnotationInputStrings.labels(localization.language)
                Toggle(AnnotationInputStrings.smartDraw(localization.language), isOn: smartDraw)
                HStack {
                    Picker(labels[0], selection: $style.pressure) {
                        ForEach(AnnotationStyle.Pressure.allCases, id: \.rawValue) { pressure in
                            Text(labels[pressure.rawValue + 1]).tag(pressure)
                        }
                    }
                    .frame(width: 190)
                    Toggle(labels[4], isOn: $style.smooth)
                }
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
        let swatchColor = AnnotationRenderer.color(AnnotationStyle(color: color, width: 1))
        button.image = NSImage(size: NSSize(width: 24, height: 16), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            outline.addClip()
            for row in 0..<2 {
                for column in 0..<3 {
                    ((row + column).isMultiple(of: 2) ? NSColor.white : NSColor.lightGray).setFill()
                    NSRect(x: CGFloat(column) * 8, y: CGFloat(row) * 8, width: 8, height: 8).fill()
                }
            }
            swatchColor.setFill()
            outline.fill()
            NSColor.separatorColor.setStroke()
            outline.lineWidth = 1
            outline.stroke()
            return true
        }
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
