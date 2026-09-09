// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Seeded generator and legacy profiles adapted from ZoomIt (Microsoft, 2026).
// Per-edge line/cubic strokes adapted from Rough.js (Preet Shihn, 2019).
// MIT permission notices: docs/ANNOTATION-PROVENANCE.md

import CoreGraphics

enum AnnotationRoughness {
    private struct SketchGenerator {
        var state: UInt32
        mutating func unit() -> CGFloat {
            state = (state &* 48271) & 0x7fff_ffff
            return CGFloat(state) / 2147483648
        }
    }
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
        if closedShape && character == .cartoonist { return sketchOutline(canonical, seed: seed, scale: scale) }
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
                let c1 = CGPoint(x: current.x + (end.x - current.x) / 3, y: current.y + (end.y - current.y) / 3)
                let c2 = CGPoint(x: current.x + (end.x - current.x) * 2 / 3, y: current.y + (end.y - current.y) * 2 / 3)
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

    static func ellipse(in rect: CGRect, seed: UInt64, scale: CGFloat) -> CGPath {
        var random = SketchGenerator(state: UInt32(truncatingIfNeeded: seed) & 0x7fff_ffff)
        if random.state == 0 { random.state = 1 }
        func offset(_ amount: CGFloat) -> CGFloat { 2 * ((random.unit() * 2 * amount) - amount) }
        let rx = rect.width / 2, ry = rect.height / 2
        let estimate = sqrt(CGFloat.pi * 2 * sqrt((pow(rx / scale, 2) + pow(ry / scale, 2)) / 2))
        let count = ceil(max(9, 9 / sqrt(200) * estimate))
        let increment = CGFloat.pi * 2 / count
        // Rough.js consumes the fitting samples even with Excalidraw's curveFitting = 1.
        _ = offset(0)
        _ = offset(0)
        let result = CGMutablePath()
        for pass in 0..<2 {
            let amount: CGFloat = pass == 0 ? scale : 1.5 * scale
            let overlap: CGFloat
            if pass == 0 {
                let upper = 2 * (random.unit() * 0.6 + 0.4)
                overlap = increment * 2 * (random.unit() * (upper - 0.1) + 0.1)
            } else { overlap = 0 }
            let phase = offset(0.5) - CGFloat.pi / 2
            func point(_ angle: CGFloat, factor: CGFloat = 1) -> CGPoint {
                CGPoint(x: rect.midX + factor * rx * cos(angle) + offset(amount),
                        y: rect.midY + factor * ry * sin(angle) + offset(amount))
            }
            var points = [point(phase - increment, factor: 0.9)]
            var angle = phase
            while angle < CGFloat.pi * 2 + phase - 0.01 {
                points.append(point(angle))
                angle += increment
            }
            points.append(point(phase + CGFloat.pi * 2 + overlap * 0.5))
            points.append(point(phase + overlap, factor: 0.98))
            points.append(point(phase + overlap * 0.5, factor: 0.9))
            result.move(to: points[1])
            for index in 1..<(points.count - 2) {
                let a = points[index], b = points[index + 1]
                let c1 = CGPoint(x: a.x + (b.x - points[index - 1].x) / 6,
                                 y: a.y + (b.y - points[index - 1].y) / 6)
                let c2 = CGPoint(x: b.x + (a.x - points[index + 2].x) / 6,
                                 y: b.y + (a.y - points[index + 2].y) / 6)
                result.addCurve(to: b, control1: c1, control2: c2)
            }
        }
        return result
    }

    /// Each edge has its own two strokes. Fill/selection use the separate canonical boundary.
    private static func sketchOutline(_ canonical: CGPath, seed: UInt64, scale: CGFloat) -> CGPath {
        let result = CGMutablePath()
        var random = SketchGenerator(state: UInt32(truncatingIfNeeded: seed) & 0x7fff_ffff)
        if random.state == 0 { random.state = 1 }
        var preserveVertices = false
        canonical.applyWithBlock {
            if $0.pointee.type == .addCurveToPoint || $0.pointee.type == .addQuadCurveToPoint {
                preserveVertices = true
            }
        }
        func offset(_ amount: CGFloat, gain: CGFloat = 1) -> CGFloat {
            2 * gain * ((random.unit() * (2 * amount)) - amount)
        }
        func line(from a: CGPoint, to b: CGPoint) {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = hypot(dx, dy)
            guard length > 0.001 * scale else { return }
            let logicalLength = length / scale
            let gain: CGFloat = logicalLength < 200 ? 1 : logicalLength > 500 ? 0.4 : 1.233334 - 0.0016668 * logicalLength
            let maximum = min(2 * scale, length / 10)
            for pass in 0..<2 {
                let jitter = pass == 0 ? maximum : maximum / 2
                let diverge = 0.2 + random.unit() * 0.2
                let bowX = offset(dy / 100, gain: gain)
                let bowY = offset(-dx / 100, gain: gain)
                let start = preserveVertices ? a : CGPoint(x: a.x + offset(jitter, gain: gain), y: a.y + offset(jitter, gain: gain))
                let first = CGPoint(x: a.x + dx * diverge + bowX + offset(jitter, gain: gain),
                                    y: a.y + dy * diverge + bowY + offset(jitter, gain: gain))
                let second = CGPoint(x: a.x + dx * 2 * diverge + bowX + offset(jitter, gain: gain),
                                     y: a.y + dy * 2 * diverge + bowY + offset(jitter, gain: gain))
                let end = preserveVertices ? b : CGPoint(x: b.x + offset(jitter, gain: gain), y: b.y + offset(jitter, gain: gain))
                result.move(to: start)
                result.addCurve(to: end, control1: first, control2: second)
            }
        }
        func cubic(from a: CGPoint, c1: CGPoint, c2: CGPoint, to b: CGPoint) {
            for pass in 0..<2 {
                let jitter: CGFloat = (pass == 0 ? 2 : 2.3) * scale
                let start = preserveVertices || pass == 0 ? a : CGPoint(x: a.x + offset(2 * scale), y: a.y + offset(2 * scale))
                let first = CGPoint(x: c1.x + offset(jitter), y: c1.y + offset(jitter))
                let second = CGPoint(x: c2.x + offset(jitter), y: c2.y + offset(jitter))
                let end = preserveVertices ? b : CGPoint(x: b.x + offset(jitter), y: b.y + offset(jitter))
                result.move(to: start)
                result.addCurve(to: end, control1: first, control2: second)
            }
        }
        var current = CGPoint.zero
        var start = CGPoint.zero
        canonical.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint: current = element.points[0]; start = current
            case .addLineToPoint:
                line(from: current, to: element.points[0])
                current = element.points[0]
            case .addQuadCurveToPoint:
                let control = element.points[0], end = element.points[1]
                let c1 = CGPoint(x: current.x + (control.x - current.x) * 2 / 3,
                                 y: current.y + (control.y - current.y) * 2 / 3)
                let c2 = CGPoint(x: end.x + (control.x - end.x) * 2 / 3,
                                 y: end.y + (control.y - end.y) * 2 / 3)
                cubic(from: current, c1: c1, c2: c2, to: end)
                current = end
            case .addCurveToPoint:
                cubic(from: current, c1: element.points[0], c2: element.points[1], to: element.points[2])
                current = element.points[2]
            case .closeSubpath:
                line(from: current, to: start)
                current = start
            @unknown default: break
            }
        }
        return result
    }
}
