// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Arrowhead catalog and metrics derived from ZoomIt for Mac.
// Copyright (c) 2026 Microsoft Corporation. MIT: docs/ANNOTATION-PROVENANCE.md

import CoreGraphics

enum AnnotationArrowhead: Int, CaseIterable {
    case legacy, none, arrow, triangle, triangleOutline, circle, circleOutline
    case bar, diamond, diamondOutline, crowFoot, oneOrMany, zeroOrOne, zeroOrMany

    var isFilled: Bool { self == .triangle || self == .circle || self == .diamond }
}

enum AnnotationLinear {
    static func editPoints(_ insert: Bool, in element: inout AnnotationElement) {
        guard !element.isLocked, element.tool == .arrow || element.tool == .line,
              element.points.count >= 2 else { return }
        if insert {
            let index = element.points.count - 1
            let a = element.points[index - 1], b = element.points[index]
            element.points.insert(CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), at: index)
        } else if element.points.count > 2 { element.points.remove(at: element.points.count - 2) }
        element.controls = []
    }

    static func usesLegacyArrow(_ element: AnnotationElement) -> Bool {
        element.tool == .arrow && element.points.count == 2 && !element.resolvedStyle.curved
            && element.resolvedStyle.startHead == .none && element.resolvedStyle.endHead == .legacy
            && element.resolvedStyle.headSize == 1 && element.resolvedStyle.pattern == .solid
    }

    static func controls(_ element: AnnotationElement) -> [CGPoint] {
        let points = element.points
        guard points.count >= 2 else { return [] }
        if element.controls.count == (points.count - 1) * 2 { return element.controls }
        var controls: [CGPoint] = []
        for index in 0..<(points.count - 1) {
            let previous = points[max(0, index - 1)]
            let start = points[index]
            let end = points[index + 1]
            let next = points[min(points.count - 1, index + 2)]
            controls.append(CGPoint(x: start.x + (end.x - previous.x) / 6,
                                    y: start.y + (end.y - previous.y) / 6))
            controls.append(CGPoint(x: end.x - (next.x - start.x) / 6,
                                    y: end.y - (next.y - start.y) / 6))
        }
        return controls
    }

    static func path(_ element: AnnotationElement) -> CGPath {
        let path = CGMutablePath()
        guard element.points.count >= 2 else { return path }
        var points = element.points
        let style = element.resolvedStyle
        let endHead = style.endHead == .legacy ? (element.tool == .arrow ? AnnotationArrowhead.triangle : .none) : style.endHead
        for (index, adjacent, head) in [(0, 1, style.startHead), (points.count - 1, points.count - 2, endHead)] {
            let tip = element.points[index], other = element.points[adjacent]
            let distance = hypot(other.x - tip.x, other.y - tip.y)
            let inset = min(shaftInset(head, width: style.width, size: style.headSize), distance * 0.45)
            if distance > 0 {
                points[index] = CGPoint(x: tip.x + (other.x - tip.x) * inset / distance,
                                        y: tip.y + (other.y - tip.y) * inset / distance)
            }
        }
        path.move(to: points[0])
        let controls = controls(element)
        for index in 1..<points.count {
            if element.resolvedStyle.curved {
                path.addCurve(to: points[index], control1: controls[(index - 1) * 2],
                              control2: controls[(index - 1) * 2 + 1])
            } else { path.addLine(to: points[index]) }
        }
        return path
    }

    private static func shaftInset(_ head: AnnotationArrowhead, width: CGFloat, size: CGFloat) -> CGFloat {
        let length = max(23, width * 3) * size
        let halfWidth = max(13.5, width * 2) * size
        let spacing = max(2, width) * size
        switch head {
        case .legacy, .none, .arrow, .bar, .crowFoot: return 0
        case .triangle, .triangleOutline, .diamond, .diamondOutline: return length
        case .circle, .circleOutline: return halfWidth * 2
        case .oneOrMany: return length * 0.92
        case .zeroOrOne: return halfWidth * 1.44 + spacing
        case .zeroOrMany: return halfWidth * 1.44 + spacing + length * 0.68
        }
    }

    static func heads(_ element: AnnotationElement, scale: CGFloat) -> [(CGPath, Bool)] {
        guard element.points.count >= 2 else { return [] }
        let style = element.resolvedStyle
        let controls = controls(element)
        let endpoints = [
            (style.startHead, element.points[0], style.curved ? controls[0] : element.points[1]),
            (style.endHead == .legacy ? (element.tool == .arrow ? .triangle : .none) : style.endHead,
             element.points.last!, style.curved ? controls.last! : element.points[element.points.count - 2])
        ]
        return endpoints.compactMap { head, tip, adjacent in
            guard head != .none && head != .legacy else { return nil }
            return (headPath(head, tip: tip, adjacent: adjacent, width: style.width * scale,
                             size: style.headSize), head.isFilled)
        }
    }

    static func headPath(_ head: AnnotationArrowhead, tip: CGPoint, adjacent: CGPoint,
                         width: CGFloat, size: CGFloat) -> CGPath {
        let length = max(23, width * 3) * size
        let halfWidth = max(13.5, width * 2) * size
        let spacing = max(2, width) * size
        let path = CGMutablePath()
        func line(_ a: CGPoint, _ b: CGPoint) { path.move(to: a); path.addLine(to: b) }
        func bar(_ x: CGFloat) { line(CGPoint(x: x, y: -halfWidth), CGPoint(x: x, y: halfWidth)) }
        func circle(_ rear: CGFloat, radius: CGFloat) {
            path.addEllipse(in: CGRect(x: -rear - radius * 2, y: -radius, width: radius * 2, height: radius * 2))
        }
        func crow(_ x: CGFloat, length: CGFloat) {
            for y in [-halfWidth, 0, halfWidth] { line(CGPoint(x: x, y: 0), CGPoint(x: x - length, y: y)) }
        }
        switch head {
        case .legacy, .none: break
        case .arrow:
            line(.zero, CGPoint(x: -length, y: halfWidth))
            line(.zero, CGPoint(x: -length, y: -halfWidth))
        case .triangle, .triangleOutline:
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: -length, y: halfWidth))
            path.addLine(to: CGPoint(x: -length, y: -halfWidth))
            path.closeSubpath()
        case .circle, .circleOutline: circle(0, radius: halfWidth)
        case .bar: bar(0)
        case .diamond, .diamondOutline:
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: -length / 2, y: halfWidth))
            path.addLine(to: CGPoint(x: -length, y: 0))
            path.addLine(to: CGPoint(x: -length / 2, y: -halfWidth))
            path.closeSubpath()
        case .crowFoot: crow(0, length: length * 0.72)
        case .oneOrMany:
            crow(0, length: length * 0.72)
            bar(-length * 0.92)
        case .zeroOrOne:
            circle(0, radius: halfWidth * 0.72)
            bar(-halfWidth * 1.44 - spacing)
        case .zeroOrMany:
            circle(0, radius: halfWidth * 0.72)
            crow(-halfWidth * 1.44 - spacing, length: length * 0.68)
        }
        var transform = CGAffineTransform(translationX: tip.x, y: tip.y)
            .rotated(by: atan2(tip.y - adjacent.y, tip.x - adjacent.x))
        return path.copy(using: &transform) ?? path
    }

    static func constrained(_ point: CGPoint, from anchor: CGPoint) -> CGPoint {
        let distance = hypot(point.x - anchor.x, point.y - anchor.y)
        let angle = (atan2(point.y - anchor.y, point.x - anchor.x) / (.pi / 4)).rounded() * (.pi / 4)
        return CGPoint(x: anchor.x + cos(angle) * distance, y: anchor.y + sin(angle) * distance)
    }
}

struct AnnotationLinearConstruction {
    var element: AnnotationElement
    private(set) var vertices: [CGPoint]
    var preview: CGPoint

    init(element: AnnotationElement, at point: CGPoint) {
        self.element = element
        vertices = [point]
        preview = point
    }

    mutating func add(_ point: CGPoint) {
        if let last = vertices.last, hypot(last.x - point.x, last.y - point.y) >= 1 {
            vertices.append(point)
        }
        preview = point
    }

    var displayed: AnnotationElement {
        var result = element
        result.points = vertices + (vertices.last == preview ? [] : [preview])
        return result
    }

    var completed: AnnotationElement? {
        guard vertices.count >= 2 else { return nil }
        var result = element
        result.points = vertices
        return result
    }
}
