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
    var centersTextVertically = false { didSet { geometryRevision = UUID() } }
    var controls: [CGPoint] = [] { didSet { geometryRevision = UUID() } }
    var startBinding: AnnotationBinding?
    var endBinding: AnnotationBinding?
    var pressures: [CGFloat] = [] { didSet { geometryRevision = UUID() } }
    private(set) var geometryRevision = UUID()
    private(set) var appendBaseRevision = UUID()
    var roughSeed: UInt64 = 0 { didSet { geometryRevision = UUID() } }

    var selectsAfterCreation: Bool {
        tool == .rect || tool == .ellipse || tool == .arrow || tool == .line
    }

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
            && lhs.centersTextVertically == rhs.centersTextVertically
    }

    init(id: UUID = UUID(), tool: ScreenshotSupport.Tool, rect: CGRect = .zero,
         points: [CGPoint] = [], text: String = "", color: ScreenshotSupport.ColorID = .red,
         stroke: ScreenshotSupport.StrokeID = .medium, number: Int = 0,
         style: AnnotationStyle? = nil, centersTextVertically: Bool = false) {
        self.id = id
        self.tool = tool
        self.rect = rect
        self.points = points
        self.text = text
        self.color = color
        self.stroke = stroke
        self.number = number
        self.style = style
        self.centersTextVertically = centersTextVertically
        roughSeed = id.uuidString.utf8.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
    }

    var resolvedStyle: AnnotationStyle {
        if let style { return style }
        let rgb = color.components
        return AnnotationStyle(color: AnnotationColor(red: rgb.red, green: rgb.green, blue: rgb.blue),
                               width: stroke.width, textSize: tool == .text ? stroke.fontSize : nil)
    }
}

struct AnnotationStyle: Codable, Equatable {
    enum Fill: Int, Codable, CaseIterable { case none, solid, hatch, crossHatch }
    enum Pattern: Int, Codable, CaseIterable { case solid, dashed, dotted }
    enum Shape: Int, Codable, CaseIterable { case standard, diamond, database, queue, person, grid, axes }
    enum FontFamily: Int, Codable, CaseIterable { case system, serif, monospace, handwriting }
    enum Alignment: Int, Codable, CaseIterable { case left, center, right }
    enum Pressure: Int, Codable, CaseIterable {
        case constant, hardware, simulated
        static let selectable: [Pressure] = [.constant, .simulated]
    }
    enum Character: Int, Codable, CaseIterable {
        // Preserve the retired artist raw value for existing styles.
        case architect, artist, cartoonist
        static let selectable: [Character] = [.architect, .cartoonist]
    }
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
    var gridRows = 4
    var gridColumns = 4
    var axisTicks = true
    var axisNegative = false
    var curved = false
    var startHead: AnnotationArrowhead = .none
    var endHead: AnnotationArrowhead = .legacy
    var headSize: CGFloat = 1
    var bindEndpoints = true
    var fontFamily: FontFamily = .system
    var textAlignment: Alignment = .left
    var boldText = false
    var pressure: Pressure = .constant
    var character: Character = .architect
    var isHighlighter = false

    var hasVisibleFill: Bool { fill != .none && fillColor.alpha > 0 }

    mutating func setFillColor(_ color: AnnotationColor) {
        fillColor = color.clamped()
        if fillColor.alpha == 0 { fill = .none }
        else if fill == .none { fill = .solid }
    }

    func applyingChanges(from previous: AnnotationStyle, to updated: AnnotationStyle) -> AnnotationStyle {
        var result = self
        func copy<Value: Equatable>(_ key: WritableKeyPath<AnnotationStyle, Value>) {
            if previous[keyPath: key] != updated[keyPath: key] { result[keyPath: key] = updated[keyPath: key] }
        }
        copy(\.color)
        copy(\.width)
        copy(\.opacity)
        copy(\.smooth)
        copy(\.textSize)
        copy(\.mediumTextWeight)
        copy(\.fill)
        copy(\.fillColor)
        copy(\.pattern)
        copy(\.shape)
        copy(\.roundness)
        copy(\.gridRows)
        copy(\.gridColumns)
        copy(\.axisTicks)
        copy(\.axisNegative)
        copy(\.curved)
        copy(\.startHead)
        copy(\.endHead)
        copy(\.headSize)
        copy(\.bindEndpoints)
        copy(\.fontFamily)
        copy(\.textAlignment)
        copy(\.boldText)
        copy(\.pressure)
        copy(\.character)
        copy(\.isHighlighter)
        return result.sanitized()
    }

    func sanitized() -> AnnotationStyle {
        var result = self
        result.gridRows = min(max(gridRows, 1), 12)
        result.gridColumns = min(max(gridColumns, 1), 12)
        if shape == .axes { result.fill = .none }
        result.color = color.clamped()
        result.fillColor = fillColor.clamped()
        result.roundness = roundness.isFinite ? min(max(roundness, 0), 1) : 0
        result.headSize = headSize.isFinite ? min(max(headSize, 0.5), 2) : 1
        result.width = width.isFinite ? min(max(width, 1), 40) : 6
        result.opacity = opacity.isFinite ? min(max(opacity, 0), 1) : 1
        if let textSize { result.textSize = textSize.isFinite ? min(max(textSize, 6), 240) : 19 }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case color, width, opacity, smooth, textSize, mediumTextWeight
        case fill, fillColor, pattern, shape, roundness, gridRows, gridColumns, axisTicks, axisNegative
        case curved, startHead, endHead, headSize, bindEndpoints
        case fontFamily, textAlignment, boldText, pressure, character, isHighlighter
    }
}

extension AnnotationStyle {
    // New style fields must not invalidate defaults saved before their introduction.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(color: try values.decode(AnnotationColor.self, forKey: .color),
                  width: try values.decode(CGFloat.self, forKey: .width))
        opacity = try values.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? opacity
        smooth = try values.decodeIfPresent(Bool.self, forKey: .smooth) ?? smooth
        textSize = try values.decodeIfPresent(CGFloat.self, forKey: .textSize)
        mediumTextWeight = try values.decodeIfPresent(Bool.self, forKey: .mediumTextWeight) ?? mediumTextWeight
        fill = try values.decodeIfPresent(Fill.self, forKey: .fill) ?? fill
        fillColor = try values.decodeIfPresent(AnnotationColor.self, forKey: .fillColor) ?? fillColor
        pattern = try values.decodeIfPresent(Pattern.self, forKey: .pattern) ?? pattern
        shape = try values.decodeIfPresent(Shape.self, forKey: .shape) ?? shape
        roundness = try values.decodeIfPresent(CGFloat.self, forKey: .roundness) ?? roundness
        gridRows = try values.decodeIfPresent(Int.self, forKey: .gridRows) ?? gridRows
        gridColumns = try values.decodeIfPresent(Int.self, forKey: .gridColumns) ?? gridColumns
        axisTicks = try values.decodeIfPresent(Bool.self, forKey: .axisTicks) ?? axisTicks
        axisNegative = try values.decodeIfPresent(Bool.self, forKey: .axisNegative) ?? axisNegative
        curved = try values.decodeIfPresent(Bool.self, forKey: .curved) ?? curved
        startHead = try values.decodeIfPresent(AnnotationArrowhead.self, forKey: .startHead) ?? startHead
        endHead = try values.decodeIfPresent(AnnotationArrowhead.self, forKey: .endHead) ?? endHead
        headSize = try values.decodeIfPresent(CGFloat.self, forKey: .headSize) ?? headSize
        bindEndpoints = try values.decodeIfPresent(Bool.self, forKey: .bindEndpoints) ?? bindEndpoints
        fontFamily = try values.decodeIfPresent(FontFamily.self, forKey: .fontFamily) ?? fontFamily
        textAlignment = try values.decodeIfPresent(Alignment.self, forKey: .textAlignment) ?? textAlignment
        boldText = try values.decodeIfPresent(Bool.self, forKey: .boldText) ?? boldText
        pressure = try values.decodeIfPresent(Pressure.self, forKey: .pressure) ?? pressure
        character = try values.decodeIfPresent(Character.self, forKey: .character) ?? character
        isHighlighter = try values.decodeIfPresent(Bool.self, forKey: .isHighlighter) ?? isHighlighter
        self = sanitized()
    }
}

extension AnnotationColor {
    init(preset: ScreenshotSupport.ColorID) {
        let rgb = preset.components
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
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
        if element.tool == .text || element.tool == .sticker || element.tool == .counter {
            return bounds(element).applying(transform(element))
        }
        let body = path(element)
        var bounds = body.boundingBoxOfPath.insetBy(dx: -element.resolvedStyle.width / 2,
                                                   dy: -element.resolvedStyle.width / 2)
        if element.tool == .arrow || element.tool == .line {
            for (head, _) in AnnotationLinear.heads(element, scale: 1) {
                bounds = bounds.union(head.boundingBoxOfPath)
            }
        }
        return bounds
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

    static func shapeBoundary(_ element: AnnotationElement) -> CGPath {
        AnnotationPathCache.shared.path(element, scale: 1, component: .shapeBoundary) {
            uncachedPath(element, applyRoughness: false)
        }
    }

    static func uncachedPath(_ element: AnnotationElement, renderScale: CGFloat = 1, applyRoughness: Bool = true) -> CGPath {
        let path = CGMutablePath()
        switch element.tool {
        case .rect:
            if element.resolvedStyle.shape.isDiagram {
                path.addPath(AnnotationDiagramGeometry.path(in: element.rect, style: element.resolvedStyle))
            } else if element.resolvedStyle.shape == .diamond {
                let rect = element.rect
                let vertices = [CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                                CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)]
                let cut = min(rect.width, rect.height) * element.resolvedStyle.roundness / 4
                if cut > 0 {
                    for index in vertices.indices {
                        let corner = vertices[index]
                        let before = vertices[(index + 3) % 4], after = vertices[(index + 1) % 4]
                        let incomingLength = max(0.001, hypot(before.x - corner.x, before.y - corner.y))
                        let outgoingLength = max(0.001, hypot(after.x - corner.x, after.y - corner.y))
                        let incoming = CGPoint(x: corner.x + (before.x - corner.x) * cut / incomingLength,
                                               y: corner.y + (before.y - corner.y) * cut / incomingLength)
                        let outgoing = CGPoint(x: corner.x + (after.x - corner.x) * cut / outgoingLength,
                                               y: corner.y + (after.y - corner.y) * cut / outgoingLength)
                        if index == 0 { path.move(to: incoming) } else { path.addLine(to: incoming) }
                        path.addQuadCurve(to: outgoing, control: corner)
                    }
                } else {
                    path.move(to: vertices[0])
                    for vertex in vertices.dropFirst() { path.addLine(to: vertex) }
                }
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
            } else { path.addPath(AnnotationLinear.path(element, renderScale: renderScale)) }
        case .freehand:
            if element.points.count == 1, let point = element.points.first {
                let pressure = element.resolvedStyle.isHighlighter || element.resolvedStyle.pressure == .constant
                    ? 1 : element.pressures.first ?? 1
                path.addPath(AnnotationBrush.stamp(at: point, width: element.resolvedStyle.width * pressure,
                                                   highlighter: element.resolvedStyle.isHighlighter))
                break
            }
            if element.resolvedStyle.pressure != .constant && !element.resolvedStyle.isHighlighter {
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
        let rough = !applyRoughness || element.tool == .redact || element.tool == .highlight || element.tool == .pixelate
            || (element.tool == .freehand && element.resolvedStyle.isHighlighter)
            ? path : AnnotationRoughness.path(path, character: element.resolvedStyle.character,
                                             seed: element.roughSeed, width: element.resolvedStyle.width, scale: renderScale,
                                             closedShape: element.tool == .rect || element.tool == .ellipse)
        var transform = transform(element)
        return rough.copy(using: &transform) ?? rough
    }

    static func hit(_ element: AnnotationElement, at point: CGPoint, scale: CGFloat,
                    imageSize: CGSize, includeShapeInteriors: Bool = true) -> Bool {
        let tolerance = 10 * scale
        switch element.tool {
        case .freehand:
            let ink = AnnotationBrush.ink(element, scale: scale)
            return ink.contains(point) || ink.copy(strokingWithWidth: 2 * tolerance,
                lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
        case .arrow, .line:
            var style = element.resolvedStyle
            style.width *= scale
            let geometry = path(element, scale: scale)
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
            let interior = element.tool == .rect || element.tool == .ellipse ? shapeBoundary(element) : geometry
            if includeShapeInteriors && interior.contains(point) { return true }
            return geometry.copy(strokingWithWidth: tolerance, lineCap: .round,
                                 lineJoin: .round, miterLimit: 10).contains(point)
        case .text, .sticker:
            return element.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2)
                .contains(point.applying(transform(element).inverted()))
        case .select, .crop: return false
        }
    }
}
