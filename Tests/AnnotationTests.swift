// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum AnnotationTests {
    static func run(_ expect: (Bool, String) -> Void) {
        testEditing(expect)
        let size = CGSize(width: 200, height: 200)
        for scale: CGFloat in [1, 2] {
            for tool: ScreenshotSupport.Tool in [.rect, .ellipse, .arrow, .line, .freehand, .redact, .highlight] {
                let element = AnnotationElement(tool: tool,
                    rect: CGRect(x: 30, y: 30, width: 100, height: 80),
                    points: tool.dragsRect ? [] : [CGPoint(x: 30, y: 30), CGPoint(x: 130, y: 110)])
                let actual = bitmap { AnnotationRenderer.draw(element, in: $0, scale: scale, shadowsEnabled: false) }
                let legacy = bitmap { context in
                    context.setStrokeColor(CGColor(srgbRed: 0.93, green: 0.26, blue: 0.21, alpha: 1))
                    context.setFillColor(CGColor(srgbRed: 0.93, green: 0.26, blue: 0.21, alpha: 1))
                    context.setLineWidth(4 * scale)
                    context.setLineCap(.round)
                    context.setLineJoin(.round)
                    switch tool {
                    case .rect: context.stroke(element.rect)
                    case .ellipse: context.strokeEllipse(in: element.rect)
                    case .arrow:
                        context.addPath(ScreenshotSupport.arrowSilhouette(
                            from: element.points[0], to: element.points[1], strokeWidth: 4 * scale))
                        context.fillPath()
                    case .line:
                        context.move(to: element.points[0])
                        context.addLine(to: element.points[1])
                        context.strokePath()
                    case .freehand:
                        context.move(to: element.points[0])
                        context.addQuadCurve(to: CGPoint(x: 80, y: 70), control: element.points[0])
                        context.addLine(to: element.points[1])
                        context.strokePath()
                    case .redact: context.fill(element.rect)
                    case .highlight:
                        context.setBlendMode(.multiply)
                        context.setFillColor(CGColor(srgbRed: 0.93, green: 0.26, blue: 0.21, alpha: 0.42))
                        context.fill(element.rect)
                    default: break
                    }
                }
                expect(actual != nil && actual == legacy, "\(tool) preserves screenshot pixels at \(scale)x")
                expect(AnnotationGeometry.hit(element, at: CGPoint(x: 80, y: 70),
                    scale: scale, imageSize: size), "\(tool) shared geometry is selectable")
            }
        }
        let line = AnnotationElement(tool: .line, points: [CGPoint(x: 20, y: 20), CGPoint(x: 180, y: 180)])
        expect(!AnnotationGeometry.hit(line, at: CGPoint(x: 20, y: 180), scale: 1, imageSize: size),
               "diagonal line bounding box does not steal unrelated clicks")
        let stroke = AnnotationElement(tool: .freehand, points: [CGPoint(x: 0, y: 50), CGPoint(x: 180, y: 50)])
        expect(AnnotationGeometry.hit(stroke, at: CGPoint(x: 90, y: 50), scale: 1, imageSize: size),
               "freehand segment between sparse samples is selectable")
        let ellipse = AnnotationElement(tool: .ellipse, rect: CGRect(x: 20, y: 20, width: 160, height: 160))
        expect(!AnnotationGeometry.hit(ellipse, at: CGPoint(x: 20, y: 20), scale: 1, imageSize: size),
               "ellipse hit geometry matches its visible path")
        for scale: CGFloat in [1, 2] {
            let normalized = ScreenAnnotationSupport.normalized(
                point: AnnotationPoint(x: 50 * scale, y: 70 * scale), in: (200 * scale, 200 * scale))
            expect(normalized == AnnotationPoint(x: 0.25, y: 0.35), "coordinate adapter is scale independent")
        }
    }

    private static func testEditing(_ expect: (Bool, String) -> Void) {
        var history = AnnotationHistory<Int>(limit: 2)
        history.begin(0)
        history.commit(1)
        expect(history.undo(1) == 0, "committed gesture has one undo step")
        history.begin(0)
        history.commit(0)
        expect(history.canRedo && !history.canUndo, "no-op gesture preserves redo")
        history.begin(0)
        expect(history.cancel() == 0 && history.canRedo, "cancel restores without destroying redo")
        expect(history.redo(0) == 1, "redo restores committed gesture")
        for value in 1...3 { history.checkpoint(value) }
        expect(history.undo(4) == 3 && history.undo(3) == 2 && history.undo(2) == nil,
               "shared history retains bounded snapshots")

        let arrow = AnnotationElement(tool: .arrow, points: [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 80)])
        var document = AnnotationDocument()
        document.begin()
        document.elements.append(arrow)
        document.selectedIDs = [arrow.id]
        document.commit()
        expect(document.selectedIDs == [arrow.id], "new arrows retain stable immediate selection")
        let gesture = AnnotationEditGesture(original: arrow, anchor: arrow.points[1], handle: .point(1))
        document.begin()
        for x in 101...300 { document.elements[0] = gesture.updated(to: CGPoint(x: x, y: 90)) }
        document.commit()
        document.undo()
        expect(document.elements == [arrow] && document.selectedIDs == [arrow.id],
               "endpoint edit is atomic and restores selection")
        document.undo()
        expect(document.elements.isEmpty, "second undo removes creation rather than one raw sample")
        document.redo()
        document.begin()
        document.elements.removeAll()
        document.cancel()
        expect(document.elements == [arrow], "cancelled eraser restores original elements")
        document.edit { $0.elements.removeAll() }
        expect(document.selectedIDs.isEmpty, "deleting elements prunes selection")
        document.undo()
        expect(document.elements == [arrow], "clear and delete are reversible edits")
        let freehand = AnnotationElement(tool: .freehand, points: arrow.points)
        expect(AnnotationEditGesture.handle(for: freehand, at: freehand.points[1], tolerance: 12) == nil,
               "freehand sample is not mistaken for a linear endpoint handle")
    }

    private static func bitmap(_ draw: (CGContext) -> Void) -> Data? {
        guard let context = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8,
            bytesPerRow: 800, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        draw(context)
        return Data(bytes: data, count: 160_000)
    }
}
