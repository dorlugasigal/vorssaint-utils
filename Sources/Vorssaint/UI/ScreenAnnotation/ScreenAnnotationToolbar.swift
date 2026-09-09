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

    private var strings: ScreenAnnotationStrings { FeatureStrings.annotation(localization.language) }
    private var width: CGFloat { min(AnnotationUIMetrics.toolbarWidth, service.toolbarAvailableSize.width) }
    private var hasSelection: Bool { !service.selectedIDs.isEmpty }
    private var showsInspector: Bool { hasSelection || service.tool != .select }

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(AnnotationToolShortcuts.primaryEntries, id: \.choice) { entry in
                        Button { service.setToolChoice(entry.choice) } label: {
                            VStack(spacing: 2) {
                                Image(systemName: toolSymbol(entry.choice))
                                    .font(.system(size: AnnotationUIMetrics.iconSize)).frame(height: 22)
                                Text(entry.keys.first ?? " ").font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: AnnotationUIMetrics.toolSide, height: AnnotationUIMetrics.toolSide)
                        }
                        .buttonStyle(.plain)
                        .background(service.toolChoice == entry.choice ? Color.accentColor.opacity(0.20) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .help(entry.keys.isEmpty ? toolTitle(entry.choice)
                              : "\(toolTitle(entry.choice)) (\(entry.keys.joined(separator: ", ")))")
                        .accessibilityLabel(toolTitle(entry.choice))
                        .accessibilityAddTraits(service.toolChoice == entry.choice ? .isSelected : [])
                    }
                    AnnotationDiagramMenu(
                        selected: service.tool == .rectangle && service.inspectorStyle.shape.isDiagram
                            ? service.inspectorStyle.shape : nil,
                        toolbarStyle: true, isRedacting: service.tool == .redact,
                        redact: { service.setToolChoice(.tool(.redact)) },
                        select: { service.setToolChoice(.shape($0)) })
                }
                .frame(minWidth: max(0, width - 24))
            }
            .frame(height: AnnotationUIMetrics.toolSide)
            Divider()
            if showsInspector {
                AnnotationInspectorViewport(
                    maximumHeight: max(40, service.toolbarAvailableSize.height - AnnotationUIMetrics.chromeHeight
                                       - (service.hasLinearConstruction ? 36 : 0))) {
                    VStack(spacing: 8) {
                        AnnotationInspector(style: Binding(get: { service.inspectorStyle }, set: service.setInspectorStyle),
                                            editingChanged: service.styleEditingChanged, tool: service.inspectorTool,
                                            smartDraw: $service.smartDrawEnabled,
                                            erasing: service.tool == .eraser)
                            .disabled(service.selectionIsLocked)
                    }
                }
            }
            if service.hasLinearConstruction {
                HStack {
                    Button(FeatureStrings.screenshot(localization.language).done) { service.finishLinearConstruction() }
                    Button(FeatureStrings.screenshot(localization.language).cancel, action: service.cancelLinearConstruction)
                    Spacer()
                }
            }
            Divider()
            footer
        }
        .buttonStyle(.borderless)
        .padding(12)
        .frame(width: width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                .frame(width: 24, height: 32).overlay(NativeWindowDragHandle())
                .help(AnnotationSessionStrings.moveToolbar(localization.language))
                .accessibilityLabel(AnnotationSessionStrings.moveToolbar(localization.language))
            AnnotationSelectionMenu(hasSelection: hasSelection, perform: service.performSelectionAction)
            Button { service.cycleBackground() } label: {
                Image(systemName: "rectangle.on.rectangle").frame(width: 28, height: 32)
            }
            .help(FeatureStrings.screenshot(localization.language).backdropLabel)
            .accessibilityLabel(FeatureStrings.screenshot(localization.language).backdropLabel)
            Picker("", selection: Binding(get: { service.isDrawingActive }, set: {
                    if $0 != service.isDrawingActive { service.toggleDrawing() }
                })) {
                    Label(AnnotationSessionStrings.mode(true, localization.language), systemImage: "pencil.tip").tag(true)
                    Label(AnnotationSessionStrings.mode(false, localization.language), systemImage: "cursorarrow").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 176)
                .accessibilityLabel("\(AnnotationSessionStrings.mode(true, localization.language)) / \(AnnotationSessionStrings.mode(false, localization.language))")
                .frame(height: 32)
            if let hint = service.escapeHint {
                Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
            } else if let shortcut = service.activationShortcutHint {
                Text("\(shortcut): \(AnnotationSessionStrings.mode(true, localization.language))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            footerButton("arrow.uturn.backward", title: strings.undo, enabled: service.canUndo, action: service.undo)
            footerButton("arrow.uturn.forward", title: localization.s.menuRedo, enabled: service.canRedo, action: service.redo)
            footerButton("trash", title: strings.clear, enabled: !service.strokes.isEmpty, action: service.clearAll)
            Button(action: service.hideOverlay) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                    if service.isDrawingActive, let shortcut = service.activationShortcutHint {
                        Text(shortcut).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.frame(minWidth: 32, minHeight: 32)
            }.help(strings.exit).accessibilityLabel(strings.exit)
        }
        .font(.system(size: 13))
    }

    private func footerButton(_ symbol: String, title: String, enabled: Bool = true,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 32, height: 32) }
            .help(title).accessibilityLabel(title).disabled(!enabled)
    }

    private func toolTitle(_ choice: AnnotationToolChoice) -> String {
        let screenshot = FeatureStrings.screenshot(localization.language)
        if case .shape(let shape) = choice { return AnnotationDiagramStrings.title(shape, localization.language) }
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
        if case .shape(let shape) = choice { return shape.symbolName }
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
        case .redact: return "eye.slash"
        }
    }
}
