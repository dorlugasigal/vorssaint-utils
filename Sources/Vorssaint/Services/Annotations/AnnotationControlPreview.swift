// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Edge preview paths adapted from ZoomIt for Mac.
// Copyright (c) 2026 Microsoft Corporation. MIT: docs/ANNOTATION-PROVENANCE.md

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
    case edges(rounded: Bool)

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
        case .edges(let rounded):
            context.saveGState()
            context.scaleBy(x: 120 / 26, y: 120 / 26)
            context.setStrokeColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha))
            context.setLineWidth(1.8)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            let bounds = CGRect(x: 5, y: 5, width: 16, height: 16)
            context.move(to: CGPoint(x: bounds.maxX, y: bounds.minY))
            if rounded {
                context.addQuadCurve(to: CGPoint(x: bounds.minX, y: bounds.maxY),
                                     control: CGPoint(x: bounds.minX, y: bounds.minY))
            } else {
                context.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY))
                context.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY))
            }
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [0.5, 3])
            context.move(to: CGPoint(x: bounds.maxX, y: bounds.minY))
            context.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
            context.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY))
            context.strokePath()
            context.restoreGState()
            return
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
