// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AnnotationTransformControls: View {
    @Binding var rotation: Double
    var resize: (Double) -> Void
    var editingChanged: (Bool) -> Void
    @State private var relativeScale = 1.0
    @ObservedObject private var localization = L10n.shared

    var body: some View {
        HStack {
            Image(systemName: "rotate.right")
            Slider(value: $rotation, in: -180...180, onEditingChanged: editingChanged)
                .frame(width: 100)
                .accessibilityLabel(AnnotationCommandStrings.title(.rotateRight, localization.language))
            Text(rotation, format: .number.precision(.fractionLength(0))).frame(width: 35)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
            Slider(value: Binding(get: { relativeScale }, set: {
                resize($0 / relativeScale)
                relativeScale = $0
            }), in: 0.25...4, onEditingChanged: {
                editingChanged($0)
                if !$0 { relativeScale = 1 }
            })
            .frame(width: 100)
            .accessibilityLabel(AnnotationCommandStrings.title(.grow, localization.language))
        }
    }
}
