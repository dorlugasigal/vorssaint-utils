// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

struct AnnotationBinding: Equatable {
    let targetID: UUID
    let anchor: CGPoint

    func remapped(_ replacements: [UUID: UUID]) -> AnnotationBinding? {
        replacements[targetID].map { AnnotationBinding(targetID: $0, anchor: anchor) }
    }
}

enum AnnotationBindings {
    static func finishEdit(_ ids: Set<UUID>, elements: inout [AnnotationElement], tolerance: CGFloat) {
        let targets = elements.filter { $0.tool == .rect || $0.tool == .ellipse }
        for index in elements.indices where ids.contains(elements[index].id) {
            attach(&elements[index], in: targets, tolerance: tolerance)
        }
        resolve(&elements)
    }

    static func nearest(to point: CGPoint, in elements: [AnnotationElement], tolerance: CGFloat) -> AnnotationBinding? {
        var nearest: (AnnotationBinding, CGFloat)?
        for target in elements.reversed() where target.tool == .rect || target.tool == .ellipse {
            let rect = target.rect
            guard rect.width > 0 && rect.height > 0 else { continue }
            let local = point.applying(AnnotationGeometry.transform(target).inverted())
            let anchor = boundary(local, target: target)
            let world = anchor.applying(AnnotationGeometry.transform(target))
            let distance = hypot(world.x - point.x, world.y - point.y)
            guard distance <= tolerance && distance < (nearest?.1 ?? .infinity) else { continue }
            nearest = (AnnotationBinding(targetID: target.id,
                anchor: CGPoint(x: (anchor.x - rect.minX) / rect.width,
                                y: (anchor.y - rect.minY) / rect.height)), distance)
        }
        return nearest?.0
    }

    static func attach(_ element: inout AnnotationElement, in elements: [AnnotationElement], tolerance: CGFloat) {
        guard !element.isLocked, element.resolvedStyle.bindEndpoints,
              (element.tool == .arrow || element.tool == .line), element.points.count >= 2 else { return }
        if element.startBinding == nil {
            element.startBinding = nearest(to: element.points[0], in: elements, tolerance: tolerance)
        }
        if element.endBinding == nil {
            element.endBinding = nearest(to: element.points[element.points.count - 1], in: elements, tolerance: tolerance)
        }
    }

    /// Only shapes are targets, so a single pass resolves every dependency.
    /// Deleted targets detach without moving the last visible endpoint.
    static func resolve(_ elements: inout [AnnotationElement]) {
        let targets = Dictionary(uniqueKeysWithValues: elements
            .filter { $0.tool == .rect || $0.tool == .ellipse }.map { ($0.id, $0) })
        for index in elements.indices where elements[index].points.count >= 2 {
            for start in [true, false] {
                guard let binding = start ? elements[index].startBinding : elements[index].endBinding else { continue }
                guard let target = targets[binding.targetID] else {
                    if start { elements[index].startBinding = nil } else { elements[index].endBinding = nil }
                    continue
                }
                let local = CGPoint(x: target.rect.minX + binding.anchor.x * target.rect.width,
                                    y: target.rect.minY + binding.anchor.y * target.rect.height)
                let point = boundary(local, target: target).applying(AnnotationGeometry.transform(target))
                let endpoint = start ? 0 : elements[index].points.count - 1
                let old = elements[index].points[endpoint]
                guard old != point else { continue }
                elements[index].points[endpoint] = point
                if !elements[index].controls.isEmpty {
                    let control = start ? 0 : elements[index].controls.count - 1
                    elements[index].controls[control].x += point.x - old.x
                    elements[index].controls[control].y += point.y - old.y
                }
            }
        }
    }

    private static func boundary(_ point: CGPoint, target: AnnotationElement) -> CGPoint {
        let rect = target.rect
        guard rect.width > 0 && rect.height > 0 else { return CGPoint(x: rect.midX, y: rect.midY) }
        if target.tool == .rect && target.resolvedStyle.roundness > 0 {
            var inverse = AnnotationGeometry.transform(target).inverted()
            let path = AnnotationGeometry.path(target).copy(using: &inverse) ?? AnnotationGeometry.path(target)
            var nearest = CGPoint(x: rect.midX, y: rect.minY)
            var distance = CGFloat.infinity
            for points in AnnotationPathSampling.polylines(path) {
                for (a, b) in zip(points, points.dropFirst()) {
                    let dx = b.x - a.x, dy = b.y - a.y
                    let t = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy)
                        / max(0.000_001, dx * dx + dy * dy)))
                    let candidate = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
                    let candidateDistance = hypot(candidate.x - point.x, candidate.y - point.y)
                    if candidateDistance < distance { nearest = candidate; distance = candidateDistance }
                }
            }
            return nearest
        }
        let dx = point.x - rect.midX, dy = point.y - rect.midY
        if target.tool == .ellipse || target.resolvedStyle.shape == .diamond {
            let x = dx / max(rect.width / 2, 0.001), y = dy / max(rect.height / 2, 0.001)
            let denominator = target.tool == .ellipse ? hypot(x, y) : abs(x) + abs(y)
            guard denominator > 0.001 else { return CGPoint(x: rect.midX, y: rect.minY) }
            return CGPoint(x: rect.midX + dx / denominator, y: rect.midY + dy / denominator)
        }
        let x = min(max(point.x, rect.minX), rect.maxX)
        let y = min(max(point.y, rect.minY), rect.maxY)
        let candidates = [CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY),
                          CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y)]
        let nearest = candidates.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) }!
        return nearest
    }
}
