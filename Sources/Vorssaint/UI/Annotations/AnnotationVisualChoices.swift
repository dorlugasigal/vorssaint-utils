// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AnnotationPreviewTile: View {
    var preview: AnnotationControlPreview
    var isSelected = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Canvas { context, size in
            let ink = colorScheme == .dark ? 0.94 : 0.12
            context.withCGContext { cg in
                cg.saveGState()
                cg.scaleBy(x: size.width / 120, y: size.height / 120)
                preview.draw(in: cg, color: AnnotationColor(red: ink, green: ink, blue: ink))
                cg.restoreGState()
            }
        }
        .frame(width: 26, height: 26)
        .frame(width: AnnotationUIMetrics.tileSide, height: AnnotationUIMetrics.tileSide)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(isHovered ? 0.09 : 0.025),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.14),
                              lineWidth: isSelected ? 2 : 1)
        }
        .onHover { isHovered = $0 }
        .accessibilityHidden(true)
    }
}

struct AnnotationVisualChoices<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    var label: (Value) -> String
    var preview: (Value) -> AnnotationControlPreview

    var body: some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { value in
                Button { selection = value } label: {
                    AnnotationPreviewTile(preview: preview(value), isSelected: selection == value)
                }
                .buttonStyle(.plain)
                .help(label(value))
                .accessibilityLabel(label(value))
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
    }
}

struct AnnotationArrowheadChoice: View {
    @Binding var selection: AnnotationArrowhead
    var isStart: Bool
    var label: String
    @ObservedObject private var localization = L10n.shared
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 4) {
                AnnotationPreviewTile(preview: .head(selection, start: isStart), isSelected: isPresented)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .help("\(label): \(AnnotationLinearStrings.head(selection, localization.language))")
        .accessibilityLabel(label)
        .accessibilityValue(AnnotationLinearStrings.head(selection, localization.language))
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text(label).font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: 4), spacing: 8) {
                    ForEach(AnnotationArrowhead.allCases, id: \.rawValue) { head in
                        Button {
                            selection = head
                            isPresented = false
                        } label: {
                            AnnotationPreviewTile(preview: .head(head, start: isStart), isSelected: selection == head)
                        }
                        .buttonStyle(.plain)
                        .help(AnnotationLinearStrings.head(head, localization.language))
                        .accessibilityLabel(AnnotationLinearStrings.head(head, localization.language))
                        .accessibilityAddTraits(selection == head ? .isSelected : [])
                    }
                }
            }
            .padding(16)
        }
    }
}
