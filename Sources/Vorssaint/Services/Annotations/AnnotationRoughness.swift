// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Seeded generator and profile metrics adapted from ZoomIt AnnotationRoughStroke.
// Copyright (c) 2026 Microsoft Corporation. MIT: docs/ANNOTATION-PROVENANCE.md

import CoreGraphics

enum AnnotationRoughness {
    private struct Generator {
        var state: UInt64
        mutating func signedUnit() -> CGFloat {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            return CGFloat(Double(value >> 11) / Double(1 << 53) * 2 - 1)
        }
    }

    static func path(_ canonical: CGPath, character: AnnotationStyle.Character,
                     seed: UInt64, width: CGFloat, scale: CGFloat = 1, closedShape: Bool = false) -> CGPath {
        guard character != .architect else { return canonical }
        let sketch = closedShape && character == .cartoonist
            && min(canonical.boundingBoxOfPath.width, canonical.boundingBoxOfPath.height) > 8 * scale
        let widthScale = 1 + min(0.35, max(0, (sqrt(max(1, width / scale)) - 1) * 0.18))
        let amplitude: CGFloat = (sketch ? 1.4 : character == .artist ? 3 : 6) * widthScale * scale
        let minimum: CGFloat = sketch ? 0 : character == .artist ? 0.35 : 0.65
        let result = CGMutablePath()
        for pass in 0..<2 {
            var generator = Generator(state: seed ^ (UInt64(pass + 1) &* 0xBF58_476D_1CE4_E5B9))
            let bias: CGFloat = sketch ? 0 : (pass == 0 ? -1 : 1) * (character == .artist ? 0.7 : 4.2) * widthScale * scale
            var current = CGPoint.zero
            var start = CGPoint.zero
            var overshoots: [(CGPoint, CGPoint)] = []
            func jittered(_ point: CGPoint) -> CGPoint {
                guard sketch else { return point }
                let amount = min(4 * scale,
                                 min(canonical.boundingBoxOfPath.width, canonical.boundingBoxOfPath.height) * 0.04) * widthScale
                return CGPoint(x: point.x + generator.signedUnit() * amount,
                               y: point.y + generator.signedUnit() * amount)
            }
            func perturbed(_ control: CGPoint, from a: CGPoint, to b: CGPoint) -> CGPoint {
                let length = hypot(b.x - a.x, b.y - a.y)
                guard length > 0.001 else { return control }
                let random = generator.signedUnit()
                let magnitude = (random < 0 ? -1 : 1) * max(abs(random), minimum)
                let offset = (magnitude * amplitude + bias) * min(1, sqrt(length / (180 * scale)))
                return CGPoint(x: control.x - (b.y - a.y) / length * offset,
                               y: control.y + (b.x - a.x) / length * offset)
            }
            func line(to point: CGPoint, closing: Bool = false) {
                let end = closing ? point : jittered(point)
                let c1 = CGPoint(x: current.x + (end.x - current.x) / 3,
                                 y: current.y + (end.y - current.y) / 3)
                let c2 = CGPoint(x: current.x + (end.x - current.x) * 2 / 3,
                                 y: current.y + (end.y - current.y) * 2 / 3)
                result.addCurve(to: end, control1: perturbed(c1, from: current, to: end),
                                control2: perturbed(c2, from: current, to: end))
                let length = hypot(end.x - current.x, end.y - current.y)
                if sketch, overshoots.isEmpty, length > 24 * scale,
                   abs(end.y - current.y) > abs(end.x - current.x), generator.signedUnit() > 0 {
                    let dx = (end.x - current.x) / length, dy = (end.y - current.y) / length
                    let extra = min(length * 0.06, 12 * widthScale * scale) * (0.5 + abs(generator.signedUnit()))
                    let sideways = generator.signedUnit() * 4 * widthScale * scale
                    let retrace = CGPoint(x: end.x - dx * length * 0.18, y: end.y - dy * length * 0.18)
                    overshoots.append((retrace, CGPoint(x: end.x + dx * extra - dy * sideways,
                                                       y: end.y + dy * extra + dx * sideways)))
                }
                current = end
            }
            canonical.applyWithBlock { pointer in
                let element = pointer.pointee
                switch element.type {
                case .moveToPoint:
                    current = jittered(element.points[0])
                    start = current
                    result.move(to: current)
                case .addLineToPoint: line(to: element.points[0])
                case .addQuadCurveToPoint:
                    let end = jittered(element.points[1])
                    result.addQuadCurve(to: end, control: perturbed(element.points[0], from: current, to: end))
                    current = end
                case .addCurveToPoint:
                    let end = jittered(element.points[2])
                    result.addCurve(to: end, control1: perturbed(element.points[0], from: current, to: end),
                                    control2: perturbed(element.points[1], from: current, to: end))
                    current = end
                case .closeSubpath:
                    if current != start { line(to: start, closing: true) }
                    result.closeSubpath()
                @unknown default: break
                }
            }
            // Keep the closed contours for fill/hit testing; open accents only add small corner overdraw.
            for (from, to) in overshoots {
                result.move(to: from)
                result.addLine(to: to)
            }
        }
        return result
    }
}
