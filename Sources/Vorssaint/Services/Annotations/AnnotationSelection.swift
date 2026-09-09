// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum AnnotationSelectionAction: Int, CaseIterable {
    case selectAll, duplicate, delete, group, ungroup, lock, unlock
    case forward, backward, front, back, rotateLeft, rotateRight, grow, shrink
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
                    number: original.number, style: original.style)
                copy.rotation = original.rotation
                copy.controls = original.controls.map { CGPoint(x: $0.x + 16, y: $0.y + 16) }
                copy.startBinding = original.startBinding?.remapped(replacements)
                copy.endBinding = original.endBinding?.remapped(replacements)
                copy.pressures = original.pressures
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
            let elements = state.elements.filter { editable.contains($0.id) }
            guard let first = elements.first else { return }
            let bounds = elements.dropFirst().reduce(AnnotationGeometry.visualBounds(first)) {
                $0.union(AnnotationGeometry.visualBounds($1))
            }
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let angle: CGFloat = action == .rotateLeft ? -.pi / 12 : action == .rotateRight ? .pi / 12 : 0
            let factor: CGFloat = action == .grow ? 1.1 : action == .shrink ? 1 / 1.1 : 1
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angle).scaledBy(x: factor, y: factor)
                .translatedBy(x: -center.x, y: -center.y)
            for index in state.elements.indices where editable.contains(state.elements[index].id) {
                var element = state.elements[index]
                // Screenshot sampling regions remain axis-aligned.
                if element.tool == .pixelate { continue }
                let old = AnnotationGeometry.bounds(element)
                if !element.points.isEmpty {
                    element.points = element.points.map { $0.applying(transform) }
                    element.controls = element.controls.map { $0.applying(transform) }
                    state.elements[index] = element
                    continue
                }
                let movedCenter = CGPoint(x: old.midX, y: old.midY).applying(transform)
                let local = CGAffineTransform(translationX: movedCenter.x, y: movedCenter.y)
                    .scaledBy(x: factor, y: factor).translatedBy(x: -old.midX, y: -old.midY)
                element.points = element.points.map { $0.applying(local) }
                element.rect = element.rect.applying(local)
                element.rotation += angle
                state.elements[index] = element
            }
        }
        state.elements = ScreenshotSupport.renumberingCounters(state.elements)
        AnnotationBindings.resolve(&state.elements)
    }
}
