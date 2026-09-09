// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

final class AnnotationSmartDraw {
    @discardableResult
    static func applyResult(_ converted: AnnotationElement, replacing original: AnnotationElement,
                            to elements: inout [AnnotationElement], tolerance: CGFloat) -> Bool {
        guard converted.id == original.id,
              let index = elements.firstIndex(where: {
                  $0 == original && $0.geometryRevision == original.geometryRevision
              }) else { return false }
        elements[index] = converted
        AnnotationBindings.finishEdit([converted.id], elements: &elements, tolerance: tolerance)
        return true
    }

    private var generation = SmartDrawRecognitionGenerationState()
    private var stability = SmartDrawStabilityTracker()
    private var work: DispatchWorkItem?
    private var cancellation: Progress?
    private let queue = DispatchQueue(label: "com.vorssaint.annotation-recognition", qos: .userInitiated)
    private var lastTime: TimeInterval?
    private var lastCount = 0

    func cancel() {
        work?.cancel()
        cancellation?.cancel()
        work = nil
        generation.beginStroke()
        stability.reset()
        lastTime = nil
        lastCount = 0
    }

    func preview(_ element: AnnotationElement, timestamp: TimeInterval, duration: TimeInterval, scale: CGFloat) {
        guard SmartDrawRecognitionBudget.shouldRecognizePreview(
            lastRecognitionTime: lastTime, lastRecognizedSampleCount: lastCount,
            timestamp: timestamp, sampleCount: element.points.count) else { return }
        lastTime = timestamp
        lastCount = element.points.count
        recognize(element, duration: duration, scale: scale, quality: .preview) { [weak self] candidate in
            self?.stability.update(candidate)
        }
    }

    func finish(_ element: AnnotationElement, duration: TimeInterval, scale: CGFloat,
                apply: @escaping (AnnotationElement) -> Void) {
        recognize(element, duration: duration, scale: scale, quality: .final) { [weak self] candidate in
            guard let self, let candidate = self.stability.commitCandidate(final: candidate) else { return }
            var converted = element
            converted.tool = candidate.element.tool
            converted.rect = candidate.element.rect
            converted.points = candidate.element.points
            converted.rotation = candidate.rotation
            converted.controls = []
            converted.pressures = []
            var style = element.resolvedStyle
            style.shape = candidate.kind == .diamond ? .diamond : .standard
            if candidate.kind == .arrow { style.endHead = .arrow }
            converted.style = style
            apply(converted)
        }
    }

    private func recognize(_ element: AnnotationElement, duration: TimeInterval, scale: CGFloat,
                           quality: SmartDrawRecognitionQuality,
                           completion: @escaping (SmartDrawCandidate?) -> Void) {
        work?.cancel()
        cancellation?.cancel()
        let cancellation = Progress(totalUnitCount: 1)
        self.cancellation = cancellation
        let token = generation.submit()
        let points = SmartDrawRecognizer.preparedPoints(element.points, zoomScale: scale)
        let operation = DispatchWorkItem { [weak self] in
            guard !cancellation.isCancelled else { return }
            let candidate = SmartDrawRecognizer.recognize(points: points, duration: duration,
                                                          zoomScale: scale, quality: quality)
            guard !cancellation.isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation.accepts(token) else { return }
                completion(candidate)
                self.work = nil
            }
        }
        work = operation
        queue.async(execute: operation)
    }
}
