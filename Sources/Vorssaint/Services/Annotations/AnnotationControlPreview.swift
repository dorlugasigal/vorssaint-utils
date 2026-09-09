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
    case headSize(CGFloat)
    case character(AnnotationStyle.Character)
    case pressure(AnnotationStyle.Pressure)

    func draw(in context: CGContext, color: AnnotationColor) {
        // Fixed logical dimensions keep production arrowhead metrics legible
        // when the inspector scales the previews to small tiles.
        var style = AnnotationStyle(color: color, width: 5)
        style.fillColor = color
        style.endHead = .none
        var element = AnnotationElement(tool: .rect,
            rect: CGRect(x: 20, y: 20, width: 80, height: 80), style: style)
        element.roughSeed = 42
        switch self {
        case .pressure(let pressure):
            style.pressure = pressure
            style.width = 22
            element.tool = .freehand
            element.points = [CGPoint(x: 14, y: 72), CGPoint(x: 37, y: 52), CGPoint(x: 60, y: 64),
                              CGPoint(x: 83, y: 52), CGPoint(x: 106, y: 60)]
            element.pressures = pressure == .simulated ? [0.9, 0.55, 0.15, 0.55, 0.9] : [0.15, 0.55, 1, 0.55, 0.15]
        case .fill(let fill):
            style.fill = fill
        case .character(let character):
            style.character = character
        case .pattern(let pattern):
            style.width = 6
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
            style.endHead = .arrow
            style.headSize = 1.5
            element.tool = .arrow
            element.points = curved
                ? [CGPoint(x: 20, y: 100), CGPoint(x: 40, y: 48), CGPoint(x: 100, y: 28)]
                : [CGPoint(x: 20, y: 100), CGPoint(x: 100, y: 20)]
        case .head(let head, let start):
            style.width = 4
            element.tool = .arrow
            element.points = [CGPoint(x: 15, y: 60), CGPoint(x: 105, y: 60)]
            if start { style.startHead = head } else { style.endHead = head }
        case .headSize(let size):
            element.tool = .arrow
            element.points = [CGPoint(x: 15, y: 60), CGPoint(x: 105, y: 60)]
            style.endHead = .arrow
            style.headSize = size
        }
        element.style = style
        AnnotationRenderer.draw(element, in: context, scale: 1, shadowsEnabled: false)
    }
}
