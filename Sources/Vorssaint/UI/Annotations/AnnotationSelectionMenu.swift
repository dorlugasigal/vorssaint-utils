// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AnnotationSelectionMenu: View {
    var hasSelection: Bool
    var perform: (AnnotationSelectionAction) -> Void
    @ObservedObject private var localization = L10n.shared

    var body: some View {
        Menu {
            AnnotationSelectionCommands(hasSelection: hasSelection, perform: perform)
        } label: {
            Image(systemName: "square.on.square")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(width: 28)
        .help(FeatureStrings.screenshot(localization.language).toolSelect)
    }
}

struct AnnotationSelectionCommands: View {
    var hasSelection: Bool
    var perform: (AnnotationSelectionAction) -> Void
    @ObservedObject private var localization = L10n.shared

    var body: some View {
        ForEach(AnnotationSelectionAction.allCases, id: \.rawValue) { action in
            if action == .delete || action == .group || action == .forward || action == .rotateLeft {
                Divider()
            }
            Button(AnnotationCommandStrings.title(action, localization.language)) { perform(action) }
                .disabled(action != .selectAll && !hasSelection)
        }
    }
}
