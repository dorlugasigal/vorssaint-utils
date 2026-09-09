// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

struct AnnotationDisplayGeometry: Equatable {
    let id: UInt32
    let frame: CGRect
    let scale: CGFloat

    static func clampedToolbarFrame(_ frame: CGRect, visibleFrame: CGRect) -> CGRect {
        let size = CGSize(width: min(frame.width, visibleFrame.width),
                          height: min(frame.height, visibleFrame.height))
        let origin = CGPoint(x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
                             y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }

    func isCompatible(with displays: [AnnotationDisplayGeometry]) -> Bool {
        id != 0 && displays.contains(self)
    }

    static func toolbarFrame(size: CGSize, visibleFrame: CGRect) -> CGRect {
        let width = min(max(size.width, 300), visibleFrame.width)
        let height = min(max(size.height, 44), visibleFrame.height)
        return CGRect(x: visibleFrame.midX - width / 2,
                      y: min(visibleFrame.minY + 24, visibleFrame.maxY - height),
                      width: width, height: height)
    }
}

enum AnnotationTool: String, Codable, CaseIterable {
    case select
    case pen
    case highlighter
    case arrow
    case line
    case rectangle
    case ellipse
    case text
    case redact
    case eraser

    var isRectangular: Bool {
        switch self {
        case .rectangle, .ellipse, .redact: return true
        case .select, .text, .eraser, .pen, .highlighter, .arrow, .line: return false
        }
    }

    var isFreehand: Bool { self == .pen || self == .highlighter }

    var elementTool: ScreenshotSupport.Tool? {
        switch self {
        case .select, .eraser: return nil
        case .pen, .highlighter: return .freehand
        case .arrow: return .arrow
        case .line: return .line
        case .rectangle: return .rect
        case .ellipse: return .ellipse
        case .text: return .text
        case .redact: return .redact
        }
    }
}

struct AnnotationColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    var alpha: Double = 1

    static let red = AnnotationColor(red: 0.95, green: 0.18, blue: 0.18)
    static let orange = AnnotationColor(red: 0.98, green: 0.36, blue: 0.02)
    static let yellow = AnnotationColor(red: 1.0, green: 0.82, blue: 0.02)
    static let green = AnnotationColor(red: 0.20, green: 0.78, blue: 0.35)
    static let blue = AnnotationColor(red: 0.18, green: 0.45, blue: 0.95)
    static let purple = AnnotationColor(red: 0.69, green: 0.32, blue: 0.87)
    static let black = AnnotationColor(red: 0.09, green: 0.09, blue: 0.11)
    static let white = AnnotationColor(red: 1, green: 1, blue: 1)

    func clamped() -> AnnotationColor {
        AnnotationColor(red: red.clamped(to: 0...1), green: green.clamped(to: 0...1),
                        blue: blue.clamped(to: 0...1), alpha: alpha.clamped(to: 0...1))
    }
}

enum ScreenAnnotationSupport {
    static let defaultWidth = 6.0

    /// The canvas remains visible after Escape so existing strokes stay on
    /// screen, but it must stop participating in hit testing outside drawing.
    static func canvasIgnoresMouseEvents(isDrawing: Bool) -> Bool { !isDrawing }

    static func activationClosesOverlay(hasOverlay: Bool, isDrawing: Bool) -> Bool {
        hasOverlay && isDrawing
    }

}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        isFinite ? min(max(self, range.lowerBound), range.upperBound) : range.lowerBound
    }
}
