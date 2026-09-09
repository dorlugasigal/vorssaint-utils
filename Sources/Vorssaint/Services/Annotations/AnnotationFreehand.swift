// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

struct AnnotationInputSample {
    let point: CGPoint
    let pressure: CGFloat
}

struct AnnotationInputSampler {
    private var last: CGPoint?
    private var timestamp: TimeInterval?
    private var pressure: CGFloat = 1
    static let maximumSamplesPerEvent = 16

    mutating func sample(_ point: CGPoint, timestamp: TimeInterval, hardwarePressure: CGFloat?,
                         mode: AnnotationStyle.Pressure, final: Bool = false,
                         coordinateScale: CGFloat = 1) -> [AnnotationInputSample] {
        guard point.x.isFinite && point.y.isFinite else { return [] }
        guard let last else {
            self.last = point
            self.timestamp = timestamp
            let hardware = hardwarePressure.flatMap { $0.isFinite ? min(max($0, 0.1), 1) : nil } ?? 1
            pressure = mode == .simulated ? 0.4 : mode == .hardware ? hardware : 1
            return [AnnotationInputSample(point: point, pressure: pressure)]
        }
        let distance = hypot(point.x - last.x, point.y - last.y)
        let scale = coordinateScale.isFinite && coordinateScale > 0 ? coordinateScale : 1
        let screenDistance = distance / scale
        guard distance > 0 && (screenDistance >= 0.5 || final) else { return [] }
        let elapsed = timestamp - (self.timestamp ?? timestamp)
        let dt = elapsed.isFinite && elapsed > 0 ? min(max(elapsed, 1 / 240), 0.12) : 1 / 120
        let next: CGFloat
        switch mode {
        case .constant: next = 1
        case .hardware:
            let raw = hardwarePressure ?? 1
            next = raw.isFinite ? min(max(raw, 0.1), 1) : 1
        case .simulated:
            let target = min(max(1 - screenDistance / dt / 1600, 0.25), 1)
            next = pressure + (target - pressure) * min(1, dt * 18)
        }
        let count = mode == .constant ? 1
            : min(Self.maximumSamplesPerEvent, max(1, Int(min(screenDistance / 2.5, 16).rounded(.up))))
        let samples = (1...count).map { index -> AnnotationInputSample in
            let fraction = CGFloat(index) / CGFloat(count)
            return AnnotationInputSample(
                point: CGPoint(x: last.x + (point.x - last.x) * fraction,
                               y: last.y + (point.y - last.y) * fraction),
                pressure: pressure + (next - pressure) * fraction)
        }
        self.last = point
        self.timestamp = timestamp
        pressure = next
        return samples
    }
}

enum AnnotationFreehand {
    static func outline(_ element: AnnotationElement) -> CGPath {
        let points = element.points
        let path = CGMutablePath()
        guard !points.isEmpty else { return path }
        if points.count == 1 {
            let radius = element.resolvedStyle.width * (element.pressures.first ?? 1) / 2
            path.addEllipse(in: CGRect(x: points[0].x - radius, y: points[0].y - radius,
                                      width: radius * 2, height: radius * 2))
            return path
        }
        var left: [CGPoint] = [], right: [CGPoint] = []
        for index in points.indices {
            let before = points[max(0, index - 1)], after = points[min(points.count - 1, index + 1)]
            let distance = max(0.001, hypot(after.x - before.x, after.y - before.y))
            let pressure = element.pressures.indices.contains(index) ? element.pressures[index] : 1
            let radius = element.resolvedStyle.width * min(max(pressure, 0.1), 1) / 2
            let normal = CGPoint(x: -(after.y - before.y) / distance * radius,
                                 y: (after.x - before.x) / distance * radius)
            left.append(CGPoint(x: points[index].x + normal.x, y: points[index].y + normal.y))
            right.append(CGPoint(x: points[index].x - normal.x, y: points[index].y - normal.y))
        }
        let perimeter = left + right.reversed()
        path.move(to: perimeter[0])
        for index in 1..<perimeter.count {
            if element.resolvedStyle.smooth {
                let a = perimeter[index - 1], b = perimeter[index]
                path.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
            } else { path.addLine(to: perimeter[index]) }
        }
        path.closeSubpath()
        return path
    }
}

/// Cache only geometry, never whole elements or point arrays. Appending samples
/// therefore keeps the document's arrays uniquely owned instead of forcing
/// a copy of a long stroke on each event.
final class AnnotationPathCache {
    static let shared = AnnotationPathCache()
    enum Component: Hashable { case body, hatch, shapeBoundary }
    private struct Key: Hashable {
        let id: UUID
        let component: Component
    }
    private struct Entry {
        let revision: UUID
        let appendBase: UUID
        let style: AnnotationStyle
        let scale: CGFloat
        let count: Int
        let core: CGMutablePath?
        let path: CGPath
    }
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private let lock = NSLock()
    private var fullBuilds = 0
    private var appendUpdates = 0

    var statistics: (entries: Int, fullBuilds: Int, appendUpdates: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (entries.count, fullBuilds, appendUpdates)
    }

    func path(_ element: AnnotationElement, scale: CGFloat, component: Component = .body,
              build: () -> CGPath) -> CGPath {
        lock.lock()
        defer { lock.unlock() }
        let key = Key(id: element.id, component: component)
        let existing = entries[key]
        if let existing, existing.revision == element.geometryRevision, existing.scale == scale {
            return existing.path
        }
        let style = element.resolvedStyle
        let incremental = element.tool == .freehand && element.points.count > 1
            && (style.pressure == .constant || style.isHighlighter)
            && style.character == .architect && element.rotation == 0 && component == .body
        var core: CGMutablePath?
        let path: CGPath
        if incremental && !element.points.isEmpty {
            let reusable = existing?.appendBase == element.appendBaseRevision
                && existing?.core != nil
                && existing?.style == style && existing?.scale == scale
                && (existing?.count ?? 0) <= element.points.count
            let mutable = reusable ? existing?.core ?? CGMutablePath() : CGMutablePath()
            if reusable { appendUpdates += 1 } else { fullBuilds += 1 }
            let start = reusable ? existing?.count ?? 0 : 0
            if start == 0 { mutable.move(to: element.points[0]) }
            for index in max(1, start)..<element.points.count {
                let previous = element.points[index - 1], current = element.points[index]
                if style.smooth {
                    mutable.addQuadCurve(to: CGPoint(x: (previous.x + current.x) / 2,
                                                     y: (previous.y + current.y) / 2), control: previous)
                } else { mutable.addLine(to: current) }
            }
            let full = CGMutablePath()
            full.addPath(mutable)
            full.addLine(to: element.points[element.points.count - 1])
            core = mutable
            path = full
        } else {
            fullBuilds += 1
            path = build()
        }
        if existing == nil {
            if order.count >= 256 { entries.removeValue(forKey: order.removeFirst()) }
            order.append(key)
        }
        entries[key] = Entry(revision: element.geometryRevision, appendBase: element.appendBaseRevision,
                                    style: style, scale: scale, count: element.points.count, core: core, path: path)
        return path
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        order.removeAll()
        fullBuilds = 0
        appendUpdates = 0
        AnnotationLinear.clearHeadCache()
    }
}
