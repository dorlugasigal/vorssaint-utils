// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AnnotationDiagramMenu: View {
    var selected: AnnotationStyle.Shape?
    var select: (AnnotationStyle.Shape) -> Void
    @ObservedObject private var localization = L10n.shared

    var body: some View {
        Menu {
            ForEach(AnnotationStyle.Shape.allCases.filter(\.isDiagram), id: \.rawValue) { shape in
                Button { select(shape) } label: {
                    Label(AnnotationDiagramStrings.title(shape, localization.language), systemImage: shape.symbolName)
                }
            }
        } label: {
            Image(systemName: selected?.symbolName ?? "square.on.circle")
                .frame(width: 27, height: 28)
                .foregroundStyle(selected == nil ? Color.primary : Color.accentColor)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(AnnotationSessionStrings.customShapes(localization.language))
        .accessibilityLabel(AnnotationSessionStrings.customShapes(localization.language))
    }
}
