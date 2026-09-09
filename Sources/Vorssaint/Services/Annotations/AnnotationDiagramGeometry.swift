// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

enum AnnotationDiagramGeometry {
    static func path(in rect: CGRect, style: AnnotationStyle) -> CGPath {
        let path = CGMutablePath()
        guard !rect.isEmpty, !rect.isInfinite, !rect.isNull else { return path }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        func line(_ a: CGPoint, _ b: CGPoint) {
            path.move(to: a)
            path.addLine(to: b)
        }
        switch style.shape {
        case .database:
            path.move(to: point(0, 0.14))
            path.addCurve(to: point(1, 0.14), control1: point(0, -0.045), control2: point(1, -0.045))
            path.addLine(to: point(1, 0.86))
            path.addCurve(to: point(0, 0.86), control1: point(1, 1.045), control2: point(0, 1.045))
            path.closeSubpath()
            path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.28))
        case .queue:
            let gap = rect.height * 0.08
            let height = (rect.height - gap * 2) / 3
            for row in 0..<3 {
                let cell = CGRect(x: rect.minX, y: rect.minY + CGFloat(row) * (height + gap),
                                  width: rect.width, height: height)
                path.addRoundedRect(in: cell, cornerWidth: height * 0.15, cornerHeight: height * 0.15)
                line(CGPoint(x: cell.minX + cell.width * 0.22, y: cell.minY),
                     CGPoint(x: cell.minX + cell.width * 0.22, y: cell.maxY))
            }
        case .person:
            path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.31, y: rect.minY,
                                      width: rect.width * 0.38, height: rect.height * 0.38))
            path.move(to: point(0, 1))
            path.addLine(to: point(0, 0.82))
            path.addCurve(to: point(1, 0.82), control1: point(0, 0.33), control2: point(1, 0.33))
            path.addLine(to: point(1, 1))
            path.closeSubpath()
        case .grid:
            path.addRect(rect)
            let rows = min(max(style.gridRows, 1), 12)
            let columns = min(max(style.gridColumns, 1), 12)
            for row in 1..<rows {
                let y = CGFloat(row) / CGFloat(rows)
                line(point(0, y), point(1, y))
            }
            for column in 1..<columns {
                let x = CGFloat(column) / CGFloat(columns)
                line(point(x, 0), point(x, 1))
            }
        case .axes:
            let origin = point(0.12, 0.88)
            let top = point(0.12, 0), right = point(1, 0.88)
            line(top, origin)
            path.addLine(to: right)
            line(point(0.04, 0.10), top)
            path.addLine(to: point(0.20, 0.10))
            line(point(0.90, 0.80), right)
            path.addLine(to: point(0.90, 0.96))
            if style.axisTicks {
                for tick in 1...4 {
                    let offset = CGFloat(tick) * 0.16
                    line(point(0.12 + offset, 0.85), point(0.12 + offset, 0.91))
                    line(point(0.09, 0.88 - offset), point(0.15, 0.88 - offset))
                }
            }
        case .standard, .diamond:
            break
        }
        return path
    }
}

extension AnnotationStyle.Shape {
    var isDiagram: Bool { self != .standard && self != .diamond }

    var symbolName: String {
        switch self {
        case .standard: return "rectangle"
        case .diamond: return "diamond"
        case .database: return "cylinder"
        case .queue: return "rectangle.stack"
        case .person: return "person"
        case .grid: return "squareshape.split.3x3"
        case .axes: return "chart.xyaxis.line"
        }
    }
}
