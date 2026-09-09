// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum AnnotationTests {
    static func run(_ expect: (Bool, String) -> Void) {
        testEditing(expect)
        testSelection(expect)
        testShapeStyles(expect)
        testLinear(expect)
        let visible = CGRect(x: -1920, y: 1080, width: 1920, height: 1050)
        for anchor in [CGRect(x: -1900, y: 1100, width: 50, height: 50),
                       CGRect(x: -100, y: 2050, width: 50, height: 50)] {
            let size = CGSize(width: 280, height: 420)
            let origin = AnnotationPanelPlacement.origin(anchor: anchor, size: size, visibleFrame: visible)
            expect(visible.contains(CGRect(origin: origin, size: size)),
                   "custom color panel stays on its owner monitor at either edge")
        }
        let invalidStyle = AnnotationStyle(color: AnnotationColor(red: .nan, green: 2, blue: -2),
                                           width: .infinity, opacity: .nan).sanitized()
        expect(invalidStyle.color == AnnotationColor(red: 0, green: 1, blue: 0)
            && invalidStyle.width == 6 && invalidStyle.opacity == 1,
               "custom styles sanitize nonfinite channels and dimensions")
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

    private static func testSelection(_ expect: (Bool, String) -> Void) {
        let first = AnnotationElement(tool: .rect, rect: CGRect(x: 20, y: 20, width: 40, height: 30))
        let second = AnnotationElement(tool: .ellipse, rect: CGRect(x: 80, y: 20, width: 40, height: 30))
        var state = AnnotationDocument.Snapshot(elements: [first, second], selection: [first.id, second.id])
        AnnotationSelection.apply(.group, to: &state)
        expect(state.elements[0].groupID != nil && state.elements[0].groupID == state.elements[1].groupID,
               "group operation assigns one stable group")
        expect(AnnotationSelection.expandingGroups([first.id], in: state.elements).count == 2,
               "selecting one group member selects the entire group")
        AnnotationSelection.apply(.duplicate, to: &state)
        expect(state.elements.count == 4 && state.selection.count == 2 && !state.selection.contains(first.id),
               "duplicate creates new identities and selects copies")
        expect(state.elements[2].groupID == state.elements[3].groupID
            && state.elements[0].groupID != state.elements[2].groupID, "duplicate isolates copied group identity")
        AnnotationSelection.apply(.lock, to: &state)
        let locked = state.elements
        for action: AnnotationSelectionAction in [.delete, .rotateLeft, .grow, .front, .duplicate] {
            AnnotationSelection.apply(action, to: &state)
            expect(state.elements == locked, "locked elements resist \(action)")
        }
        state.selection = Set(locked.suffix(2).map(\.id))
        AnnotationSelection.apply(.unlock, to: &state)
        AnnotationSelection.apply(.back, to: &state)
        expect(state.selection.contains(state.elements[0].id), "back layer action preserves relative selection order")
        AnnotationSelection.apply(.ungroup, to: &state)
        expect(state.elements[0].groupID == nil && state.elements[1].groupID == nil, "ungroup clears copied group")
        let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
        expect(AnnotationSelection.marquee(rect, elements: [first, second]).count == 2,
               "marquee selects fully enclosed elements")
        for language in AppLanguage.allCases {
            expect(AnnotationCommandStrings.labels(language).count == AnnotationSelectionAction.allCases.count,
                   "selection actions localized for \(language)")
        }
    }

    private static func testShapeStyles(_ expect: (Bool, String) -> Void) {
        var style = AnnotationStyle(color: .red, width: 4)
        style.shape = .diamond
        var diamond = AnnotationElement(tool: .rect, rect: CGRect(x: 20, y: 20, width: 120, height: 100), style: style)
        let size = CGSize(width: 200, height: 200)
        expect(AnnotationGeometry.hit(diamond, at: CGPoint(x: 80, y: 70), scale: 1, imageSize: size),
               "diamond interior is selectable")
        expect(!AnnotationGeometry.hit(diamond, at: CGPoint(x: 20, y: 20), scale: 1, imageSize: size),
               "diamond does not select rectangular corner outside geometry")
        var rendered: [Data] = []
        for fill in AnnotationStyle.Fill.allCases {
            style.fill = fill
            style.fillColor = .green
            diamond.style = style
            if let pixels = bitmap({ AnnotationRenderer.draw(diamond, in: $0, scale: 1, shadowsEnabled: false) }) {
                rendered.append(pixels)
                expect(pixels == bitmap({ AnnotationRenderer.draw(diamond, in: $0, scale: 1, shadowsEnabled: false) }),
                       "shape fills are deterministic")
            }
        }
        expect(Set(rendered).count == 4, "none solid hatch and crosshatch produce distinct fills")
        style.shape = .standard
        style.roundness = 1
        diamond.style = style
        expect(!AnnotationGeometry.path(diamond).contains(CGPoint(x: 21, y: 21)),
               "rounded rectangle uses rounded geometry for rendering and selection")
        for language in AppLanguage.allCases {
            expect(AnnotationStyleStrings.labels(language).count == 11, "shape styles localized for \(language)")
        }
    }

    private static func testLinear(_ expect: (Bool, String) -> Void) {
        var element = AnnotationElement(tool: .arrow, points: [CGPoint(x: 20, y: 80), CGPoint(x: 160, y: 80)])
        expect(AnnotationLinear.usesLegacyArrow(element), "default screenshot arrow retains legacy silhouette")
        var style = element.resolvedStyle
        for head in AnnotationArrowhead.allCases {
            for size: CGFloat in [1, 1.35, 1.75] {
                style.endHead = head
                style.headSize = size
                element.style = style
                let pixels = bitmap { AnnotationRenderer.draw(element, in: $0, scale: 1, shadowsEnabled: false) }
                expect(pixels != nil, "arrowhead \(head) size \(size) renders")
                expect(element.tool == .arrow, "headless and custom heads retain arrow creation identity")
                for (path, _) in AnnotationLinear.heads(element, scale: 1) {
                    expect(!path.isEmpty && path.boundingBoxOfPath.minX.isFinite,
                           "arrowhead has finite nonempty geometry")
                }
            }
        }
        style.curved = true
        element.style = style
        element.points = [CGPoint(x: 20, y: 90), CGPoint(x: 90, y: 30), CGPoint(x: 160, y: 90)]
        expect(AnnotationLinear.controls(element).count == 4, "curve supplies editable controls for each segment")
        let control = AnnotationLinear.controls(element)[0]
        let gesture = AnnotationEditGesture(original: element, anchor: control, handle: .control(0))
        let edited = gesture.updated(to: CGPoint(x: 45, y: 10))
        expect(edited.controls[0] == CGPoint(x: 45, y: 10) && edited.points == element.points,
               "editing a curve control does not move vertices")
        var construction = AnnotationLinearConstruction(element: element, at: CGPoint(x: 10, y: 10))
        expect(construction.completed == nil, "single click cannot commit a degenerate line")
        construction.preview = CGPoint(x: 100, y: 30)
        expect(construction.completed == nil && construction.displayed.points.count == 2,
               "preview does not finalize a multi-click vertex")
        construction.add(CGPoint(x: 100, y: 30))
        construction.add(CGPoint(x: 100, y: 30))
        expect(construction.completed?.points.count == 2, "duplicate clicks do not add duplicate vertices")
        expect(abs(AnnotationLinear.constrained(CGPoint(x: 20, y: 19), from: .zero).x
            - AnnotationLinear.constrained(CGPoint(x: 20, y: 19), from: .zero).y) < 0.001,
               "shift constraint snaps to 45 degree directions")
        for language in AppLanguage.allCases {
            expect(AnnotationLinearStrings.labels(language).count == 21, "linear inspector localized for \(language)")
        }
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
