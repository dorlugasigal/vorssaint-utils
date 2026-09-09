// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The annotation paint pass, shared by the transparent desktop canvas,
/// screenshot preview and pixel export. Image effects remain in the host.
enum AnnotationRenderer {
    static func drawLinearMidpoints(_ element: AnnotationElement, in context: CGContext, scale: CGFloat) {
        guard !element.isLocked else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineDash(phase: 0, lengths: [])
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setFillColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(scale)
        for point in AnnotationLinear.midpoints(element) {
            let radius = 4 * scale
            context.move(to: CGPoint(x: point.x, y: point.y - radius))
            context.addLine(to: CGPoint(x: point.x + radius, y: point.y))
            context.addLine(to: CGPoint(x: point.x, y: point.y + radius))
            context.addLine(to: CGPoint(x: point.x - radius, y: point.y))
            context.closePath()
            context.drawPath(using: .fillStroke)
        }
    }

    static func drawLinearFinishHandle(at point: CGPoint, in context: CGContext, scale: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        let radius = 7 * scale
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
        context.setLineDash(phase: 0, lengths: [])
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2 * scale)
        context.fillEllipse(in: rect)
        context.strokeEllipse(in: rect)
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fillEllipse(in: rect.insetBy(dx: 4 * scale, dy: 4 * scale))
    }

    static func color(_ style: AnnotationStyle) -> NSColor {
        let rgb = style.color.clamped()
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha * style.opacity)
    }

    static func draw(_ annotation: AnnotationElement, in context: CGContext,
                     scale: CGFloat, shadowsEnabled: Bool) {
        let style = annotation.resolvedStyle
        if annotation.tool == .text {
            drawText(annotation, in: context, scale: scale, shadowsEnabled: shadowsEnabled)
            return
        }
        var scaledStyle = style
        scaledStyle.width *= scale
        context.saveGState()
        defer { context.restoreGState() }
        if shadowsEnabled {
            context.setShadow(offset: CGSize(width: 0, height: -scale), blur: 3 * scale,
                              color: CGColor(gray: 0, alpha: 0.38))
        }
        context.setStrokeColor(color(style).cgColor)
        context.setFillColor(color(style).cgColor)
        context.setLineWidth(scaledStyle.width)
        let highlighter = annotation.tool == .freehand && style.isHighlighter
        context.setLineCap(highlighter ? .butt : .round)
        context.setLineJoin(highlighter ? .bevel : .round)
        switch highlighter ? .solid : style.pattern {
        case .solid: break
        case .dashed: context.setLineDash(phase: 0, lengths: [6 * scaledStyle.width, 3 * scaledStyle.width])
        case .dotted: context.setLineDash(phase: 0, lengths: [0.01 * scaledStyle.width, 2.5 * scaledStyle.width])
        }
        let path = AnnotationGeometry.path(annotation, scale: scale)
        if annotation.tool == .rect || annotation.tool == .ellipse {
            drawFill(annotation, path: path, in: context, scale: scale)
        }
        context.addPath(path)
        switch annotation.tool {
        case .arrow where AnnotationLinear.usesLegacyArrow(annotation):
            context.fillPath()
        case .redact:
            context.setFillColor(color(style).withAlphaComponent(1).cgColor)
            context.fillPath()
        case .freehand where annotation.points.count == 1 || (style.pressure != .constant && !highlighter):
            context.fillPath()
        case .highlight:
            context.setBlendMode(.multiply)
            context.setFillColor(color(style).withAlphaComponent(0.42 * style.opacity * style.color.alpha).cgColor)
            context.fillPath()
        default:
            context.strokePath()
        }
        if (annotation.tool == .arrow || annotation.tool == .line) && !AnnotationLinear.usesLegacyArrow(annotation) {
            context.setLineDash(phase: 0, lengths: [])
            for (head, filled) in AnnotationLinear.heads(annotation, scale: scale) {
                context.addPath(head)
                filled ? context.fillPath() : context.strokePath()
            }
        }
    }

    private static func drawFill(_ element: AnnotationElement, path: CGPath, in context: CGContext, scale: CGFloat) {
        let style = element.resolvedStyle
        guard style.fill != .none else { return }
        context.saveGState()
        defer { context.restoreGState() }
        var fillStyle = style
        fillStyle.color = style.fillColor
        context.setFillColor(color(fillStyle).cgColor)
        if style.fill == .solid {
            context.addPath(path)
            context.fillPath()
            return
        }
        context.addPath(path)
        context.clip()
        context.setStrokeColor(color(fillStyle).cgColor)
        context.setLineWidth(max(1, scale))
        context.setLineDash(phase: 0, lengths: [])
        let hatch = AnnotationPathCache.shared.path(element, scale: scale, component: .hatch) {
            let bounds = path.boundingBoxOfPath
            let step = max(6 * scale, style.width * 2 * scale)
            let hatch = CGMutablePath()
            for x in stride(from: bounds.minX - bounds.height, through: bounds.maxX, by: step) {
                hatch.move(to: CGPoint(x: x, y: bounds.minY))
                hatch.addLine(to: CGPoint(x: x + bounds.height, y: bounds.maxY))
                if style.fill == .crossHatch {
                    hatch.move(to: CGPoint(x: x, y: bounds.maxY))
                    hatch.addLine(to: CGPoint(x: x + bounds.height, y: bounds.minY))
                }
            }
            return AnnotationRoughness.path(hatch, character: style.character, seed: element.roughSeed ^ 0x4841544348,
                                            width: scale, scale: scale)
        }
        context.addPath(hatch)
        context.strokePath()
    }

    static func font(_ annotation: AnnotationElement, scale: CGFloat) -> NSFont {
        let style = annotation.resolvedStyle
        let fontSize = (style.textSize ?? annotation.stroke.fontSize) * scale
        let weight: NSFont.Weight = style.boldText ? .bold : style.mediumTextWeight ? .medium : .semibold
        switch style.fontFamily {
        case .system: return NSFont.systemFont(ofSize: fontSize, weight: weight)
        case .serif:
            return NSFont(name: style.boldText ? "Georgia-Bold" : "Georgia", size: fontSize)
                ?? NSFont.systemFont(ofSize: fontSize, weight: weight)
        case .monospace: return NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        case .handwriting:
            return NSFont(name: style.boldText ? "ChalkboardSE-Bold" : "ChalkboardSE-Regular", size: fontSize)
                ?? NSFont.systemFont(ofSize: fontSize, weight: weight)
        }
    }

    static func textBounds(_ annotation: AnnotationElement, scale: CGFloat) -> CGRect {
        let text = annotation.text.isEmpty ? " " : annotation.text
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: 100_000, height: 100_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font(annotation, scale: scale)]).size
        let size = CGSize(width: ceil(measured.width) + 4, height: ceil(measured.height))
        var origin = annotation.rect.origin
        switch annotation.resolvedStyle.textAlignment {
        case .left: break
        case .center: origin.x = annotation.rect.midX - size.width / 2
        case .right: origin.x = annotation.rect.maxX - size.width
        }
        if annotation.centersTextVertically { origin.y = annotation.rect.midY - size.height / 2 }
        return CGRect(origin: origin, size: size)
    }

    private static func drawText(_ annotation: AnnotationElement, in context: CGContext,
                                 scale: CGFloat, shadowsEnabled: Bool) {
        guard !annotation.text.isEmpty else { return }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(annotation, scale: scale), .foregroundColor: color(annotation.resolvedStyle)
        ]
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment(annotation.resolvedStyle.textAlignment)
        attributes[.paragraphStyle] = paragraph
        if shadowsEnabled {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 2.5 * scale
            shadow.shadowOffset = NSSize(width: 0, height: -scale)
            attributes[.shadow] = shadow
        }
        context.saveGState()
        let previous = NSGraphicsContext.current
        context.concatenate(AnnotationGeometry.transform(annotation))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        if annotation.text.contains("\n") || annotation.resolvedStyle.textAlignment != .left {
            annotation.text.draw(in: annotation.rect.insetBy(dx: 2, dy: 0), withAttributes: attributes)
        } else {
            annotation.text.draw(at: CGPoint(x: annotation.rect.minX + 2, y: annotation.rect.minY),
                                 withAttributes: attributes)
        }
        NSGraphicsContext.current = previous
        context.restoreGState()
    }

    static func alignment(_ alignment: AnnotationStyle.Alignment) -> NSTextAlignment {
        switch alignment {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}
