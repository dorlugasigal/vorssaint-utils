// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
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
        .frame(width: 28, height: 28)
        .frame(width: 38, height: 38)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(isHovered ? 0.10 : 0.04),
                    in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.14),
                              lineWidth: isSelected ? 1.5 : 1)
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
    @State private var showsAdvanced = false

    private let common: [AnnotationArrowhead] = [.none, .arrow, .triangle, .triangleOutline]

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 3) {
                AnnotationPreviewTile(preview: .head(selection, start: isStart))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .help("\(label): \(AnnotationLinearStrings.head(selection, localization.language))")
        .accessibilityLabel(label)
        .accessibilityValue(AnnotationLinearStrings.head(selection, localization.language))
        .onChange(of: isPresented) { _, presented in
            if !presented { showsAdvanced = false }
        }
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                headGrid(common)
                DisclosureGroup(AnnotationSessionStrings.moreOptions(localization.language), isExpanded: $showsAdvanced) {
                    headGrid(AnnotationArrowhead.allCases.filter { $0 != .legacy && !common.contains($0) })
                        .padding(.top, 8)
                    }
                    .font(.caption)
            }
            .padding(12)
        }
    }

    private func headGrid(_ heads: [AnnotationArrowhead]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 6), count: 4), spacing: 6) {
            ForEach(heads, id: \.rawValue) { head in
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
}
