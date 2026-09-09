// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// A native cursor cannot become part of annotation export or undo history.
enum AnnotationBrushCursor {
    private static var cached: (style: AnnotationStyle, erasing: Bool, scale: CGFloat, cursor: NSCursor)?

    static func cursor(style: AnnotationStyle, erasing: Bool = false, scale: CGFloat = 1) -> NSCursor {
        if let cached, cached.style == style, cached.erasing == erasing, cached.scale == scale {
            return cached.cursor
        }
        let path = AnnotationInteractionFeedback.footprint(style: style, erasing: erasing, scale: scale)
        let bounds = path.boundingBoxOfPath.insetBy(dx: -3, dy: -3)
        let image = NSImage(size: bounds.size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            if !erasing {
                context.addPath(path)
                context.setFillColor(AnnotationRenderer.color(style).cgColor)
                context.fillPath()
            }
            // Contrast outside the footprint keeps its interior at the actual ink size.
            for (width, color) in [(CGFloat(2), NSColor.white), (CGFloat(0.75), NSColor.black)] {
                context.addPath(path)
                context.setLineWidth(width)
                context.setStrokeColor(color.cgColor)
                context.strokePath()
            }
            return true
        }
        let cursor = NSCursor(image: image, hotSpot: CGPoint(x: -bounds.minX, y: -bounds.minY))
        cached = (style, erasing, scale, cursor)
        return cursor
    }
}
