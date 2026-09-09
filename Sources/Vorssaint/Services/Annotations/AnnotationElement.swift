// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Shared session-local geometry. Coordinates have a top-left origin; each
/// host supplies its logical-to-pixel scale rather than normalizing elements.
struct AnnotationElement: Identifiable, Equatable {
    let id: UUID
    var tool: ScreenshotSupport.Tool
    var rect: CGRect
    var points: [CGPoint]
    var text: String
    var color: ScreenshotSupport.ColorID
    var stroke: ScreenshotSupport.StrokeID
    var number: Int
    var style: AnnotationStyle?

    init(id: UUID = UUID(), tool: ScreenshotSupport.Tool, rect: CGRect = .zero,
         points: [CGPoint] = [], text: String = "", color: ScreenshotSupport.ColorID = .red,
         stroke: ScreenshotSupport.StrokeID = .medium, number: Int = 0,
         style: AnnotationStyle? = nil) {
        self.id = id
        self.tool = tool
        self.rect = rect
        self.points = points
        self.text = text
        self.color = color
        self.stroke = stroke
        self.number = number
        self.style = style
    }

    var resolvedStyle: AnnotationStyle {
        if let style { return style }
        let rgb = color.components
        return AnnotationStyle(color: AnnotationColor(red: rgb.red, green: rgb.green, blue: rgb.blue),
                               width: stroke.width)
    }
}

struct AnnotationStyle: Equatable {
    var color: AnnotationColor
    var width: CGFloat
    var opacity: CGFloat = 1
    var smooth = true
    var textSize: CGFloat?
    var mediumTextWeight = false
}

enum AnnotationGeometry {
    static func bounds(_ element: AnnotationElement) -> CGRect {
        guard let first = element.points.first else { return element.rect }
        return element.points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }

    static func path(_ element: AnnotationElement) -> CGPath {
        let path = CGMutablePath()
        switch element.tool {
        case .rect, .redact, .highlight, .pixelate:
            path.addRect(element.rect)
        case .ellipse:
            path.addEllipse(in: element.rect)
        case .arrow:
            if element.points.count >= 2 {
                path.addPath(ScreenshotSupport.arrowSilhouette(
                    from: element.points[0], to: element.points[1],
                    strokeWidth: element.resolvedStyle.width))
            }
        case .freehand, .line:
            guard let first = element.points.first else { return path }
            path.move(to: first)
            for index in 1..<element.points.count {
                let current = element.points[index]
                let previous = element.points[index - 1]
                if element.tool == .freehand && element.resolvedStyle.smooth {
                    path.addQuadCurve(to: CGPoint(x: (current.x + previous.x) / 2,
                                                  y: (current.y + previous.y) / 2),
                                      control: previous)
                } else {
                    path.addLine(to: current)
                }
            }
            if let last = element.points.last { path.addLine(to: last) }
        case .text, .sticker, .counter, .select, .crop: break
        }
        return path
    }

    static func hit(_ element: AnnotationElement, at point: CGPoint, scale: CGFloat,
                    imageSize: CGSize, includeShapeInteriors: Bool = true) -> Bool {
        let tolerance = 10 * scale
        switch element.tool {
        case .arrow, .line, .freehand:
            var scaled = element
            var style = element.resolvedStyle
            style.width *= scale
            scaled.style = style
            let geometry = path(scaled)
            if element.tool == .arrow && geometry.contains(point) { return true }
            return geometry.copy(strokingWithWidth: 2 * tolerance + style.width,
                                 lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
        case .counter:
            let radius = ScreenshotSupport.counterDiameter(for: imageSize, scale: 1) / 2
            return hypot(point.x - element.rect.midX, point.y - element.rect.midY) <= radius + 4 * scale
        case .rect, .ellipse, .highlight, .pixelate, .redact:
            let geometry = path(element)
            if includeShapeInteriors && geometry.contains(point) { return true }
            return geometry.copy(strokingWithWidth: tolerance, lineCap: .round,
                                 lineJoin: .round, miterLimit: 10).contains(point)
        case .text, .sticker:
            return element.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(point)
        case .select, .crop: return false
        }
    }
}
