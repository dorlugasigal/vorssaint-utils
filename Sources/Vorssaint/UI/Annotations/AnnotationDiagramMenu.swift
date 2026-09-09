// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AnnotationDiagramMenu: View {
    var selected: AnnotationStyle.Shape?
    var toolbarStyle = false
    var isRedacting = false
    var redact: (() -> Void)?
    var select: (AnnotationStyle.Shape) -> Void
    @ObservedObject private var localization = L10n.shared
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            VStack(spacing: 2) {
                Image(systemName: "square.on.circle")
                    .font(.system(size: toolbarStyle ? AnnotationUIMetrics.iconSize : 16)).frame(height: 22)
                if toolbarStyle {
                    Image(systemName: "chevron.down").font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: toolbarStyle ? AnnotationUIMetrics.toolSide : 33,
                   height: toolbarStyle ? AnnotationUIMetrics.toolSide : 32)
        }
        .buttonStyle(.borderless)
        .background(selected != nil || isRedacting || isPresented ? Color.accentColor.opacity(0.22) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .help(AnnotationSessionStrings.customShapes(localization.language))
        .accessibilityLabel(AnnotationSessionStrings.customShapes(localization.language))
        .accessibilityAddTraits(selected != nil || isRedacting ? .isSelected : [])
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AnnotationSessionStrings.customShapes(localization.language)).font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(86)), count: 3), spacing: 10) {
                    ForEach(AnnotationStyle.Shape.allCases.filter(\.isDiagram), id: \.rawValue) { shape in
                        Button {
                            isPresented = false
                            select(shape)
                        } label: {
                            VStack(spacing: 5) {
                                AnnotationPreviewTile(preview: .shape(shape), isSelected: selected == shape)
                                Text(AnnotationDiagramStrings.title(shape, localization.language))
                                    .font(.caption).lineLimit(2)
                            }.frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AnnotationDiagramStrings.title(shape, localization.language))
                        .accessibilityAddTraits(selected == shape ? .isSelected : [])
                    }
                }
                if let redact {
                    Divider()
                    Button {
                        isPresented = false
                        redact()
                    } label: {
                        Label(FeatureStrings.screenshot(localization.language).toolRedact, systemImage: "eye.slash")
                    }
                    .buttonStyle(.borderless)
                }
            }.padding(16)
        }
    }
}
