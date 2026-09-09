// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// One bounded history per host, including any host-owned pixels. Continuous
/// input is speculative until commit; cancellation never destroys redo.
struct AnnotationHistory<State: Equatable> {
    private var past: [State] = []
    private var future: [State] = []
    private var pending: State?
    let limit: Int

    init(limit: Int = 60) { self.limit = max(1, limit) }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    var isEditing: Bool { pending != nil }
    var lastUndo: State? { past.last }

    mutating func begin(_ state: State) {
        if pending == nil { pending = state }
    }

    mutating func commit(_ state: State) {
        guard let original = pending else { return }
        pending = nil
        if original != state { checkpoint(original) }
    }

    mutating func cancel() -> State? {
        defer { pending = nil }
        return pending
    }

    mutating func checkpoint(_ state: State) {
        guard pending == nil else { return }
        past.append(state)
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
    }

    @discardableResult
    mutating func discardLastCheckpoint() -> State? { past.popLast() }

    mutating func undo(_ current: State) -> State? {
        guard pending == nil, let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    mutating func redo(_ current: State) -> State? {
        guard pending == nil, let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }
}

struct AnnotationDocument {
    struct Snapshot: Equatable {
        var elements: [AnnotationElement] = []
        var selection: Set<UUID> = []
        static func == (lhs: Snapshot, rhs: Snapshot) -> Bool { lhs.elements == rhs.elements }
    }

    var state = Snapshot()
    private(set) var history = AnnotationHistory<Snapshot>()
    var elements: [AnnotationElement] {
        get { state.elements }
        set { state.elements = newValue }
    }
    var selectedIDs: Set<UUID> {
        get { state.selection }
        set { state.selection = newValue.intersection(Set(elements.map(\.id))) }
    }

    mutating func begin() { history.begin(state) }
    mutating func commit() {
        AnnotationBindings.resolve(&state.elements)
        history.commit(state)
    }
    mutating func cancel() {
        if let original = history.cancel() { state = original }
    }
    mutating func undo() {
        cancel()
        if let previous = history.undo(state) { state = previous }
    }
    mutating func redo() {
        cancel()
        if let next = history.redo(state) { state = next }
    }
    mutating func edit(_ body: (inout Snapshot) -> Void) {
        begin()
        body(&state)
        state.selection.formIntersection(Set(elements.map(\.id)))
        commit()
    }
}

/// A gesture always transforms its original geometry, avoiding cumulative
/// floating-point drift and keeping points, bounds and endpoint handles aligned.
struct AnnotationEditGesture {
    enum Handle: Equatable {
        case move
        case resize(ScreenshotSupport.Handle)
        case point(Int)
        case control(Int)
        case midpoint(Int)
    }
    let original: AnnotationElement
    let anchor: CGPoint
    let handle: Handle

    static func handle(for element: AnnotationElement, at point: CGPoint,
                       tolerance: CGFloat) -> Handle? {
        guard !element.isLocked else { return nil }
        let point = point.applying(AnnotationGeometry.transform(element).inverted())
        if element.tool == .arrow || element.tool == .line {
            if let index = element.points.indices.first(where: {
                hypot(element.points[$0].x - point.x, element.points[$0].y - point.y) <= tolerance
            }) { return .point(index) }
            let midpoints = AnnotationLinear.midpoints(element)
            if let index = midpoints.indices.first(where: {
                hypot(midpoints[$0].x - point.x, midpoints[$0].y - point.y) <= tolerance
            }) { return .midpoint(index) }
            if element.resolvedStyle.curved {
                let controls = AnnotationLinear.controls(element)
                if let index = controls.indices.first(where: {
                    hypot(controls[$0].x - point.x, controls[$0].y - point.y) <= tolerance
                }) { return .control(index) }
            }
        }
        if element.tool.resizesWithHandles,
           let handle = ScreenshotSupport.handle(at: point, rect: element.rect, tolerance: tolerance) {
            return .resize(handle)
        }
        return nil
    }

    func updated(to point: CGPoint) -> AnnotationElement {
        guard !original.isLocked else { return original }
        var result = original
        switch handle {
        case .midpoint(let segment):
            let split = AnnotationLinear.insertingPoint(in: original, segment: segment)
            guard split.points.count == original.points.count + 1 else { return original }
            return AnnotationEditGesture(original: split, anchor: anchor, handle: .point(segment + 1)).updated(to: point)
        case .move:
            let delta = CGPoint(x: point.x - anchor.x, y: point.y - anchor.y)
            result.rect = original.rect.offsetBy(dx: delta.x, dy: delta.y)
            result.points = original.points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
            result.controls = original.controls.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
            result.startBinding = nil
            result.endBinding = nil
        case .control(let index):
            result.controls = AnnotationLinear.controls(original)
            if result.controls.indices.contains(index) {
                result.controls[index] = point.applying(AnnotationGeometry.transform(original).inverted())
            }
        case .point(let index):
            if result.points.indices.contains(index) {
                let localPoint = point.applying(AnnotationGeometry.transform(original).inverted())
                let previousPoint = result.points[index]
                result.points[index] = localPoint
                if original.resolvedStyle.curved || !original.controls.isEmpty {
                    result.controls = AnnotationLinear.controls(original)
                    for controlIndex in [index * 2 - 1, index * 2]
                    where result.controls.indices.contains(controlIndex) {
                        result.controls[controlIndex].x += localPoint.x - previousPoint.x
                        result.controls[controlIndex].y += localPoint.y - previousPoint.y
                    }
                }
                if index == 0 { result.startBinding = nil }
                if index == result.points.count - 1 { result.endBinding = nil }
            }
        case .resize(let handle):
            result.rect = ScreenshotSupport.resizedRect(original.rect, dragging: handle,
                to: point.applying(AnnotationGeometry.transform(original).inverted()))
            let center = CGPoint(x: result.rect.midX, y: result.rect.midY)
                .applying(AnnotationGeometry.transform(original))
            result.rect.origin = CGPoint(x: center.x - result.rect.width / 2,
                                         y: center.y - result.rect.height / 2)
        }
        return result
    }
}
