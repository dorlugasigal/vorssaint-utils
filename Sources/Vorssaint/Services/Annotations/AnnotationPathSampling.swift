// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

enum AnnotationPathSampling {
    static func polylines(_ path: CGPath) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var line: [CGPoint] = []
        var current = CGPoint.zero
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                if !line.isEmpty { result.append(line) }
                current = element.points[0]
                line = [current]
            case .addLineToPoint:
                current = element.points[0]
                line.append(current)
            case .addQuadCurveToPoint, .addCurveToPoint:
                let start = current
                let c1 = element.points[0]
                let cubic = element.type == .addCurveToPoint
                let c2 = cubic ? element.points[1] : c1
                let end = element.points[cubic ? 2 : 1]
                for index in 1...16 {
                    let t = CGFloat(index) / 16
                    line.append(curvePoint(start: start, c1: c1, c2: c2, end: end, t: t, cubic: cubic))
                }
                current = end
            case .closeSubpath:
                if let first = line.first { line.append(first); current = first }
            @unknown default: break
            }
        }
        if !line.isEmpty { result.append(line) }
        return result
    }

    private static func curvePoint(start: CGPoint, c1: CGPoint, c2: CGPoint, end: CGPoint,
                                   t: CGFloat, cubic: Bool) -> CGPoint {
        let u: CGFloat = 1 - t
        let a: CGFloat = cubic ? u * u * u : u * u
        let b: CGFloat = cubic ? 3 * u * u * t : 2 * u * t
        let c: CGFloat = cubic ? 3 * u * t * t : 0
        let d: CGFloat = cubic ? t * t * t : t * t
        let x: CGFloat = a * start.x + b * c1.x + c * c2.x + d * end.x
        let y: CGFloat = a * start.y + b * c1.y + c * c2.y + d * end.y
        return CGPoint(x: x, y: y)
    }

    static func sweptHit(_ element: AnnotationElement, from start: CGPoint, to end: CGPoint,
                         tolerance: CGFloat) -> Bool {
        let path: CGPath
        if element.tool == .text {
            var transform = AnnotationGeometry.transform(element)
            path = CGPath(rect: element.rect, transform: &transform)
        } else if element.tool == .freehand {
            path = AnnotationBrush.ink(element)
        } else { path = AnnotationGeometry.path(element) }
        let filled = element.tool == .freehand || element.tool == .text || element.tool == .redact
            || element.tool == .highlight || AnnotationLinear.usesLegacyArrow(element)
            || ((element.tool == .rect || element.tool == .ellipse) && element.resolvedStyle.fill != .none)
        var paths: [(CGPath, Bool)] = [(path, filled)]
        if element.tool == .arrow || element.tool == .line {
            paths.append(contentsOf: AnnotationLinear.heads(element, scale: 1))
        }
        let bounds = paths.reduce(CGRect.null) { $0.union($1.0.boundingBoxOfPath) }
        let sweep = ScreenshotSupport.selectionRect(from: start, to: end)
            .insetBy(dx: -tolerance, dy: -tolerance)
        let margin = tolerance + element.resolvedStyle.width / 2
        guard sweep.intersects(bounds.insetBy(dx: -margin, dy: -margin)) else { return false }
        for (geometry, filled) in paths {
            if filled && (geometry.contains(start) || geometry.contains(end)) { return true }
            for points in polylines(geometry) where points.count > 1 {
                for index in 1..<points.count {
                    if segmentDistance(start, end, points[index - 1], points[index])
                        <= tolerance + (filled ? 0 : element.resolvedStyle.width / 2) { return true }
                }
            }
        }
        return false
    }

    private static func segmentDistance(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGFloat {
        let denominator = (b.x - a.x) * (d.y - c.y) - (b.y - a.y) * (d.x - c.x)
        if abs(denominator) > 0.000_001 {
            let t = ((c.x - a.x) * (d.y - c.y) - (c.y - a.y) * (d.x - c.x)) / denominator
            let u = ((c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)) / denominator
            if (0...1).contains(t) && (0...1).contains(u) { return 0 }
        }
        return min(ScreenshotSupport.distance(from: a, toSegment: c, d),
                   ScreenshotSupport.distance(from: b, toSegment: c, d),
                   ScreenshotSupport.distance(from: c, toSegment: a, b),
                   ScreenshotSupport.distance(from: d, toSegment: a, b))
    }
}
