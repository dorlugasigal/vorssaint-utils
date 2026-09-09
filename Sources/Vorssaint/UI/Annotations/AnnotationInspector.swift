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
    @Binding var expanded: Bool
    var editingChanged: (Bool) -> Void
    var tool: ScreenshotSupport.Tool
    var editPoints: (Bool) -> Void = { _ in }
    var smartDraw: Binding<Bool> = .constant(false)
    var allowsHighlighter = false
    var showsStrokeColor = true
    var layoutChanged: () -> Void = {}
    @ObservedObject private var localization = L10n.shared

    private var strings: ScreenshotFeatureStrings { FeatureStrings.screenshot(localization.language) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if showsStrokeColor {
                    AnnotationColorControl(color: $style.color, editingChanged: editingChanged,
                                           allowsAlpha: tool != .redact,
                                           title: AnnotationPickerStrings.text(.stroke, localization.language))
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
                    AnnotationVisualChoices(values: AnnotationStyle.Character.selectable, selection: $style.character,
                        label: { characters[$0.rawValue + 1] }, preview: { .character($0) })
                }
            }
            if tool == .ellipse || (tool == .rect && style.shape != .axes) {
                HStack(spacing: 10) {
                    AnnotationVisualChoices(values: AnnotationStyle.Fill.allCases, selection: $style.fill,
                        label: { AnnotationStyleStrings.fillName($0, localization.language) },
                        preview: { .fill($0) })
                    AnnotationColorControl(color: $style.fillColor, editingChanged: editingChanged,
                                           title: AnnotationStyleStrings.fill(localization.language))
                        .frame(width: 32, height: 28)
                        .help(AnnotationStyleStrings.fill(localization.language))
                }
            }
            if tool == .line || tool == .arrow {
                AnnotationArrowOptions(style: $style)
            }
            DisclosureGroup(isExpanded: $expanded) {
                advancedControls.padding(.top, 8)
            } label: {
                Label(AnnotationSessionStrings.moreOptions(localization.language), systemImage: "slider.horizontal.3")
                    .font(.caption)
            }
            .disclosureGroupStyle(AnnotationDisclosureStyle())
        }
        .onChange(of: expanded) { _, _ in layoutChanged() }
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
