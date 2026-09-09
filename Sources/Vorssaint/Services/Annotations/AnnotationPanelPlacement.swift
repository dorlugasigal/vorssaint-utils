// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from ZoomIt for Mac, Copyright (c) 2026 Microsoft Corporation.
// MIT permission notice: docs/ANNOTATION-PROVENANCE.md

import CoreGraphics

enum AnnotationPanelPlacement {
    static func origin(anchor: CGRect, size: CGSize, visibleFrame: CGRect) -> CGPoint {
        let available = visibleFrame.insetBy(dx: 12, dy: 12)
        let right = anchor.maxX + 12
        let proposedX = right + size.width <= available.maxX ? right : anchor.minX - 12 - size.width
        return CGPoint(x: min(max(proposedX, available.minX), max(available.minX, available.maxX - size.width)),
                       y: min(max(anchor.maxY - size.height, available.minY),
                              max(available.minY, available.maxY - size.height)))
    }
}
