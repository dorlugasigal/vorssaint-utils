// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum AnnotationControlPreview {
    case fill(AnnotationStyle.Fill)
    case pattern(AnnotationStyle.Pattern)
    case width(CGFloat)
    case shape(AnnotationStyle.Shape)
    case route(curved: Bool)
    case head(AnnotationArrowhead, start: Bool)

    func draw(in context: CGContext, color: AnnotationColor) {
        // A fixed logical canvas keeps the production arrowhead metrics legible
        // when scaled down to the small inspector tiles.
        var style = AnnotationStyle(color: color, width: 5)
        style.fillColor = color
        style.endHead = .none
        var element = AnnotationElement(tool: .rect,
            rect: CGRect(x: 20, y: 20, width: 80, height: 80), style: style)
        switch self {
        case .fill(let fill):
            style.fill = fill
        case .pattern(let pattern):
            style.width = 3
            style.pattern = pattern
            element.tool = .line
            element.points = [CGPoint(x: 10, y: 60), CGPoint(x: 110, y: 60)]
        case .width(let width):
            style.width = width * 2
            element.tool = .line
            element.points = [CGPoint(x: 15, y: 60), CGPoint(x: 105, y: 60)]
        case .shape(let shape):
            style.shape = shape
        case .route(let curved):
            style.curved = curved
            element.tool = .line
            element.points = [CGPoint(x: 10, y: 85), CGPoint(x: 60, y: 30), CGPoint(x: 110, y: 70)]
        case .head(let head, let start):
            style.width = 4
            element.tool = .arrow
            element.points = [CGPoint(x: 15, y: 60), CGPoint(x: 105, y: 60)]
            if start { style.startHead = head } else { style.endHead = head }
            // "Default" at the start means no head, matching the actual renderer.
        }
        element.style = style
        AnnotationRenderer.draw(element, in: context, scale: 1, shadowsEnabled: false)
    }
}

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
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 6), count: 4), spacing: 6) {
                    ForEach(AnnotationArrowhead.allCases, id: \.rawValue) { head in
                        Button {
                            selection = head
                            isPresented = false
                        } label: {
                            AnnotationPreviewTile(preview: .head(head, start: isStart),
                                                  isSelected: selection == head)
                        }
                        .buttonStyle(.plain)
                        .help(AnnotationLinearStrings.head(head, localization.language))
                        .accessibilityLabel(AnnotationLinearStrings.head(head, localization.language))
                        .accessibilityAddTraits(selection == head ? .isSelected : [])
                    }
                }
            }
            .padding(12)
        }
    }
}
