// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Pending erasure is presentation state, not a mutation of the document.
struct AnnotationEraserSweep {
    private(set) var pendingIDs: Set<UUID> = []
    private var previous: CGPoint?

    static func radius(width: CGFloat) -> CGFloat { max(8, width / 2) }

    mutating func begin(at point: CGPoint, elements: [AnnotationElement], radius: CGFloat) {
        cancel()
        previous = point
        update(to: point, elements: elements, radius: radius)
    }

    mutating func update(to point: CGPoint, elements: [AnnotationElement], radius: CGFloat) {
        guard let previous else { return }
        for element in elements where !element.isLocked && !pendingIDs.contains(element.id) {
            if AnnotationPathSampling.sweptHit(element, from: previous, to: point, tolerance: radius) {
                pendingIDs.insert(element.id)
            }
        }
        self.previous = point
    }

    mutating func commit(to state: inout AnnotationDocument.Snapshot) {
        let removed = Set(state.elements.filter { pendingIDs.contains($0.id) && !$0.isLocked }.map(\.id))
        state.elements.removeAll { removed.contains($0.id) }
        state.selection.subtract(removed)
        AnnotationBindings.resolve(&state.elements)
        cancel()
    }

    mutating func cancel() {
        pendingIDs.removeAll()
        previous = nil
    }
}

enum AnnotationInteractionFeedback {
    static let pendingOpacity: CGFloat = 0.22
    static let ghostOpacity: CGFloat = 0.55

    static func isShapeGhost(_ element: AnnotationElement, draftID: UUID?) -> Bool {
        element.id == draftID && element.tool != .freehand && element.tool != .text
    }

    static func committed(_ elements: [AnnotationElement], draftID: UUID?) -> [AnnotationElement] {
        elements.filter { $0.id != draftID }
    }

    static func footprint(style: AnnotationStyle, erasing: Bool, at point: CGPoint = .zero,
                          scale: CGFloat = 1) -> CGPath {
        let style = style.sanitized()
        if erasing {
            let radius = AnnotationEraserSweep.radius(width: style.width) * scale
            return CGPath(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                           width: 2 * radius, height: 2 * radius), transform: nil)
        }
        let pressure: CGFloat = style.pressure == .simulated && !style.isHighlighter ? 0.4 : 1
        return AnnotationBrush.stamp(at: point, width: style.width * pressure * scale,
                                     highlighter: style.isHighlighter)
    }
}
