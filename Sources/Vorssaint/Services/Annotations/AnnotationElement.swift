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
    var rotation: CGFloat = 0
    var groupID: UUID?
    var isLocked = false
    var controls: [CGPoint] = []
    var startBinding: AnnotationBinding?
    var endBinding: AnnotationBinding?

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
    enum Fill: Int, CaseIterable { case none, solid, hatch, crossHatch }
    enum Pattern: Int, CaseIterable { case solid, dashed, dotted }
    enum Shape: Int, CaseIterable { case standard, diamond }
    var color: AnnotationColor
    var width: CGFloat
    var opacity: CGFloat = 1
    var smooth = true
    var textSize: CGFloat?
    var mediumTextWeight = false
    var fill: Fill = .none
    var fillColor: AnnotationColor = .white
    var pattern: Pattern = .solid
    var shape: Shape = .standard
    var roundness: CGFloat = 0
    var curved = false
    var multiClick = false
    var startHead: AnnotationArrowhead = .none
    var endHead: AnnotationArrowhead = .legacy
    var headSize: CGFloat = 1
    var bindEndpoints = false

    func sanitized() -> AnnotationStyle {
        var result = self
        result.color = color.clamped()
        result.fillColor = fillColor.clamped()
        result.roundness = roundness.isFinite ? min(max(roundness, 0), 1) : 0
        result.headSize = headSize.isFinite ? min(max(headSize, 1), 1.75) : 1
        result.width = width.isFinite ? min(max(width, 1), 40) : 6
        result.opacity = opacity.isFinite ? min(max(opacity, 0), 1) : 1
        if let textSize { result.textSize = textSize.isFinite ? min(max(textSize, 6), 240) : 19 }
        return result
    }
}

enum AnnotationGeometry {
    static func transform(_ element: AnnotationElement) -> CGAffineTransform {
        let rect = bounds(element)
        return CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: element.rotation)
            .translatedBy(x: -rect.midX, y: -rect.midY)
    }

    static func visualBounds(_ element: AnnotationElement) -> CGRect {
        bounds(element).applying(transform(element))
    }

    static func bounds(_ element: AnnotationElement) -> CGRect {
        guard let first = element.points.first else { return element.rect }
        return element.points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }

    static func path(_ element: AnnotationElement) -> CGPath {
        let path = CGMutablePath()
        switch element.tool {
        case .rect:
            if element.resolvedStyle.shape == .diamond {
                let rect = element.rect
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                path.closeSubpath()
            } else {
                let radius = element.resolvedStyle.roundness * min(element.rect.width, element.rect.height) / 2
                path.addRoundedRect(in: element.rect, cornerWidth: radius, cornerHeight: radius)
            }
        case .redact, .highlight, .pixelate:
            path.addRect(element.rect)
        case .ellipse:
            path.addEllipse(in: element.rect)
        case .arrow, .line:
            if AnnotationLinear.usesLegacyArrow(element) {
                path.addPath(ScreenshotSupport.arrowSilhouette(
                    from: element.points[0], to: element.points[1],
                    strokeWidth: element.resolvedStyle.width))
            } else { path.addPath(AnnotationLinear.path(element)) }
        case .freehand:
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
        var transform = transform(element)
        return path.copy(using: &transform) ?? path
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
            if AnnotationLinear.usesLegacyArrow(element) && geometry.contains(point) { return true }
            if element.tool == .arrow || element.tool == .line {
                for (head, filled) in AnnotationLinear.heads(element, scale: scale) {
                    if filled && head.contains(point) { return true }
                    if head.copy(strokingWithWidth: 2 * tolerance, lineCap: .round,
                                 lineJoin: .round, miterLimit: 10).contains(point) { return true }
                }
            }
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
            return element.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2)
                .contains(point.applying(transform(element).inverted()))
        case .select, .crop: return false
        }
    }
}
