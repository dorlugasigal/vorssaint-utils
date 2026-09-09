// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum ScreenAnnotationToolbar {
    static func makeController(service: ScreenAnnotationService) -> NSViewController {
        NSHostingController(rootView: AnnotationToolbarView(service: service))
    }
}

private struct AnnotationToolbarView: View {
    @ObservedObject var service: ScreenAnnotationService
    @ObservedObject private var localization = L10n.shared

    private let presetColors: [AnnotationColor] = [
        .red, .orange, .yellow, .green, .blue, .purple, .black, .white
    ]
    private var strings: ScreenAnnotationStrings { FeatureStrings.annotation(localization.language) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(AnnotationToolShortcuts.entries, id: \.choice) { entry in
                    Button { service.setToolChoice(entry.choice) } label: {
                        VStack(spacing: 2) {
                            Image(systemName: toolSymbol(entry.choice)).frame(height: 21)
                            Text(entry.keys.first ?? " ").font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 34, height: 36)
                    }
                    .buttonStyle(.borderless)
                    .background(service.toolChoice == entry.choice ? Color.accentColor.opacity(0.22) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .help(entry.keys.isEmpty ? toolTitle(entry.choice)
                          : "\(toolTitle(entry.choice)) (\(entry.keys.joined(separator: ", ")))")
                    .accessibilityLabel(toolTitle(entry.choice))
                    .accessibilityAddTraits(service.toolChoice == entry.choice ? .isSelected : [])
                }
            }
            Divider()
            HStack(spacing: 9) {
                ForEach(Array(presetColors.enumerated()), id: \.offset) { _, color in
                    Button { service.setColor(color) } label: {
                        Circle()
                            .fill(Color(red: color.red, green: color.green, blue: color.blue))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(
                                service.color == color ? Color.primary : Color.clear, lineWidth: 2.5))
                    }
                    .buttonStyle(.borderless)
                }
                Divider().frame(height: 20)
                Button { service.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help(strings.undo)
                    .disabled(!service.canUndo)
                Button { service.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .help(localization.s.menuRedo)
                    .disabled(!service.canRedo)
                Divider().frame(height: 20)
                Button { service.clearAll() } label: { Image(systemName: "trash") }
                    .help(strings.clear)
            }
            AnnotationInspector(style: Binding(get: { service.inspectorStyle }, set: service.setInspectorStyle),
                                editingChanged: service.styleEditingChanged, tool: service.inspectorTool,
                                editPoints: service.editLinearPoints, smartDraw: $service.smartDrawEnabled)
            HStack {
                if service.hasLinearConstruction {
                    Button(FeatureStrings.screenshot(localization.language).done, action: service.finishLinearConstruction)
                    Button(FeatureStrings.screenshot(localization.language).cancel, action: service.cancelLinearConstruction)
                }
                AnnotationSelectionMenu(hasSelection: !service.selectedIDs.isEmpty, perform: service.performSelectionAction)
                Button { service.cycleBackground() } label: { Image(systemName: "square.fill") }
                    .help(FeatureStrings.screenshot(localization.language).backdropLabel)
                Button { service.toggleDrawing() } label: {
                    Label(AnnotationSessionStrings.mode(service.isDrawingActive, localization.language),
                          systemImage: service.isDrawingActive ? "pencil.tip" : "cursorarrow")
                }

                Spacer()
                Button { service.hideOverlay() } label: { Image(systemName: "xmark") }
                    .help(strings.exit)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func toolTitle(_ choice: AnnotationToolChoice) -> String {
        let screenshot = FeatureStrings.screenshot(localization.language)
        if choice == .shape(.diamond) { return AnnotationStyleStrings.diamond(localization.language) }
        switch choice.tool {
        case .select: return screenshot.toolSelect
        case .pen: return strings.pen
        case .highlighter: return strings.highlighter
        case .arrow: return screenshot.toolArrow
        case .line: return screenshot.toolLine
        case .rectangle: return screenshot.toolRect
        case .ellipse: return screenshot.toolEllipse
        case .text: return screenshot.toolText
        case .redact: return screenshot.toolRedact
        case .eraser: return localization.s.actionRemove
        }
    }

    private func toolSymbol(_ choice: AnnotationToolChoice) -> String {
        if choice == .shape(.diamond) { return "diamond" }
        switch choice.tool {
        case .select: return "cursorarrow"
        case .pen: return "pencil"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .eraser: return "eraser"
        case .redact: return "rectangle.fill"
        }
    }
}
