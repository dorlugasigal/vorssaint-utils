// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum ScreenshotEditorHost {
    static func makeController(model: ScreenshotEditorModel, controller: ScreenshotEditorController,
                               minimumSize: CGSize) -> NSViewController {
        let content = ScreenshotEditorView(model: model, controller: controller)
            .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.minSize]
        return host
    }
}
