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
                     seed: UInt64, width: CGFloat, scale: CGFloat = 1) -> CGPath {
        guard character != .architect else { return canonical }
        let widthScale = 1 + min(0.35, max(0, (sqrt(max(1, width / scale)) - 1) * 0.18))
        let amplitude: CGFloat = (character == .artist ? 3 : 6) * widthScale * scale
        let minimum: CGFloat = character == .artist ? 0.35 : 0.65
        let result = CGMutablePath()
        for pass in 0..<2 {
            var generator = Generator(state: seed ^ (UInt64(pass + 1) &* 0xBF58_476D_1CE4_E5B9))
            let bias: CGFloat = (pass == 0 ? -1 : 1) * (character == .artist ? 0.7 : 4.2) * widthScale * scale
            var current = CGPoint.zero
            var start = CGPoint.zero
            func perturbed(_ control: CGPoint, from a: CGPoint, to b: CGPoint) -> CGPoint {
                let length = hypot(b.x - a.x, b.y - a.y)
                guard length > 0.001 else { return control }
                let random = generator.signedUnit()
                let magnitude = (random < 0 ? -1 : 1) * max(abs(random), minimum)
                let offset = (magnitude * amplitude + bias) * min(1, sqrt(length / (180 * scale)))
                return CGPoint(x: control.x - (b.y - a.y) / length * offset,
                               y: control.y + (b.x - a.x) / length * offset)
            }
            func line(to end: CGPoint) {
                let c1 = CGPoint(x: current.x + (end.x - current.x) / 3,
                                 y: current.y + (end.y - current.y) / 3)
                let c2 = CGPoint(x: current.x + (end.x - current.x) * 2 / 3,
                                 y: current.y + (end.y - current.y) * 2 / 3)
                result.addCurve(to: end, control1: perturbed(c1, from: current, to: end),
                                control2: perturbed(c2, from: current, to: end))
                current = end
            }
            canonical.applyWithBlock { pointer in
                let element = pointer.pointee
                switch element.type {
                case .moveToPoint:
                    current = element.points[0]
                    start = current
                    result.move(to: current)
                case .addLineToPoint: line(to: element.points[0])
                case .addQuadCurveToPoint:
                    let end = element.points[1]
                    result.addQuadCurve(to: end, control: perturbed(element.points[0], from: current, to: end))
                    current = end
                case .addCurveToPoint:
                    let end = element.points[2]
                    result.addCurve(to: end, control1: perturbed(element.points[0], from: current, to: end),
                                    control2: perturbed(element.points[1], from: current, to: end))
                    current = end
                case .closeSubpath:
                    if current != start { line(to: start) }
                    result.closeSubpath()
                @unknown default: break
                }
            }
        }
        return result
    }
}
