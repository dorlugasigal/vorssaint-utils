// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum AnnotationColorPanels {
    static func close(owner: NSWindow?) { AnnotationColorControl.Coordinator.close(owner: owner) }
    static func closeCurrent() { AnnotationColorControl.Coordinator.closeCurrent() }
}

private struct CompactAnnotationPreference<Content: View>: View {
    let title: String
    var preview: AnnotationControlPreview?
    var symbol = "slider.horizontal.3"
    var width: CGFloat = 180
    @ViewBuilder var content: () -> Content
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            if let preview {
                AnnotationPreviewTile(preview: preview, isSelected: isPresented, side: 28)
            } else {
                Image(systemName: symbol).frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
        .popover(isPresented: $isPresented) {
            content().frame(width: width).padding(12)
        }
    }
}

struct AnnotationInspector: View {
    @Binding var style: AnnotationStyle
    var editingChanged: (Bool) -> Void
    var tool: ScreenshotSupport.Tool
    var smartDraw: Binding<Bool> = .constant(true)
    var allowsHighlighter = false
    var erasing = false
    var compact = false
    @ObservedObject private var localization = L10n.shared

    private var strings: ScreenshotFeatureStrings { FeatureStrings.screenshot(localization.language) }
    private var hasStroke: Bool { [.rect, .ellipse, .line, .arrow, .freehand].contains(tool) }
    private var supportsFill: Bool { tool == .ellipse || (tool == .rect && style.shape != .axes) }
    private func title(_ field: AnnotationPickerStrings.Field) -> String {
        AnnotationPickerStrings.text(field, localization.language)
    }

    var body: some View {
        if compact { compactBar } else { fullInspector }
    }

    private var fullInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            if erasing {
                widthSection
            } else {
                if hasStroke {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 8) { strokeSections }
                        VStack(spacing: 8) { strokeSections }
                    }
                } else if tool != .select && tool != .text { colorSection }
                if (supportsFill && style.hasVisibleFill)
                    || (tool == .rect && [.standard, .diamond, .grid, .axes].contains(style.shape)) || tool == .arrow
                    || (tool == .freehand && (!style.isHighlighter || allowsHighlighter)) {
                    Divider()
                }
                if tool == .rect && [.standard, .diamond, .grid].contains(style.shape) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 8) { if style.hasVisibleFill { fillSection }; shapeControls }
                        VStack(spacing: 8) { if style.hasVisibleFill { fillSection }; shapeControls }
                    }
                } else {
                    if style.hasVisibleFill && supportsFill { fillSection }
                    if tool == .rect { shapeControls }
                }
                if tool == .arrow { arrowSections }
                if tool == .text { textSections }
                if tool == .freehand { freehandSections }
            }
        }
        .transaction { $0.animation = nil }
    }

    @ViewBuilder private var strokeSections: some View {
        colorSection
        widthSection
        if !style.isHighlighter {
            AnnotationInspectorSection(title: AnnotationStyleStrings.pattern(localization.language),
                                       symbol: "line.3.horizontal") {
                AnnotationVisualChoices(values: AnnotationStyle.Pattern.allCases, selection: $style.pattern,
                    label: { AnnotationStyleStrings.patternName($0, localization.language) }, preview: { .pattern($0) })
            }
            AnnotationInspectorSection(title: title(.roughness), symbol: "scribble") {
                let names = AnnotationStyleStrings.characters(localization.language)
                AnnotationVisualChoices(values: AnnotationStyle.Character.selectable, selection: $style.character,
                    label: { names[$0.rawValue + 1] }, preview: { .character($0) })
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title(.stroke)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    AnnotationColorControl(color: $style.color, opacity: $style.opacity, editingChanged: editingChanged,
                                           allowsAlpha: tool != .redact, title: title(.stroke),
                                           suggestedColors: style.isHighlighter ? AnnotationBrush.neonColors : AnnotationColorPalette.colors)
                        .frame(width: 36, height: 36)
                }
                if supportsFill {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AnnotationStyleStrings.fill(localization.language)).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        AnnotationColorControl(color: fillColorBinding, opacity: $style.opacity, editingChanged: editingChanged,
                                               title: AnnotationStyleStrings.fill(localization.language))
                            .frame(width: 36, height: 36)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fillColorBinding: Binding<AnnotationColor> {
        Binding(get: {
            var color = style.fillColor
            if style.fill == .none { color.alpha = 0 }
            return color
        }, set: { color in
            var updated = style
            updated.setFillColor(color)
            style = updated
        })
    }

    private var compactBar: some View {
        HStack(spacing: 6) {
            AnnotationColorControl(color: $style.color, opacity: $style.opacity, editingChanged: editingChanged,
                                   allowsAlpha: tool != .redact, title: title(.stroke),
                                   suggestedColors: style.isHighlighter ? AnnotationBrush.neonColors : AnnotationColorPalette.colors,
                                   side: 28)
                .frame(width: 28, height: 28)
            if supportsFill {
                AnnotationColorControl(color: fillColorBinding, opacity: $style.opacity, editingChanged: editingChanged,
                                       title: AnnotationStyleStrings.fill(localization.language), side: 28)
                    .frame(width: 28, height: 28)
            }
            if hasStroke {
                CompactAnnotationPreference(title: title(.width), symbol: "lineweight") { widthSection }
                if !style.isHighlighter {
                    CompactAnnotationPreference(title: AnnotationStyleStrings.pattern(localization.language), preview: .pattern(style.pattern)) {
                        AnnotationVisualChoices(values: AnnotationStyle.Pattern.allCases, selection: $style.pattern,
                            label: { AnnotationStyleStrings.patternName($0, localization.language) }, preview: { .pattern($0) })
                    }
                    CompactAnnotationPreference(title: title(.roughness), symbol: "scribble") {
                        let names = AnnotationStyleStrings.characters(localization.language)
                        AnnotationVisualChoices(values: AnnotationStyle.Character.selectable, selection: $style.character,
                            label: { names[$0.rawValue + 1] }, preview: { .character($0) })
                    }
                }
            }
            if supportsFill && style.hasVisibleFill {
                CompactAnnotationPreference(title: AnnotationStyleStrings.fill(localization.language), preview: .fill(style.fill)) { fillSection }
            }
            if tool == .rect && [.standard, .diamond, .grid, .axes].contains(style.shape) {
                let edges = style.shape == .standard || style.shape == .diamond
                CompactAnnotationPreference(title: edges ? title(.edges) : AnnotationDiagramStrings.title(style.shape, localization.language),
                                            preview: edges ? .edges(rounded: style.roundness > 0) : .shape(style.shape),
                                            width: 280) { shapeControls }
            }
            if tool == .arrow {
                CompactAnnotationPreference(title: title(.heads), preview: .route(curved: style.curved), width: 560) { arrowSections }
            }
            if tool == .text {
                CompactAnnotationPreference(title: AnnotationTextStrings.labels(localization.language)[0],
                                            symbol: "textformat", width: 380) { textSections }
            }
            if tool == .freehand {
                CompactAnnotationPreference(title: AnnotationInputStrings.labels(localization.language)[0],
                                            preview: .pressure(style.pressure), width: 340) { freehandSections }
            }
        }
    }

    private var widthSection: some View {
        AnnotationInspectorSection(title: title(erasing ? .eraserSize : .width),
                                   symbol: erasing ? "eraser" : "lineweight") {
            AnnotationVisualChoices(values: erasing ? [CGFloat(8), 16, 28]
                : style.isHighlighter ? [CGFloat(10), 18, 28] : [CGFloat(2), 4, 7],
                selection: $style.width, label: { "\(title(.width)): \($0.formatted())" }, preview: { .width($0) })
            HStack(spacing: 8) {
                Slider(value: $style.width, in: 1...40, onEditingChanged: editingChanged)
                    .frame(width: 88).accessibilityLabel(title(erasing ? .eraserSize : .width))
                Text(style.width, format: .number.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit()).frame(width: 28)
            }
        }
    }

    private var fillSection: some View {
        AnnotationInspectorSection(title: AnnotationStyleStrings.fill(localization.language),
                                   symbol: "square.lefthalf.filled") {
            AnnotationVisualChoices(values: [.solid, .hatch, .crossHatch], selection: $style.fill,
                label: { AnnotationStyleStrings.fillName($0, localization.language) }, preview: { .fill($0) })
        }
    }

    @ViewBuilder private var shapeControls: some View {
        if style.shape == .standard || style.shape == .diamond {
            AnnotationInspectorSection(title: title(.edges),
                                       symbol: "rectangle.roundedtop") {
                AnnotationVisualChoices(values: [false, true],
                    selection: Binding(get: { style.roundness > 0 }, set: { style.roundness = $0 ? max(0.25, style.roundness) : 0 }),
                    label: { title($0 ? .rounded : .sharp) }, preview: { .edges(rounded: $0) })
            }
        } else if style.shape == .grid {
            let names = AnnotationDiagramStrings.labels(localization.language)
            AnnotationInspectorSection(title: AnnotationDiagramStrings.title(.grid, localization.language),
                                       symbol: "grid") {
                HStack(spacing: 8) {
                    Stepper("\(names[5]): \(style.gridRows)", value: $style.gridRows, in: 1...12)
                    Stepper("\(names[6]): \(style.gridColumns)", value: $style.gridColumns, in: 1...12)
                }
            }
        } else if style.shape == .axes {
            AnnotationInspectorSection(title: AnnotationDiagramStrings.title(.axes, localization.language),
                                       symbol: "arrow.up.and.right") {
                Toggle(AnnotationDiagramStrings.labels(localization.language)[7], isOn: $style.axisTicks)
                Toggle(AnnotationSessionStrings.negativeAxes(localization.language), isOn: $style.axisNegative)
            }
        }
    }

    private var arrowSections: some View {
        let names = AnnotationLinearStrings.labels(localization.language)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) { arrowControls(names) }
            VStack(spacing: 8) { arrowControls(names) }
        }
    }

    @ViewBuilder private func arrowControls(_ names: [String]) -> some View {
        AnnotationInspectorSection(title: title(.heads), symbol: "arrow.left.and.right") {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(names[16]).font(.caption).foregroundStyle(.secondary)
                    AnnotationArrowheadChoice(selection: $style.startHead, isStart: true, label: names[16])
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(names[17]).font(.caption).foregroundStyle(.secondary)
                    AnnotationArrowheadChoice(selection: $style.endHead, isStart: false, label: names[17])
                }
            }
        }
        AnnotationInspectorSection(title: title(.route), symbol: "arrow.up.right") {
            AnnotationVisualChoices(values: [false, true], selection: $style.curved,
                label: { $0 ? names[14] : strings.toolLine }, preview: { .route(curved: $0) })
        }
        AnnotationInspectorSection(title: names[18], symbol: "arrow.up.left.and.arrow.down.right") {
            AnnotationVisualChoices(values: [CGFloat(0.75), 1, 1.5], selection: $style.headSize,
                label: { "\(names[18]): \(Int($0 * 100))%" }, preview: { .headSize($0) })
            HStack(spacing: 8) {
                Slider(value: $style.headSize, in: 0.5...2, onEditingChanged: editingChanged)
                    .frame(width: 84).accessibilityLabel(names[18])
                Text(Double(style.headSize).formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit()).frame(width: 38)
            }
        }
    }

    private var textSections: some View {
        let names = AnnotationTextStrings.labels(localization.language)
        return VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if !compact { colorSection }
                AnnotationInspectorSection(title: names[0], symbol: "textformat") {
                    HStack(spacing: 12) {
                        Picker(names[0], selection: $style.fontFamily) {
                            ForEach(AnnotationStyle.FontFamily.allCases, id: \.rawValue) { family in
                                Text(names[family.rawValue + 1]).tag(family)
                            }

                        }.labelsHidden().frame(width: 150).accessibilityLabel(names[0])
                        Button { style.boldText.toggle() } label: {
                            Image(systemName: "bold").font(.system(size: 16, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .background(style.boldText ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain).help(names[6]).accessibilityLabel(names[6])
                        .accessibilityAddTraits(style.boldText ? .isSelected : [])
                    }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                AnnotationInspectorSection(title: names[5], symbol: "textformat.size") {
                    HStack {
                        Slider(value: Binding(get: { style.textSize ?? 19 }, set: { style.textSize = $0 }),
                               in: 6...240, onEditingChanged: editingChanged).accessibilityLabel(names[5])
                        Text(style.textSize ?? 19, format: .number.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit()).frame(width: 34)
                    }
                }
                AnnotationInspectorSection(title: names[7], symbol: "text.alignleft") {
                    Picker(names[7], selection: $style.textAlignment) {
                        ForEach(AnnotationStyle.Alignment.allCases, id: \.rawValue) { alignment in
                            Image(systemName: alignment == .left ? "text.alignleft" : alignment == .center
                                  ? "text.aligncenter" : "text.alignright").tag(alignment)
                                .accessibilityLabel(names[alignment.rawValue + 8])
                        }
                    }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(names[7])
                }
            }
        }
    }

    @ViewBuilder private var freehandSections: some View {
        if !style.isHighlighter {
            let names = AnnotationInputStrings.labels(localization.language)
            AnnotationInspectorSection(title: names[0], symbol: "pencil.tip") {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(AnnotationStyle.Pressure.selectable, id: \.rawValue) { pressure in
                        Button { style.pressure = pressure } label: {
                            VStack(spacing: 6) {
                                AnnotationPreviewTile(preview: .pressure(pressure), isSelected: style.pressure == pressure)
                                Text(names[pressure.rawValue + 1]).font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(names[pressure.rawValue + 1])
                        .accessibilityAddTraits(style.pressure == pressure ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                    Toggle(AnnotationInputStrings.smartDraw(localization.language), isOn: smartDraw)
                        .toggleStyle(.checkbox)
                }
            }
        }
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
        }
    }

}
