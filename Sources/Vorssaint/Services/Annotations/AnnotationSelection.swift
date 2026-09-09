// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum AnnotationSelectionAction: Int, CaseIterable {
    case selectAll, duplicate, delete, group, ungroup, lock, unlock
    case forward, backward, front, back, rotateLeft, rotateRight, grow, shrink

    var symbolName: String {
        switch self {
        case .selectAll: return "checkmark.square"
        case .duplicate: return "plus.square.on.square"
        case .delete: return "trash"
        case .group: return "square.on.square"
        case .ungroup: return "square.dashed"
        case .lock: return "lock"
        case .unlock: return "lock.open"
        case .forward: return "arrow.up"
        case .backward: return "arrow.down"
        case .front: return "arrow.up.to.line"
        case .back: return "arrow.down.to.line"
        case .rotateLeft: return "rotate.left"
        case .rotateRight: return "rotate.right"
        case .grow: return "arrow.up.left.and.arrow.down.right"
        case .shrink: return "arrow.down.right.and.arrow.up.left"
        }
    }
}

enum AnnotationSelection {
    static func expandingGroups(_ ids: Set<UUID>, in elements: [AnnotationElement]) -> Set<UUID> {
        let groups = Set(elements.filter { ids.contains($0.id) }.compactMap(\.groupID))
        return ids.union(elements.filter { $0.groupID.map(groups.contains) == true }.map(\.id))
    }

    static func marquee(_ rect: CGRect, elements: [AnnotationElement]) -> Set<UUID> {
        expandingGroups(Set(elements.filter {
            rect.contains(AnnotationGeometry.visualBounds($0))
        }.map(\.id)), in: elements)
    }

    static func apply(_ action: AnnotationSelectionAction, to state: inout AnnotationDocument.Snapshot) {
        if action == .selectAll { state.selection = Set(state.elements.map(\.id)); return }
        let selection = expandingGroups(state.selection, in: state.elements)
        let editable = Set(state.elements.filter { selection.contains($0.id) && !$0.isLocked }.map(\.id))
        switch action {
        case .selectAll: break
        case .delete:
            state.elements.removeAll { editable.contains($0.id) }
            state.selection.subtract(editable)
        case .duplicate:
            var groups: [UUID: UUID] = [:]
            let originals = state.elements.filter { editable.contains($0.id) }
            let pairs = Array(zip(originals, originals.map { _ in UUID() }))
            let replacements = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0.id, $0.1) })
            let copies = pairs.map { original, id in
                var copy = AnnotationElement(id: id, tool: original.tool,
                    rect: original.rect.offsetBy(dx: 16, dy: 16),
                    points: original.points.map { CGPoint(x: $0.x + 16, y: $0.y + 16) },
                    text: original.text, color: original.color, stroke: original.stroke,
                    number: original.number, style: original.style, centersTextVertically: original.centersTextVertically)
                copy.rotation = original.rotation
                copy.controls = original.controls.map { CGPoint(x: $0.x + 16, y: $0.y + 16) }
                copy.startBinding = original.startBinding?.remapped(replacements)
                copy.endBinding = original.endBinding?.remapped(replacements)
                copy.pressures = original.pressures
                copy.roughSeed = original.roughSeed
                if let group = original.groupID {
                    if groups[group] == nil { groups[group] = UUID() }
                    copy.groupID = groups[group]
                }
                return copy
            }
            guard !copies.isEmpty else { return }
            state.elements.append(contentsOf: copies)
            state.selection = Set(copies.map(\.id))
        case .group, .ungroup:
            let id: UUID? = action == .group && editable.count > 1 ? UUID() : nil
            if action == .group && id == nil { return }
            for index in state.elements.indices where editable.contains(state.elements[index].id) {
                state.elements[index].groupID = id
            }
        case .lock, .unlock:
            for index in state.elements.indices where selection.contains(state.elements[index].id) {
                state.elements[index].isLocked = action == .lock
            }
        case .front, .back:
            let selected = state.elements.filter { editable.contains($0.id) }
            let others = state.elements.filter { !editable.contains($0.id) }
            state.elements = action == .front ? others + selected : selected + others
        case .forward:
            for index in state.elements.indices.reversed() where index + 1 < state.elements.count {
                if editable.contains(state.elements[index].id) && !selection.contains(state.elements[index + 1].id) {
                    state.elements.swapAt(index, index + 1)
                }
            }
        case .backward:
            for index in state.elements.indices where index > 0 {
                if editable.contains(state.elements[index].id) && !selection.contains(state.elements[index - 1].id) {
                    state.elements.swapAt(index, index - 1)
                }
            }
        case .rotateLeft, .rotateRight, .grow, .shrink:
            let angle: CGFloat = action == .rotateLeft ? -.pi / 12 : action == .rotateRight ? .pi / 12 : 0
            let factor: CGFloat = action == .grow ? 1.1 : action == .shrink ? 1 / 1.1 : 1
            transform(&state, rotation: angle, factor: factor)
        }
        state.elements = ScreenshotSupport.renumberingCounters(state.elements)
        AnnotationBindings.resolve(&state.elements)
    }

    static func rotation(of element: AnnotationElement) -> CGFloat {
        if (element.tool == .arrow || element.tool == .line), let first = element.points.first,
           let last = element.points.last, element.points.count >= 2 {
            return atan2(last.y - first.y, last.x - first.x)
        }
        return atan2(sin(element.rotation), cos(element.rotation))
    }

    static func transform(_ state: inout AnnotationDocument.Snapshot, rotation: CGFloat, factor: CGFloat) {
        guard rotation.isFinite, factor.isFinite, factor > 0 else { return }
        let selected = expandingGroups(state.selection, in: state.elements)
        let elements = state.elements.filter { selected.contains($0.id) && !$0.isLocked && $0.tool != .pixelate }
        guard let first = elements.first else { return }
        let editable = Set(elements.map(\.id))
        let bounds = elements.dropFirst().reduce(AnnotationGeometry.visualBounds(first)) {
            $0.union(AnnotationGeometry.visualBounds($1))
        }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: rotation).scaledBy(x: factor, y: factor)
            .translatedBy(x: -center.x, y: -center.y)
        for index in state.elements.indices where editable.contains(state.elements[index].id) {
            var element = state.elements[index]
            if !element.points.isEmpty {
                element.points = element.points.map { $0.applying(transform) }
                element.controls = element.controls.map { $0.applying(transform) }
            } else {
                let old = element.rect
                let movedCenter = CGPoint(x: old.midX, y: old.midY).applying(transform)
                element.rect = CGRect(x: movedCenter.x - old.width * factor / 2,
                                      y: movedCenter.y - old.height * factor / 2,
                                      width: old.width * factor, height: old.height * factor)
                element.rotation += rotation
                if element.tool == .text {
                    var style = element.resolvedStyle
                    style.textSize = min(240, max(6, (style.textSize ?? element.stroke.fontSize) * factor))
                    element.style = style
                }
            }
            state.elements[index] = element
        }
        AnnotationBindings.resolve(&state.elements)
    }
}
