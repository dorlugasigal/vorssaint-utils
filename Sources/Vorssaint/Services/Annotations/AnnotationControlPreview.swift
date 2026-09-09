// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

enum AnnotationControlPreview {
    case fill(AnnotationStyle.Fill)
    case pattern(AnnotationStyle.Pattern)
    case width(CGFloat)
    case shape(AnnotationStyle.Shape)
    case route(curved: Bool)
    case head(AnnotationArrowhead, start: Bool)

    func draw(in context: CGContext, color: AnnotationColor) {
        // Fixed logical dimensions keep production arrowhead metrics legible
        // when the inspector scales the previews to small tiles.
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
        }
        element.style = style
        AnnotationRenderer.draw(element, in: context, scale: 1, shadowsEnabled: false)
    }
}
