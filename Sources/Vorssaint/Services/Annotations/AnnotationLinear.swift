// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Arrowhead catalog and metrics derived from ZoomIt for Mac.
// Copyright (c) 2026 Microsoft Corporation. MIT: docs/ANNOTATION-PROVENANCE.md

import CoreGraphics
import Foundation

enum AnnotationArrowhead: Int, Codable, CaseIterable {
    case legacy, none, arrow, triangle, triangleOutline, circle, circleOutline
    case bar, diamond, diamondOutline, crowFoot, oneOrMany, zeroOrOne, zeroOrMany

    var isFilled: Bool { self == .triangle || self == .circle || self == .diamond }
}

enum AnnotationLinear {
    static func constrainedStyle(_ value: AnnotationStyle, for tool: ScreenshotSupport.Tool) -> AnnotationStyle {
        guard tool == .line else { return value }
        var style = value
        style.curved = false
        style.startHead = .none
        style.endHead = .none
        return style
    }

    static func creationStyle(for tool: ScreenshotSupport.Tool, base: AnnotationStyle) -> AnnotationStyle {
        var style = base
        style.curved = tool == .arrow
        if tool == .arrow { style.endHead = .arrow }
        return constrainedStyle(style, for: tool)
    }

    static func midpoints(_ element: AnnotationElement) -> [CGPoint] {
        guard element.tool == .arrow, element.points.count >= 2 else { return [] }
        let controls = controls(element)
        return (0..<(element.points.count - 1)).map { segment in
            let start = element.points[segment], end = element.points[segment + 1]
            if !element.resolvedStyle.curved { return midpoint(start, end) }
            let left = midpoint(start, controls[segment * 2])
            let middle = midpoint(controls[segment * 2], controls[segment * 2 + 1])
            let right = midpoint(controls[segment * 2 + 1], end)
            return midpoint(midpoint(left, middle), midpoint(middle, right))
        }
    }

    /// De Casteljau subdivision inserts a draggable knot without changing the
    /// existing cubic or replacing the user's other custom control handles.
    static func insertingPoint(in element: AnnotationElement, segment: Int) -> AnnotationElement {
        guard !element.isLocked, element.tool == .arrow,
              segment >= 0, segment + 1 < element.points.count else { return element }
        var result = element
        let start = element.points[segment], end = element.points[segment + 1]
        let point: CGPoint
        if element.resolvedStyle.curved {
            var controls = controls(element)
            let left = midpoint(start, controls[segment * 2])
            let middle = midpoint(controls[segment * 2], controls[segment * 2 + 1])
            let right = midpoint(controls[segment * 2 + 1], end)
            let innerLeft = midpoint(left, middle), innerRight = midpoint(middle, right)
            point = midpoint(innerLeft, innerRight)
            controls.replaceSubrange((segment * 2)...(segment * 2 + 1), with: [left, innerLeft, innerRight, right])
            result.controls = controls
        } else {
            point = midpoint(start, end)
            result.controls = []
        }
        result.points.insert(point, at: segment + 1)
        return worldAligned(result, relativeTo: element)
    }

    static func removingPoint(in element: AnnotationElement, index: Int) -> AnnotationElement {
        guard !element.isLocked, (element.tool == .arrow || element.tool == .line),
              index > 0, index + 1 < element.points.count else { return element }
        var result = element
        if element.resolvedStyle.curved {
            var controls = controls(element)
            let start = (index - 1) * 2
            let outer = [controls[start], controls[start + 3]]
            controls.replaceSubrange(start..<(start + 4), with: outer)
            result.controls = controls
        } else { result.controls = [] }
        result.points.remove(at: index)
        return worldAligned(result, relativeTo: element)
    }

    private static func worldAligned(_ element: AnnotationElement, relativeTo original: AnnotationElement) -> AnnotationElement {
        guard original.rotation != 0 else { return element }
        // Inserting/removing knots can change the bounds-derived rotation pivot.
        // Bake the old transform into linear geometry to avoid moving the curve.
        let transform = AnnotationGeometry.transform(original)
        var result = element
        result.points = result.points.map { $0.applying(transform) }
        result.controls = result.controls.map { $0.applying(transform) }
        result.rotation = 0
        return result
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static let cacheLock = NSLock()
    private static var headCache: [UUID: (revision: UUID, scale: CGFloat, paths: [(CGPath, Bool)])] = [:]

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

    static func path(_ element: AnnotationElement, renderScale: CGFloat = 1) -> CGPath {
        let path = CGMutablePath()
        guard element.points.count >= 2 else { return path }
        let shaft = shaftGeometry(element, renderScale: renderScale)
        path.move(to: shaft.points[0])
        let controls = controls(shaft)
        for index in 1..<shaft.points.count {
            if shaft.resolvedStyle.curved {
                path.addCurve(to: shaft.points[index], control1: controls[(index - 1) * 2],
                              control2: controls[(index - 1) * 2 + 1])
            } else { path.addLine(to: shaft.points[index]) }
        }
        return path
    }

    static func endpointAdjacent(_ element: AnnotationElement, atStart: Bool) -> CGPoint {
        let tip = atStart ? element.points[0] : element.points[element.points.count - 1]
        if element.resolvedStyle.curved {
            let controls = controls(element)
            let control = atStart ? controls[0] : controls[controls.count - 1]
            if hypot(control.x - tip.x, control.y - tip.y) > 0.000_001 { return control }
        }
        let candidates = atStart ? element.points : Array(element.points.reversed())
        return candidates.dropFirst().first { hypot($0.x - tip.x, $0.y - tip.y) > 0.000_001 } ?? tip
    }

    /// Match ZoomIt's endpoint tangent insets, moving each attached control by
    /// the same delta so shortening the shaft does not change its end tangent.
    static func shaftGeometry(_ element: AnnotationElement, renderScale: CGFloat = 1) -> AnnotationElement {
        guard element.points.count >= 2 else { return element }
        var result = element
        let style = element.resolvedStyle
        let scale = renderScale.isFinite && renderScale > 0 ? renderScale : 1
        let endHead = style.endHead == .legacy ? (element.tool == .arrow ? AnnotationArrowhead.triangle : .none) : style.endHead
        var directions: [CGPoint] = []
        var insets: [CGFloat] = []
        for (index, adjacent, head) in [(0, 1, style.startHead),
                                        (element.points.count - 1, element.points.count - 2, endHead)] {
            let tip = element.points[index], other = element.points[adjacent]
            let tangent = endpointAdjacent(element, atStart: index == 0)
            let length = hypot(tangent.x - tip.x, tangent.y - tip.y)
            let direction = length > 0 ? CGPoint(x: (tangent.x - tip.x) / length,
                                                 y: (tangent.y - tip.y) / length) : .zero
            let limit = max(0, (other.x - tip.x) * direction.x + (other.y - tip.y) * direction.y)
            directions.append(direction)
            insets.append(min(shaftInset(head, width: style.width / scale, size: style.headSize * scale), limit))
        }
        if element.points.count == 2 {
            let length = hypot(element.points[1].x - element.points[0].x,
                               element.points[1].y - element.points[0].y)
            let maximum = max(0, length - max(scale, style.width * 0.5))
            let total = insets[0] + insets[1]
            if total > maximum {
                insets = insets.map { $0 * maximum / total }
            }
        }
        if style.curved { result.controls = controls(element) }
        for end in 0...1 {
            let index = end == 0 ? 0 : element.points.count - 1
            let delta = CGPoint(x: directions[end].x * insets[end], y: directions[end].y * insets[end])
            result.points[index].x += delta.x
            result.points[index].y += delta.y
            if style.curved {
                let control = end == 0 ? 0 : result.controls.count - 1
                result.controls[control].x += delta.x
                result.controls[control].y += delta.y
            }
        }
        return result
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
        guard element.points.count >= 2, !usesLegacyArrow(element) else { return [] }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = headCache[element.id], cached.revision == element.geometryRevision, cached.scale == scale {
            return cached.paths
        }
        let paths = uncachedHeads(element, scale: scale)
        if headCache.count >= 256 && headCache[element.id] == nil { headCache.removeAll() }
        headCache[element.id] = (element.geometryRevision, scale, paths)
        return paths
    }

    static func clearHeadCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        headCache.removeAll()
    }

    private static func uncachedHeads(_ element: AnnotationElement, scale: CGFloat) -> [(CGPath, Bool)] {
        let style = element.resolvedStyle
        let endpoints = [
            (style.startHead, element.points[0], endpointAdjacent(element, atStart: true)),
            (style.endHead == .legacy ? (element.tool == .arrow ? .triangle : .none) : style.endHead,
             element.points.last!, endpointAdjacent(element, atStart: false))
        ]
        return endpoints.compactMap { head, tip, adjacent in
            guard head != .none && head != .legacy,
                  hypot(tip.x - adjacent.x, tip.y - adjacent.y) > 0.000_001 else { return nil }
            let canonical = headPath(head, tip: tip, adjacent: adjacent, width: style.width, size: style.headSize * scale)
            let rough = AnnotationRoughness.path(canonical, character: style.character,
                    seed: element.roughSeed ^ UInt64(head.rawValue), width: style.width * scale, scale: scale)
            var transform = AnnotationGeometry.transform(element)
            return (rough.copy(using: &transform) ?? rough, head.isFilled)
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
    private(set) var preview: CGPoint
    private(set) var isClickConstruction = false
    private(set) var pointerIsDown = true
    private var downPoint: CGPoint
    private var exceededDragThreshold = false
    private var viewScale: CGFloat
    private var rawPreview: CGPoint
    private var lastClickPoint: CGPoint?

    var finishHandle: CGPoint? { isClickConstruction && vertices.count >= 2 ? vertices.last : nil }

    init(element: AnnotationElement, at point: CGPoint, viewScale: CGFloat = 1) {
        self.element = element
        self.element.style = AnnotationLinear.constrainedStyle(element.resolvedStyle, for: element.tool)
        vertices = [point]
        preview = point
        rawPreview = point
        downPoint = point
        self.viewScale = max(viewScale, 0.001)
    }

    func hitsFinishHandle(_ point: CGPoint, viewScale: CGFloat) -> Bool {
        guard let finishHandle else { return false }
        return hypot(point.x - finishHandle.x, point.y - finishHandle.y) * viewScale <= 10
    }

    mutating func beginPointer(at point: CGPoint, constrained: Bool, viewScale: CGFloat) {
        downPoint = point
        exceededDragThreshold = false
        pointerIsDown = true
        updatePreview(at: point, constrained: constrained, viewScale: viewScale)
    }

    mutating func updatePreview(at point: CGPoint, constrained: Bool, viewScale: CGFloat) {
        rawPreview = point
        self.viewScale = max(viewScale, 0.001)
        if pointerIsDown && hypot(point.x - downPoint.x, point.y - downPoint.y) * self.viewScale > 4 {
            exceededDragThreshold = true
        }
        preview = constrained ? AnnotationLinear.constrained(point, from: vertices[vertices.count - 1]) : point
    }

    mutating func updateConstraint(_ constrained: Bool, viewScale: CGFloat) {
        updatePreview(at: rawPreview, constrained: constrained, viewScale: viewScale)
    }

    /// Only release commits vertices. Hover and mouse-down remain speculative.
    mutating func release(at point: CGPoint, constrained: Bool, viewScale: CGFloat, clickCount: Int = 1) -> Bool {
        guard pointerIsDown else { return false }
        let finishHandleHit = hitsFinishHandle(point, viewScale: viewScale)
        updatePreview(at: point, constrained: constrained, viewScale: viewScale)
        pointerIsDown = false
        if element.tool == .line {
            if exceededDragThreshold || isClickConstruction {
                add(preview)
                return true
            }
            isClickConstruction = true
            return false
        }
        if !isClickConstruction {
            if exceededDragThreshold {
                add(preview)
                return true
            }
            isClickConstruction = true
            return false
        }
        // Snapping can put the vertex far from the first physical click.
        // A second click there finishes; it must not add a segment back to it.
        let repeatsClick = clickCount >= 2 && lastClickPoint.map {
            hypot(point.x - $0.x, point.y - $0.y) * viewScale <= 10
        } == true
        if finishHandleHit || repeatsClick {
            preview = vertices[vertices.count - 1]
            return true
        }
        add(preview)
        lastClickPoint = point
        return clickCount >= 2
    }

    mutating func finish(commitPreview: Bool) -> AnnotationElement? {
        if commitPreview { add(preview) }
        pointerIsDown = false
        return completed
    }

    mutating func add(_ point: CGPoint) {
        if let last = vertices.last, hypot(last.x - point.x, last.y - point.y) * viewScale > 0.5 {
            if element.tool == .line, vertices.count == 2 { vertices[1] = point }
            else { vertices.append(point) }
        }
        preview = point
    }

    var displayed: AnnotationElement {
        var result = element
        let last = vertices[vertices.count - 1]
        let includesPreview = hypot(last.x - preview.x, last.y - preview.y) * viewScale > 0.5
        result.points = vertices + (includesPreview ? [preview] : [])
        result.controls = []
        return result
    }

    var completed: AnnotationElement? {
        guard vertices.count >= 2 else { return nil }
        var result = element
        result.points = vertices
        result.controls = []
        return result
    }
}
