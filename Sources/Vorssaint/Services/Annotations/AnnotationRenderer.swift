// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The annotation paint pass, shared by the transparent desktop canvas,
/// screenshot preview and pixel export. Image effects remain in the host.
enum AnnotationRenderer {
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
        var scaled = annotation
        var scaledStyle = style
        scaledStyle.width *= scale
        scaled.style = scaledStyle
        context.saveGState()
        defer { context.restoreGState() }
        if shadowsEnabled {
            context.setShadow(offset: CGSize(width: 0, height: -scale), blur: 3 * scale,
                              color: CGColor(gray: 0, alpha: 0.38))
        }
        context.setStrokeColor(color(style).cgColor)
        context.setFillColor(color(style).cgColor)
        context.setLineWidth(scaledStyle.width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch style.pattern {
        case .solid: break
        case .dashed: context.setLineDash(phase: 0, lengths: [6 * scaledStyle.width, 3 * scaledStyle.width])
        case .dotted: context.setLineDash(phase: 0, lengths: [0, 2.5 * scaledStyle.width])
        }
        let path = AnnotationGeometry.path(scaled)
        if annotation.tool == .rect || annotation.tool == .ellipse {
            drawFill(style, path: path, in: context, scale: scale)
        }
        context.addPath(path)
        switch annotation.tool {
        case .arrow, .redact:
            context.fillPath()
        case .highlight:
            context.setBlendMode(.multiply)
            context.setFillColor(color(style).withAlphaComponent(0.42 * style.opacity * style.color.alpha).cgColor)
            context.fillPath()
        default:
            context.strokePath()
        }
    }

    private static func drawFill(_ style: AnnotationStyle, path: CGPath, in context: CGContext, scale: CGFloat) {
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
        let bounds = path.boundingBoxOfPath
        let step = max(6 * scale, style.width * 2 * scale)
        for x in stride(from: bounds.minX - bounds.height, through: bounds.maxX, by: step) {
            context.move(to: CGPoint(x: x, y: bounds.minY))
            context.addLine(to: CGPoint(x: x + bounds.height, y: bounds.maxY))
            if style.fill == .crossHatch {
                context.move(to: CGPoint(x: x, y: bounds.maxY))
                context.addLine(to: CGPoint(x: x + bounds.height, y: bounds.minY))
            }
        }
        context.strokePath()
    }

    static func font(_ annotation: AnnotationElement, scale: CGFloat) -> NSFont {
        let style = annotation.resolvedStyle
        let size: CGFloat
        switch annotation.stroke {
        case .small: size = 13
        case .medium: size = 19
        case .large: size = 27
        }
        return NSFont.systemFont(ofSize: (style.textSize ?? size) * scale,
                                 weight: style.mediumTextWeight ? .medium : .semibold)
    }

    static func textBounds(_ annotation: AnnotationElement, scale: CGFloat) -> CGRect {
        let text = annotation.text.isEmpty ? " " : annotation.text
        let measured = text.size(withAttributes: [.font: font(annotation, scale: scale)])
        return CGRect(origin: annotation.rect.origin,
                      size: CGSize(width: ceil(measured.width) + 4, height: ceil(measured.height)))
    }

    private static func drawText(_ annotation: AnnotationElement, in context: CGContext,
                                 scale: CGFloat, shadowsEnabled: Bool) {
        guard !annotation.text.isEmpty else { return }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(annotation, scale: scale), .foregroundColor: color(annotation.resolvedStyle)
        ]
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
        annotation.text.draw(at: CGPoint(x: annotation.rect.minX + 2, y: annotation.rect.minY),
                             withAttributes: attributes)
        NSGraphicsContext.current = previous
        context.restoreGState()
    }
}
