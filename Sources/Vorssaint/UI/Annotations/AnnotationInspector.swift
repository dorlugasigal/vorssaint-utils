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
    var allowsHighlighter = false
    var showsStrokeColor = true
    var layoutChanged: () -> Void = {}
    @State private var expanded = false
    @ObservedObject private var localization = L10n.shared

    private var strings: ScreenshotFeatureStrings { FeatureStrings.screenshot(localization.language) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if showsStrokeColor {
                    AnnotationColorControl(color: $style.color, editingChanged: editingChanged,
                                           allowsAlpha: tool != .redact)
                        .frame(width: 32, height: 28)
                        .help(strings.colorLabel)
                }
                if tool != .text {
                    AnnotationVisualChoices(values: style.isHighlighter ? [CGFloat(10), 18, 28] : [CGFloat(2), 4, 7],
                        selection: $style.width,
                        label: { "\(strings.strokeLabel): \($0.formatted())" }, preview: { .width($0) })
                } else {
                    let labels = AnnotationTextStrings.labels(localization.language)
                    Picker(labels[0], selection: $style.fontFamily) {
                        ForEach(AnnotationStyle.FontFamily.allCases, id: \.rawValue) { family in
                            Text(labels[family.rawValue + 1]).tag(family)
                        }
                    }.frame(width: 160)
                    Toggle(isOn: $style.boldText) { Image(systemName: "bold") }
                        .toggleStyle(.button).help(labels[6]).accessibilityLabel(labels[6])
                }
                if tool != .text && !style.isHighlighter {
                    AnnotationVisualChoices(values: AnnotationStyle.Pattern.allCases, selection: $style.pattern,
                        label: { AnnotationStyleStrings.patternName($0, localization.language) },
                        preview: { .pattern($0) })
                    let characters = AnnotationStyleStrings.characters(localization.language)
                    AnnotationVisualChoices(values: AnnotationStyle.Character.allCases, selection: $style.character,
                        label: { characters[$0.rawValue + 1] }, preview: { .character($0) })
                }
            }
            if tool == .ellipse || (tool == .rect && style.shape != .axes) {
                HStack(spacing: 10) {
                    AnnotationVisualChoices(values: AnnotationStyle.Fill.allCases, selection: $style.fill,
                        label: { AnnotationStyleStrings.fillName($0, localization.language) },
                        preview: { .fill($0) })
                    AnnotationColorControl(color: $style.fillColor, editingChanged: editingChanged)
                        .frame(width: 32, height: 28)
                        .help(AnnotationStyleStrings.fill(localization.language))
                }
            }
            if tool == .line || tool == .arrow {
                let labels = AnnotationLinearStrings.labels(localization.language)
                HStack(spacing: 10) {
                    AnnotationVisualChoices(values: [false, true], selection: $style.curved,
                        label: { $0 ? labels[14] : strings.toolLine }, preview: { .route(curved: $0) })
                    AnnotationArrowheadChoice(selection: $style.startHead, isStart: true, label: labels[16])
                    AnnotationArrowheadChoice(selection: $style.endHead, isStart: false, label: labels[17])
                }
            }
            DisclosureGroup(isExpanded: $expanded) {
                advancedControls.padding(.top, 8)
            } label: {
                Label(AnnotationSessionStrings.moreOptions(localization.language), systemImage: "slider.horizontal.3")
                    .font(.caption)
            }
        }
        .onChange(of: expanded) { _, _ in layoutChanged() }
        .onChange(of: tool) { _, _ in expanded = false }
    }

    private var advancedControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
            if tool != .text {
                Image(systemName: "lineweight").help(strings.strokeLabel)
                Slider(value: $style.width, in: 1...40, onEditingChanged: editingChanged)
                    .frame(width: 60)
                    .accessibilityLabel(strings.strokeLabel)
            }
            if tool != .redact {
                Image(systemName: "circle.lefthalf.filled")
                Slider(value: $style.opacity, in: 0...1, onEditingChanged: editingChanged)
                    .frame(width: 85)
                    .accessibilityLabel(AnnotationSessionStrings.opacity(localization.language))
            }
            }
            if tool == .rect {
                HStack {
                    AnnotationVisualChoices(values: AnnotationStyle.Shape.allCases, selection: $style.shape,
                        label: { AnnotationDiagramStrings.title($0, localization.language) },
                        preview: { .shape($0) })
                    Slider(value: $style.roundness, in: 0...1, onEditingChanged: editingChanged)
                        .frame(width: 100)
                        .disabled(style.shape != .standard && style.shape != .diamond)
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
                    Toggle(AnnotationSessionStrings.negativeAxes(localization.language), isOn: $style.axisNegative)
                }
            }
            if tool == .line || tool == .arrow {
                let labels = AnnotationLinearStrings.labels(localization.language)
                HStack {
                    AnnotationVisualChoices(values: [CGFloat(0.75), 1, 1.5], selection: $style.headSize,
                        label: { "\(labels[18]): \(Double($0).formatted(.percent.precision(.fractionLength(0))))" },
                        preview: { .headSize($0) })
                    Slider(value: $style.headSize, in: 0.5...2, onEditingChanged: editingChanged)
                        .frame(width: 100)
                        .accessibilityLabel(labels[18])
                    Text(Double(style.headSize).formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .frame(width: 42)
                }
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
                if allowsHighlighter {
                    Toggle(FeatureStrings.annotation(localization.language).highlighter,
                           isOn: Binding(get: { style.isHighlighter }, set: { enabled in
                        var updated = style
                        updated.isHighlighter = enabled
                        updated.opacity = enabled ? 0.35 : 1
                        if enabled {
                            updated.color = AnnotationBrush.neonColors[0]
                            updated.pressure = .constant
                            updated.pattern = .solid
                            updated.character = .architect
                        }
                        style = updated
                    }))
                    if style.isHighlighter {
                        HStack {
                            ForEach(Array(AnnotationBrush.neonColors.enumerated()), id: \.offset) { _, color in
                                Button { style.color = color } label: {
                                    Circle().fill(Color(red: color.red, green: color.green, blue: color.blue))
                                        .frame(width: 18, height: 18)
                                        .overlay(Circle().strokeBorder(
                                            style.color == color ? Color.primary : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(strings.colorLabel)
                            }
                        }
                    }
                }
                if !style.isHighlighter {
                    Toggle(AnnotationInputStrings.smartDraw(localization.language), isOn: smartDraw)
                }
                HStack {
                    if !style.isHighlighter {
                        Picker(labels[0], selection: $style.pressure) {
                            ForEach(AnnotationStyle.Pressure.allCases, id: \.rawValue) { pressure in
                                Text(labels[pressure.rawValue + 1]).tag(pressure)
                            }
                        }
                        .frame(width: 190)
                    }
                    Toggle(labels[4], isOn: $style.smooth)
                }
            }
        }
    }
}

struct AnnotationColorControl: NSViewRepresentable {
    @Binding var color: AnnotationColor
    var editingChanged: (Bool) -> Void
    var allowsAlpha = true

    final class Well: NSColorWell {
        var willActivate: ((Well) -> Bool)?
        var didActivate: ((Well) -> Void)?
        var didDeactivate: (() -> Void)?

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if let rgb = color.usingColorSpace(.sRGB) {
                let luminance = (0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent
                                 + 0.0722 * rgb.blueComponent) * rgb.alphaComponent
                    + 0.85 * (1 - rgb.alphaComponent)
                let ink: NSColor = luminance > 0.5 ? .black : .white
                NSImage(systemSymbolName: "paintpalette.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [ink]))?
                    .draw(in: bounds.insetBy(dx: 7, dy: 5))
            }
        }

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
