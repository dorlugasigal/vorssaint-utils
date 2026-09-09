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
                    let t = CGFloat(index) / 16, u = 1 - t
                    let point: CGPoint
                    if cubic {
                        point = CGPoint(x: u*u*u*start.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*end.x,
                                        y: u*u*u*start.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*end.y)
                    } else {
                        point = CGPoint(x: u*u*start.x + 2*u*t*c1.x + t*t*end.x,
                                        y: u*u*start.y + 2*u*t*c1.y + t*t*end.y)
                    }
                    line.append(point)
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

    static func sweptHit(_ element: AnnotationElement, from start: CGPoint, to end: CGPoint,
                         tolerance: CGFloat) -> Bool {
        let path = element.tool == .text
            ? CGPath(rect: element.rect, transform: nil) : AnnotationGeometry.path(element)
        var paths = [path]
        if element.tool == .arrow || element.tool == .line {
            paths.append(contentsOf: AnnotationLinear.heads(element, scale: 1).map(\.0))
        }
        let bounds = paths.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
        let sweep = ScreenshotSupport.selectionRect(from: start, to: end)
            .insetBy(dx: -tolerance, dy: -tolerance)
        guard sweep.intersects(bounds.insetBy(dx: -tolerance, dy: -tolerance)) else { return false }
        if path.contains(start) || path.contains(end) { return true }
        for geometry in paths {
            for points in polylines(geometry) where points.count > 1 {
                for index in 1..<points.count {
                    if segmentDistance(start, end, points[index - 1], points[index])
                        <= tolerance + element.resolvedStyle.width / 2 { return true }
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
