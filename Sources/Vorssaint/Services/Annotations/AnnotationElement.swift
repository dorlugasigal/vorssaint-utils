// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Shared session-local geometry. Coordinates have a top-left origin; each
/// host supplies its logical-to-pixel scale rather than normalizing elements.
struct AnnotationElement: Identifiable, Equatable {
    let id: UUID
    var tool: ScreenshotSupport.Tool { didSet { geometryRevision = UUID() } }
    var rect: CGRect { didSet { geometryRevision = UUID() } }
    var points: [CGPoint] { didSet { geometryRevision = UUID(); appendBaseRevision = UUID() } }
    var text: String
    var color: ScreenshotSupport.ColorID
    var stroke: ScreenshotSupport.StrokeID { didSet { geometryRevision = UUID() } }
    var number: Int
    var style: AnnotationStyle? { didSet { geometryRevision = UUID() } }
    var rotation: CGFloat = 0 { didSet { geometryRevision = UUID() } }
    var groupID: UUID?
    var isLocked = false
    var controls: [CGPoint] = [] { didSet { geometryRevision = UUID() } }
    var startBinding: AnnotationBinding?
    var endBinding: AnnotationBinding?
    var pressures: [CGFloat] = [] { didSet { geometryRevision = UUID() } }
    private(set) var geometryRevision = UUID()
    private(set) var appendBaseRevision = UUID()
    var roughSeed: UInt64 = 0 { didSet { geometryRevision = UUID() } }

    mutating func appendFreehand(_ samples: [AnnotationInputSample]) {
        guard !samples.isEmpty else { return }
        let base = appendBaseRevision
        points.append(contentsOf: samples.map(\.point))
        pressures.append(contentsOf: samples.map(\.pressure))
        appendBaseRevision = base
    }

    static func == (lhs: AnnotationElement, rhs: AnnotationElement) -> Bool {
        lhs.id == rhs.id && lhs.tool == rhs.tool && lhs.rect == rhs.rect
            && lhs.points == rhs.points && lhs.text == rhs.text && lhs.color == rhs.color
            && lhs.stroke == rhs.stroke && lhs.number == rhs.number && lhs.style == rhs.style
            && lhs.rotation == rhs.rotation && lhs.groupID == rhs.groupID && lhs.isLocked == rhs.isLocked
            && lhs.controls == rhs.controls && lhs.startBinding == rhs.startBinding
            && lhs.endBinding == rhs.endBinding && lhs.pressures == rhs.pressures
            && lhs.roughSeed == rhs.roughSeed
    }

    init(id: UUID = UUID(), tool: ScreenshotSupport.Tool, rect: CGRect = .zero,
         points: [CGPoint] = [], text: String = "", color: ScreenshotSupport.ColorID = .red,
         stroke: ScreenshotSupport.StrokeID = .medium, number: Int = 0,
         style: AnnotationStyle? = nil) {
        self.id = id
        self.tool = tool
        self.rect = rect
        self.points = points
        self.text = text
        self.color = color
        self.stroke = stroke
        self.number = number
        self.style = style
        roughSeed = id.uuidString.utf8.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
    }

    var resolvedStyle: AnnotationStyle {
        if let style { return style }
        let rgb = color.components
        return AnnotationStyle(color: AnnotationColor(red: rgb.red, green: rgb.green, blue: rgb.blue),
                               width: stroke.width, textSize: tool == .text ? legacyTextSize : nil)
    }

    private var legacyTextSize: CGFloat {
        switch stroke {
        case .small: return 13
        case .medium: return 19
        case .large: return 27
        }
    }
}

struct AnnotationStyle: Equatable {
    enum Fill: Int, CaseIterable { case none, solid, hatch, crossHatch }
    enum Pattern: Int, CaseIterable { case solid, dashed, dotted }
    enum Shape: Int, CaseIterable { case standard, diamond }
    enum FontFamily: Int, CaseIterable { case system, serif, monospace, handwriting }
    enum Alignment: Int, CaseIterable { case left, center, right }
    enum Pressure: Int, CaseIterable { case constant, hardware, simulated }
    enum Character: Int, CaseIterable { case architect, artist, cartoonist }
    var color: AnnotationColor
    var width: CGFloat
    var opacity: CGFloat = 1
    var smooth = true
    var textSize: CGFloat?
    var mediumTextWeight = false
    var fill: Fill = .none
    var fillColor: AnnotationColor = .white
    var pattern: Pattern = .solid
    var shape: Shape = .standard
    var roundness: CGFloat = 0
    var curved = false
    var multiClick = false
    var startHead: AnnotationArrowhead = .none
    var endHead: AnnotationArrowhead = .legacy
    var headSize: CGFloat = 1
    var bindEndpoints = false
    var fontFamily: FontFamily = .system
    var textAlignment: Alignment = .left
    var boldText = false
    var pressure: Pressure = .constant
    var character: Character = .architect

    func sanitized() -> AnnotationStyle {
        var result = self
        result.color = color.clamped()
        result.fillColor = fillColor.clamped()
        result.roundness = roundness.isFinite ? min(max(roundness, 0), 1) : 0
        result.headSize = headSize.isFinite ? min(max(headSize, 1), 1.75) : 1
        result.width = width.isFinite ? min(max(width, 1), 40) : 6
        result.opacity = opacity.isFinite ? min(max(opacity, 0), 1) : 1
        if let textSize { result.textSize = textSize.isFinite ? min(max(textSize, 6), 240) : 19 }
        return result
    }
}

enum AnnotationGeometry {
    static func transform(_ element: AnnotationElement) -> CGAffineTransform {
        let rect = bounds(element)
        return CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: element.rotation)
            .translatedBy(x: -rect.midX, y: -rect.midY)
    }

    static func visualBounds(_ element: AnnotationElement) -> CGRect {
        bounds(element).applying(transform(element))
    }

    static func bounds(_ element: AnnotationElement) -> CGRect {
        guard let first = element.points.first else { return element.rect }
        return element.points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }

    static func path(_ element: AnnotationElement, scale: CGFloat = 1) -> CGPath {
        AnnotationPathCache.shared.path(element, scale: scale) {
            var scaled = element
            var style = element.resolvedStyle
            style.width *= scale
            scaled.style = style
            return uncachedPath(scaled, renderScale: scale)
        }
    }

    static func uncachedPath(_ element: AnnotationElement, renderScale: CGFloat = 1) -> CGPath {
        let path = CGMutablePath()
        switch element.tool {
        case .rect:
            if element.resolvedStyle.shape == .diamond {
                let rect = element.rect
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                path.closeSubpath()
            } else {
                let radius = element.resolvedStyle.roundness * min(element.rect.width, element.rect.height) / 2
                path.addRoundedRect(in: element.rect, cornerWidth: radius, cornerHeight: radius)
            }
        case .redact, .highlight, .pixelate:
            path.addRect(element.rect)
        case .ellipse:
            path.addEllipse(in: element.rect)
        case .arrow, .line:
            if AnnotationLinear.usesLegacyArrow(element) {
                path.addPath(ScreenshotSupport.arrowSilhouette(
                    from: element.points[0], to: element.points[1],
                    strokeWidth: element.resolvedStyle.width))
            } else { path.addPath(AnnotationLinear.path(element)) }
        case .freehand:
            if element.resolvedStyle.pressure != .constant {
                path.addPath(AnnotationFreehand.outline(element))
                break
            }
            guard let first = element.points.first else { return path }
            path.move(to: first)
            for index in 1..<element.points.count {
                let current = element.points[index]
                let previous = element.points[index - 1]
                if element.tool == .freehand && element.resolvedStyle.smooth {
                    path.addQuadCurve(to: CGPoint(x: (current.x + previous.x) / 2,
                                                  y: (current.y + previous.y) / 2),
                                      control: previous)
                } else {
                    path.addLine(to: current)
                }
            }
            if let last = element.points.last { path.addLine(to: last) }
        case .text, .sticker, .counter, .select, .crop: break
        }
        let rough = element.tool == .redact || element.tool == .highlight || element.tool == .pixelate
            ? path : AnnotationRoughness.path(path, character: element.resolvedStyle.character,
                                             seed: element.roughSeed, width: element.resolvedStyle.width, scale: renderScale)
        var transform = transform(element)
        return rough.copy(using: &transform) ?? rough
    }

    static func hit(_ element: AnnotationElement, at point: CGPoint, scale: CGFloat,
                    imageSize: CGSize, includeShapeInteriors: Bool = true) -> Bool {
        let tolerance = 10 * scale
        switch element.tool {
        case .arrow, .line, .freehand:
            var style = element.resolvedStyle
            style.width *= scale
            let geometry = path(element, scale: scale)
            if element.tool == .freehand && element.resolvedStyle.pressure != .constant && geometry.contains(point) {
                return true
            }
            if AnnotationLinear.usesLegacyArrow(element) && geometry.contains(point) { return true }
            if element.tool == .arrow || element.tool == .line {
                for (head, filled) in AnnotationLinear.heads(element, scale: scale) {
                    if filled && head.contains(point) { return true }
                    if head.copy(strokingWithWidth: 2 * tolerance, lineCap: .round,
                                 lineJoin: .round, miterLimit: 10).contains(point) { return true }
                }
            }
            return geometry.copy(strokingWithWidth: 2 * tolerance + style.width,
                                 lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
        case .counter:
            let radius = ScreenshotSupport.counterDiameter(for: imageSize, scale: 1) / 2
            return hypot(point.x - element.rect.midX, point.y - element.rect.midY) <= radius + 4 * scale
        case .rect, .ellipse, .highlight, .pixelate, .redact:
            let geometry = path(element)
            if includeShapeInteriors && geometry.contains(point) { return true }
            return geometry.copy(strokingWithWidth: tolerance, lineCap: .round,
                                 lineJoin: .round, miterLimit: 10).contains(point)
        case .text, .sticker:
            return element.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2)
                .contains(point.applying(transform(element).inverted()))
        case .select, .crop: return false
        }
    }
}
