// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum AnnotationTextPlacement {
    enum Target: Equatable {
        case text(UUID)
        case create(CGPoint, centered: Bool)
        case locked
        case linear
    }

    static func target(at point: CGPoint, elements: [AnnotationElement], scale: CGFloat,
                       imageSize: CGSize, excluding: UUID? = nil, selection: Set<UUID> = []) -> Target {
        if let owner = AnnotationEditGesture.owner(at: point, in: elements, selection: selection,
                                                   scale: scale, imageSize: imageSize),
           owner.tool == .arrow || owner.tool == .line,
           AnnotationEditGesture.handle(for: owner, at: point, tolerance: 12 * scale, scale: scale) != nil {
            return .linear
        }
        guard let hit = elements.last(where: {
            $0.id != excluding && AnnotationGeometry.hit($0, at: point, scale: scale, imageSize: imageSize)
        }) else { return .create(point, centered: false) }
        if hit.isLocked { return .locked }
        switch hit.tool {
        case .text: return .text(hit.id)
        case .rect, .ellipse:
            let center = CGPoint(x: hit.rect.midX, y: hit.rect.midY).applying(AnnotationGeometry.transform(hit))
            if let label = elements.last(where: {
                $0.tool == .text && AnnotationGeometry.hit($0, at: center, scale: scale, imageSize: imageSize)
            }) { return label.isLocked ? .locked : .text(label.id) }
            return .create(center, centered: true)
        case .arrow, .line: return .linear
        default: return .create(point, centered: false)
        }
    }

    static func editorFrame(for element: AnnotationElement, preferredSize: CGSize = CGSize(width: 100, height: 80),
                            bounds: CGRect, viewScale: CGFloat = 1) -> CGRect {
        let required = CGSize(width: element.rect.width + 4 / viewScale,
                              height: element.rect.height + 20 / viewScale)
        var size = CGSize(width: max(required.width, min(preferredSize.width, bounds.width)),
                          height: max(required.height, min(preferredSize.height, bounds.height)))
        var origin = element.rect.origin
        switch element.resolvedStyle.textAlignment {
        case .left:
            size.width = max(required.width, min(size.width, max(0, bounds.maxX - origin.x)))
        case .center:
            size.width = max(required.width, min(size.width, max(0, 2 * min(element.rect.midX - bounds.minX, bounds.maxX - element.rect.midX))))
            origin.x = element.rect.midX - size.width / 2
        case .right:
            size.width = max(required.width, min(size.width, max(0, element.rect.maxX - bounds.minX)))
            origin.x = element.rect.maxX - size.width
        }
        if element.centersTextVertically {
            size.height = max(required.height, min(size.height, max(0, 2 * min(element.rect.midY - bounds.minY, bounds.maxY - element.rect.midY))))
            origin.y = element.rect.midY - size.height / 2
        } else {
            size.height = max(required.height, min(size.height, max(0, bounds.maxY - origin.y)))
        }
        // Screen bounds limit spare editing room, not the text itself or its anchor.
        return CGRect(origin: origin, size: size)
    }
}
