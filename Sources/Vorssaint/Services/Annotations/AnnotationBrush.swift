// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Microsoft Corporation.
// Nib proportions and neon palette adapted from ZoomIt for Mac.
// Permission notice in docs/ANNOTATION-PROVENANCE.md.

import CoreGraphics

enum AnnotationBrush {
    static let neonColors = [
        AnnotationColor(red: 1, green: 244 / 255, blue: 92 / 255),
        AnnotationColor(red: 50 / 255, green: 215 / 255, blue: 1),
        AnnotationColor(red: 1, green: 92 / 255, blue: 173 / 255),
        AnnotationColor(red: 102 / 255, green: 242 / 255, blue: 111 / 255),
        AnnotationColor(red: 1, green: 159 / 255, blue: 67 / 255)
    ]

    static func stamp(at point: CGPoint, width: CGFloat, highlighter: Bool) -> CGPath {
        let height = max(1, width)
        let breadth = highlighter ? max(1, width * 0.68) : height
        let rect = CGRect(x: point.x - breadth / 2, y: point.y - height / 2,
                          width: breadth, height: height)
        return highlighter ? CGPath(rect: rect, transform: nil) : CGPath(ellipseIn: rect, transform: nil)
    }

    static func ink(_ element: AnnotationElement, scale: CGFloat = 1) -> CGPath {
        let path = AnnotationGeometry.path(element, scale: scale)
        let style = element.resolvedStyle
        if element.points.count == 1 || (style.pressure != .constant && !style.isHighlighter) { return path }
        return path.copy(strokingWithWidth: style.width * scale,
                         lineCap: style.isHighlighter ? .butt : .round,
                         lineJoin: style.isHighlighter ? .bevel : .round, miterLimit: 10)
    }
}
