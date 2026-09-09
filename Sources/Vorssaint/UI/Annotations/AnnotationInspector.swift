// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum AnnotationColorPanels {
    static func close(owner: NSWindow?) { AnnotationColorControl.Coordinator.close(owner: owner) }
    static func closeCurrent() { AnnotationColorControl.Coordinator.closeCurrent() }
}

struct AnnotationInspector: View {
    @Binding var style: AnnotationStyle
    var editingChanged: (Bool) -> Void
    var tool: ScreenshotSupport.Tool
    var editPoints: (Bool) -> Void = { _ in }
    var smartDraw: Binding<Bool> = .constant(false)
    var constructionMode: Binding<Bool> = .constant(false)
    var canEditPoints = false
    var canRemovePoints = false
    @ObservedObject private var localization = L10n.shared

    private var strings: ScreenshotFeatureStrings { FeatureStrings.screenshot(localization.language) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
            AnnotationColorControl(color: Binding(get: { style.color }, set: { style.color = $0 }),
                                   editingChanged: editingChanged, allowsAlpha: tool != .redact)
                .frame(width: 32, height: 24)
                .help(strings.colorLabel)
            if tool != .text {
                Image(systemName: "lineweight").help(strings.strokeLabel)
                Slider(value: $style.width, in: 1...40, onEditingChanged: editingChanged)
                    .frame(width: 85)
                    .accessibilityLabel(strings.strokeLabel)
            }
            if tool != .redact {
                Image(systemName: "circle.lefthalf.filled")
                Slider(value: $style.opacity, in: 0...1, onEditingChanged: editingChanged)
                    .frame(width: 85)
                    .accessibilityLabel(AnnotationSessionStrings.opacity(localization.language))
            }
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
                    Toggle(labels[15], isOn: constructionMode)
                    Button { editPoints(true) } label: { Image(systemName: "plus.circle") }.help(labels[19])
                        .disabled(!canEditPoints)
                    Button { editPoints(false) } label: { Image(systemName: "minus.circle") }.help(labels[20])
                        .disabled(!canRemovePoints)
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
                Toggle(FeatureStrings.annotation(localization.language).highlighter,
                       isOn: Binding(get: { style.isHighlighter }, set: {
                           var updated = style
                           updated.isHighlighter = $0
                           updated.opacity = $0 ? 0.35 : 1
                           style = updated
                       }))
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
    var allowsAlpha = true

    final class Well: NSColorWell {
        var willActivate: ((Well) -> Bool)?
        var didActivate: ((Well) -> Void)?
        var didDeactivate: (() -> Void)?

        override func activate(_ exclusive: Bool) {
            guard willActivate?(self) == true else { return }
            super.activate(true)
            didActivate?(self)
        }

        override func deactivate() {
            super.deactivate()
            didDeactivate?()
        }
    }

    func makeNSView(context: Context) -> Well {
        let well = Well(frame: .zero)
        well.target = context.coordinator
        well.action = #selector(Coordinator.changed(_:))
        well.willActivate = { [weak coordinator = context.coordinator] in coordinator?.prepare($0) ?? false }
        well.didActivate = { [weak coordinator = context.coordinator] in coordinator?.position($0) }
        well.didDeactivate = { [weak coordinator = context.coordinator] in coordinator?.close() }
        return well
    }

    func updateNSView(_ well: Well, context: Context) {
        context.coordinator.control = self
        context.coordinator.synchronize(well)
    }

    func makeCoordinator() -> Coordinator { Coordinator(control: self) }

    static func dismantleNSView(_ nsView: Well, coordinator: Coordinator) { coordinator.close() }

    final class Coordinator: NSObject {
        private static weak var active: Coordinator?
        var control: AnnotationColorControl
        private weak var owner: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var panel: NSColorPanel?
        private weak var well: Well?
        private var synchronizing = false
        private var saved: (level: NSWindow.Level, frame: CGRect, color: NSColor,
                            alpha: Bool, continuous: Bool, mode: NSColorPanel.Mode, parent: NSWindow?)?

        init(control: AnnotationColorControl) { self.control = control }

        static func close(owner: NSWindow?) {
            if let active, active.owner === owner { active.close() }
        }

        static func closeCurrent() { active?.close() }

        func synchronize(_ well: Well) {
            let color = AnnotationRenderer.color(AnnotationStyle(color: control.color, width: 1))
            guard well.color != color else { return }
            synchronizing = true
            well.color = color
            synchronizing = false
        }

        func prepare(_ well: Well) -> Bool {
            guard let owner = well.window, owner.screen != nil else {
                NSSound.beep()
                return false
            }
            let continuing = Self.active?.owner === owner
            Self.active?.close(commit: !continuing)
            let panel = NSColorPanel.shared
            saved = (panel.level, panel.frame, panel.color, panel.showsAlpha,
                     panel.isContinuous, panel.mode, panel.parent)
            self.panel = panel
            self.well = well
            self.owner = owner
            Self.active = self
            if !continuing { control.editingChanged(true) }
            panel.parent?.removeChildWindow(panel)
            owner.addChildWindow(panel, ordered: .above)
            panel.level = NSWindow.Level(rawValue: owner.level.rawValue + 1)
            panel.showsAlpha = control.allowsAlpha
            panel.isContinuous = true
            for window in [owner, panel] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                        self?.close()
                    })
            }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: owner, queue: .main) { [weak self, weak well] _ in
                        if let well { self?.position(well) }
                    })
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self, weak well] _ in
                    if let well { self?.position(well) }
                })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
                    self?.clampPanel()
                })
            position(well)
            return true
        }

        func position(_ well: Well) {
            guard let panel, let owner, let screen = owner.screen else { return }
            let anchor = owner.convertToScreen(well.convert(well.bounds, to: nil))
            panel.level = NSWindow.Level(rawValue: owner.level.rawValue + 1)
            panel.setFrameOrigin(AnnotationPanelPlacement.origin(anchor: anchor, size: panel.frame.size,
                                                                 visibleFrame: screen.visibleFrame))
        }

        private func clampPanel() {
            guard let panel, let visible = owner?.screen?.visibleFrame else { return }
            let origin = CGPoint(x: min(max(panel.frame.minX, visible.minX), max(visible.minX, visible.maxX - panel.frame.width)),
                                 y: min(max(panel.frame.minY, visible.minY), max(visible.minY, visible.maxY - panel.frame.height)))
            if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        }

        @objc func changed(_ well: NSColorWell) {
            guard !synchronizing else { return }
            guard let rgb = well.color.usingColorSpace(.sRGB) else { NSSound.beep(); return }
            control.color = AnnotationColor(red: rgb.redComponent, green: rgb.greenComponent,
                                            blue: rgb.blueComponent, alpha: rgb.alphaComponent)
        }

        func close(commit: Bool = true) {
            guard let panel else { return }
            self.panel = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            panel.orderOut(nil)
            panel.parent?.removeChildWindow(panel)
            well?.deactivate()
            well = nil
            if let saved {
                panel.level = saved.level
                panel.showsAlpha = saved.alpha
                panel.isContinuous = saved.continuous
                panel.mode = saved.mode
                panel.color = saved.color
                panel.setFrame(saved.frame, display: false)
                saved.parent?.addChildWindow(panel, ordered: .above)
            }
            saved = nil
            if commit { control.editingChanged(false) }
            owner?.makeKey()
            owner = nil
            if Self.active === self { Self.active = nil }
        }
    }
}
