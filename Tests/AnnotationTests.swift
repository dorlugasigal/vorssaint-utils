// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum AnnotationTests {
    static func run(_ expect: (Bool, String) -> Void) {
        testControlPreviews(expect)
        testToolShortcuts(expect)
        testDiagramShapes(expect)
        testCurveControlPreservation(expect)
        testEditing(expect)
        testSelection(expect)
        testShapeStyles(expect)
        testLinear(expect)
        testLinearFinishing(expect)
        testCanvasLinearPoints(expect)
        testBindings(expect)
        testText(expect)
        testFreehand(expect)
        testInteractionFeedback(expect)
        testRoughness(expect)
        testSmartDraw(expect)
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

    private static func testInteractionFeedback(_ expect: (Bool, String) -> Void) {
        var style = AnnotationStyle(color: AnnotationBrush.neonColors[0], width: 20, opacity: 0.35,
                                    smooth: false, isHighlighter: true)
        let origin = CGPoint(x: 50, y: 50)
        expect(AnnotationBrush.neonColors.count == 5
               && AnnotationBrush.neonColors[0] == AnnotationColor(red: 1, green: 244 / 255, blue: 92 / 255)
               && AnnotationBrush.neonColors[4] == AnnotationColor(red: 1, green: 159 / 255, blue: 67 / 255),
               "freehand highlighter has the dedicated neon sRGB palette")
        for scale: CGFloat in [0.5, 1, 2] {
            let tap = AnnotationElement(tool: .freehand, points: [origin], style: style)
            let footprint = AnnotationInteractionFeedback.footprint(style: style, erasing: false, at: origin, scale: scale)
            let ink = AnnotationGeometry.path(tap, scale: scale)
            expect(footprint.boundingBoxOfPath == ink.boundingBoxOfPath,
                   "highlighter cursor matches its actual stamp at \(scale)x")
            expect(abs(footprint.boundingBoxOfPath.width - 13.6 * scale) < 0.001
                   && abs(footprint.boundingBoxOfPath.height - 20 * scale) < 0.001,
                   "flat nib uses source rectangular proportions at \(scale)x")
            let actual = bitmap { AnnotationRenderer.draw(tap, in: $0, scale: scale, shadowsEnabled: false) }
            let expected = bitmap {
                $0.addPath(footprint)
                $0.setFillColor(AnnotationRenderer.color(style).cgColor)
                $0.fillPath()
            }
            expect(actual != nil && actual == expected, "single highlighter click renders its rectangular footprint")
        }
        var marker = AnnotationElement(tool: .freehand, points: [origin], style: style)
        _ = AnnotationGeometry.path(marker)
        marker.appendFreehand([AnnotationInputSample(point: CGPoint(x: 150, y: 50), pressure: 0.3)])
        let markerPixels = bitmap { AnnotationRenderer.draw(marker, in: $0, scale: 1, shadowsEnabled: false) }
        let flatPixels = bitmap {
            $0.setStrokeColor(AnnotationRenderer.color(style).cgColor)
            $0.setLineWidth(20)
            $0.setLineCap(.butt)
            $0.setLineJoin(.bevel)
            $0.move(to: origin)
            $0.addLine(to: CGPoint(x: 150, y: 50))
            $0.strokePath()
        }
        expect(markerPixels != nil && markerPixels == flatPixels,
               "marker transitions from cached tap to flat-ended stroke without retaining a stamp")
        expect(!AnnotationBrush.ink(marker).contains(CGPoint(x: 45, y: 50)),
               "highlighter does not acquire round endpoint caps")
        style.pressure = .hardware
        marker.style = style
        expect(bitmap { AnnotationRenderer.draw(marker, in: $0, scale: 1, shadowsEnabled: false) } == flatPixels,
               "highlighter keeps its flat width instead of inheriting pen pressure taper")

        var penStyle = AnnotationStyle(color: .red, width: 20, pressure: .simulated)
        var pen = AnnotationElement(tool: .freehand, points: [origin], style: penStyle)
        pen.pressures = [0.4]
        expect(AnnotationInteractionFeedback.footprint(style: penStyle, erasing: false, at: origin).boundingBoxOfPath
               == AnnotationGeometry.path(pen).boundingBoxOfPath, "pen cursor previews its initial simulated pressure")
        penStyle.pressure = .constant
        let eraserFootprint = AnnotationInteractionFeedback.footprint(style: penStyle, erasing: true)
        expect(eraserFootprint.boundingBoxOfPath.width == 2 * AnnotationEraserSweep.radius(width: penStyle.width),
               "eraser cursor radius is the sweep hit radius")
        expect(AnnotationInteractionFeedback.footprint(style: AnnotationStyle(color: .red, width: .nan),
               erasing: false).boundingBoxOfPath.width == 6, "cursor sanitizes nonfinite widths")

        let thin = AnnotationElement(tool: .line,
            points: [CGPoint(x: 50, y: 10), CGPoint(x: 50, y: 90)],
            style: AnnotationStyle(color: .red, width: 1))
        var locked = AnnotationElement(tool: .line,
            points: [CGPoint(x: 60, y: 10), CGPoint(x: 60, y: 90)])
        locked.isLocked = true
        let far = AnnotationElement(tool: .rect, rect: CGRect(x: 150, y: 150, width: 30, height: 30))
        var document = AnnotationDocument()
        document.elements = [thin, locked, far]
        document.selectedIDs = [thin.id, locked.id]
        let original = document.state
        var sweep = AnnotationEraserSweep()
        document.begin()
        sweep.begin(at: CGPoint(x: 0, y: 50), elements: document.elements, radius: 8)
        sweep.update(to: CGPoint(x: 100, y: 50), elements: document.elements, radius: 8)
        expect(sweep.pendingIDs == [thin.id], "sparse eraser sweep marks unlocked intersections only")
        expect(document.elements == original.elements && document.selectedIDs == original.selection,
               "pending fade never mutates elements selection styles or order")
        let faded = bitmap {
            $0.setAlpha(AnnotationInteractionFeedback.pendingOpacity)
            AnnotationRenderer.draw(thin, in: $0, scale: 1, shadowsEnabled: false)
        }
        let opaque = bitmap { AnnotationRenderer.draw(thin, in: $0, scale: 1, shadowsEnabled: false) }
        expect(faded != nil && faded != opaque, "pending targets fade through presentation alpha")
        sweep.cancel()
        document.cancel()
        expect(sweep.pendingIDs.isEmpty && document.state == original && !document.history.canUndo,
               "cancel restores exact originals without adding an undo entry")

        document.begin()
        sweep.begin(at: CGPoint(x: 50, y: 50), elements: document.elements, radius: 8)
        sweep.commit(to: &document.state)
        document.commit()
        expect(document.elements == [locked, far] && sweep.pendingIDs.isEmpty,
               "mouse release deletes pending targets and keeps locks")
        document.undo()
        expect(document.elements == original.elements && document.selectedIDs == original.selection
               && !document.history.canUndo, "one undo restores the entire erase including selection")
        document.redo()
        expect(document.elements == [locked, far], "one redo reapplies the whole erase")

        var bound = AnnotationElement(tool: .arrow,
            points: [CGPoint(x: 130, y: 160), CGPoint(x: 150, y: 160)])
        bound.endBinding = AnnotationBinding(targetID: far.id, anchor: CGPoint(x: 0, y: 1 / 3))
        document.elements = [far, bound]
        document.begin()
        sweep.begin(at: CGPoint(x: 180, y: 170), elements: document.elements, radius: 1)
        sweep.commit(to: &document.state)
        document.commit()
        expect(document.elements.count == 1 && document.elements[0].endBinding == nil,
               "release detaches erased binding targets without dangling IDs")
        document.undo()
        expect(document.elements == [far, bound], "undo restores erased targets and endpoint bindings together")
        let emptyCenter = CGPoint(x: 165, y: 165)
        expect(!AnnotationPathSampling.sweptHit(far, from: emptyCenter, to: emptyCenter, tolerance: 1),
               "eraser does not mistake an unfilled shape bounding box for ink")
        let outsideCap = CGPoint(x: 45, y: 50)
        expect(!AnnotationPathSampling.sweptHit(marker, from: outsideCap, to: outsideCap, tolerance: 1),
               "eraser respects the flat marker endpoint")
        var text = AnnotationElement(tool: .text, rect: CGRect(x: 20, y: 20, width: 100, height: 20), text: "rotate")
        text.rotation = .pi / 2
        let rotatedPoint = CGPoint(x: 70, y: 70)
        expect(AnnotationPathSampling.sweptHit(text, from: rotatedPoint, to: rotatedPoint, tolerance: 1),
               "eraser uses rotated text geometry")

        expect(AnnotationInteractionFeedback.isShapeGhost(far, draftID: far.id)
               && !AnnotationInteractionFeedback.isShapeGhost(pen, draftID: pen.id),
               "shape ghost is distinct from freehand ink")
        expect(AnnotationInteractionFeedback.committed([thin, far], draftID: far.id) == [thin],
               "in-progress ghost cannot enter screenshot exports")
        expect(AnnotationInteractionFeedback.committed([thin, far], draftID: nil) == [thin, far],
               "committed shapes export normally after mouse release")
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
        construction.updatePreview(at: CGPoint(x: 100, y: 30), constrained: false, viewScale: 1)
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

    private static func testLinearFinishing(_ expect: (Bool, String) -> Void) {
        for tool: ScreenshotSupport.Tool in [.arrow, .line] {
            let element = AnnotationElement(tool: tool)
            for scale: CGFloat in [0.25, 1, 2] {
                for x: CGFloat in [-1, 1] {
                    for y: CGFloat in [-1, 1] {
                        let start = CGPoint(x: -30, y: 40)
                        let end = CGPoint(x: start.x + 80 * x, y: start.y + 70 * y)
                        var drag = AnnotationLinearConstruction(element: element, at: start, viewScale: scale)
                        drag.updatePreview(at: end, constrained: true, viewScale: scale)
                        let visible = drag.displayed.points
                        expect(drag.release(at: end, constrained: true, viewScale: scale),
                               "\(tool) ordinary drag finishes on release in every quadrant at \(scale)x")
                        expect(drag.finish(commitPreview: false)?.points == visible,
                               "release commits exactly the visible constrained endpoint")
                    }
                }
                var clicks = AnnotationLinearConstruction(element: element, at: .zero, viewScale: scale)
                expect(!clicks.release(at: .zero, constrained: false, viewScale: scale)
                       && clicks.isClickConstruction, "click automatically starts linear construction")
                let second = CGPoint(x: 100, y: 90)
                clicks.updatePreview(at: second, constrained: true, viewScale: scale)
                let vertex = clicks.preview
                clicks.beginPointer(at: second, constrained: true, viewScale: scale)
                expect(clicks.vertices == [.zero], "mouse-down does not commit a construction vertex")
                expect(!clicks.release(at: second, constrained: true, viewScale: scale)
                       && clicks.vertices == [.zero, vertex], "mouse-up commits one snapped vertex")
                let third = CGPoint(x: vertex.x + 8, y: vertex.y + 90)
                clicks.updatePreview(at: third, constrained: true, viewScale: scale)
                expect(clicks.preview == AnnotationLinear.constrained(third, from: vertex),
                       "every new segment constrains from its latest committed anchor")
                clicks.updateConstraint(false, viewScale: scale)
                expect(clicks.preview == third, "releasing Shift restores the raw floating endpoint")
                clicks.updateConstraint(true, viewScale: scale)
                let preview = clicks.preview
                let finished = clicks.finish(commitPreview: true)
                expect(finished?.points == [.zero, vertex, preview], "Enter commits floating preview then finishes")
                expect(finished?.id == element.id, "construction preserves the arrow stable identity")

                var handle = AnnotationLinearConstruction(element: element, at: .zero, viewScale: scale)
                _ = handle.release(at: .zero, constrained: false, viewScale: scale)
                handle.beginPointer(at: second, constrained: false, viewScale: scale)
                _ = handle.release(at: second, constrained: false, viewScale: scale)
                handle.updatePreview(at: third, constrained: false, viewScale: scale)
                let nearHandle = CGPoint(x: second.x + 2 / scale, y: second.y)
                handle.beginPointer(at: nearHandle, constrained: true, viewScale: scale)
                expect(handle.release(at: nearHandle, constrained: true, viewScale: scale),
                       "last committed vertex is a screen-scaled finish handle")
                expect(handle.finish(commitPreview: false)?.points == [.zero, second],
                       "finish handle discards the floating endpoint and never adds a tiny segment")

                var doubleClick = AnnotationLinearConstruction(element: element, at: .zero, viewScale: scale)
                _ = doubleClick.release(at: .zero, constrained: false, viewScale: scale)
                doubleClick.beginPointer(at: second, constrained: true, viewScale: scale)
                expect(doubleClick.release(at: second, constrained: true, viewScale: scale, clickCount: 2),
                       "double-click commits its constrained endpoint and finishes")
                let committed = doubleClick.vertices
                expect(!doubleClick.release(at: second, constrained: true, viewScale: scale, clickCount: 2)
                       && doubleClick.vertices == committed, "repeated release cannot double-commit vertices")

                var snappedDoubleClick = AnnotationLinearConstruction(element: element, at: .zero, viewScale: scale)
                _ = snappedDoubleClick.release(at: .zero, constrained: false, viewScale: scale)
                let rawClick = CGPoint(x: 200, y: 100)
                snappedDoubleClick.beginPointer(at: rawClick, constrained: true, viewScale: scale)
                _ = snappedDoubleClick.release(at: rawClick, constrained: true, viewScale: scale)
                let snappedVertices = snappedDoubleClick.vertices
                snappedDoubleClick.beginPointer(at: rawClick, constrained: true, viewScale: scale)
                expect(snappedDoubleClick.release(at: rawClick, constrained: true, viewScale: scale, clickCount: 2)
                       && snappedDoubleClick.finish(commitPreview: false)?.points == snappedVertices,
                       "second physical click finishes without adding a segment back from the snapped vertex")

                var returnedDrag = AnnotationLinearConstruction(element: element, at: .zero, viewScale: scale)
                returnedDrag.updatePreview(at: CGPoint(x: 5 / scale, y: 0), constrained: false, viewScale: scale)
                expect(returnedDrag.release(at: .zero, constrained: false, viewScale: scale)
                       && returnedDrag.completed == nil,
                       "latched drag returning to origin cancels instead of unexpectedly starting click mode")
                var boundary = AnnotationLinearConstruction(element: element, at: .zero, viewScale: scale)
                expect(!boundary.release(at: CGPoint(x: 4 / scale, y: 0), constrained: false, viewScale: scale),
                       "four-screen-point threshold is a click at every zoom")
            }
        }

        let existing = AnnotationElement(tool: .rect, rect: CGRect(x: 10, y: 10, width: 20, height: 20))
        var document = AnnotationDocument()
        document.elements = [existing]
        document.selectedIDs = [existing.id]
        let original = document.state
        let arrow = AnnotationElement(tool: .arrow)
        var construction = AnnotationLinearConstruction(element: arrow, at: .zero)
        document.begin()
        document.elements.append(construction.displayed)
        _ = construction.release(at: .zero, constrained: false, viewScale: 1)
        construction.updatePreview(at: CGPoint(x: 100, y: 90), constrained: true, viewScale: 1)
        document.elements[1] = construction.displayed
        document.cancel()
        expect(document.elements == original.elements && document.selectedIDs == original.selection
               && !document.history.canUndo, "Escape cancels the entire speculative construction and restores selection")
        document.begin()
        if let finished = construction.finish(commitPreview: true) {
            document.elements.append(finished)
            document.selectedIDs = [finished.id]
        }
        document.commit()
        expect(document.selectedIDs == [arrow.id], "completed arrow is immediately selected")
        document.undo()
        expect(document.elements == [existing] && !document.history.canUndo,
               "one undo removes a completed multi-click arrow")
        document.redo()
        expect(document.elements.count == 2 && document.selectedIDs == [arrow.id],
               "redo restores completed geometry and immediate editing selection")

        for x: CGFloat in [-1, 1] {
            for y: CGFloat in [-1, 1] {
                var style = AnnotationStyle(color: .red, width: 4, curved: true,
                                            startHead: .triangle, endHead: .triangle)
                var curve = AnnotationElement(tool: .arrow,
                    points: [CGPoint(x: 100, y: 100), CGPoint(x: 100 + 80 * x, y: 100 + 60 * y)], style: style)
                curve.controls = [CGPoint(x: 100 + 30 * x, y: 100 + 60 * y),
                                  CGPoint(x: 100 + 20 * x, y: 100 + 40 * y)]
                let shaft = AnnotationLinear.shaftGeometry(curve)
                for index in 0...1 {
                    let oldTangent = CGPoint(x: curve.controls[index].x - curve.points[index].x,
                                            y: curve.controls[index].y - curve.points[index].y)
                    let newTangent = CGPoint(x: shaft.controls[index].x - shaft.points[index].x,
                                            y: shaft.controls[index].y - shaft.points[index].y)
                    expect(hypot(oldTangent.x - newTangent.x, oldTangent.y - newTangent.y) < 0.000_001,
                           "shortening curved shaft preserves its exact endpoint tangent in every quadrant")
                    let delta = CGPoint(x: shaft.points[index].x - curve.points[index].x,
                                        y: shaft.points[index].y - curve.points[index].y)
                    expect(abs(delta.x * oldTangent.y - delta.y * oldTangent.x) < 0.000_001,
                           "curved shaft inset follows the arrowhead tangent instead of its adjacent knot")
                }
                style.startHead = .none
                curve.style = style
                let heads = AnnotationLinear.heads(curve, scale: 1)
                if let head = heads.first, let polygon = AnnotationPathSampling.polylines(head.0).first,
                   polygon.count >= 3 {
                    let tip = polygon[0]
                    let direction = CGPoint(x: tip.x - (polygon[1].x + polygon[2].x) / 2,
                                            y: tip.y - (polygon[1].y + polygon[2].y) / 2)
                    let tangent = CGPoint(x: curve.points[1].x - curve.controls[1].x,
                                          y: curve.points[1].y - curve.controls[1].y)
                    expect(abs(direction.x * tangent.y - direction.y * tangent.x) < 0.000_001
                           && direction.x * tangent.x + direction.y * tangent.y > 0,
                           "arrowhead points along the outward curve tangent in every quadrant")
                    curve.rotation = .pi / 3
                    var transform = AnnotationGeometry.transform(curve)
                    expect(AnnotationLinear.heads(curve, scale: 1).first?.0.boundingBoxOfPath
                           == head.0.copy(using: &transform)?.boundingBoxOfPath,
                           "rotated arrowheads share the shaft world transform")
                } else { expect(false, "curved arrow must have a nonempty triangle head") }
            }
        }
        for length: CGFloat in [0.1, 1, 5, 20, 200] {
            for head in AnnotationArrowhead.allCases {
                let style = AnnotationStyle(color: .red, width: 6, startHead: head, endHead: head)
                let line = AnnotationElement(tool: .arrow, points: [.zero, CGPoint(x: length, y: 0)], style: style)
                let shaft = AnnotationLinear.shaftGeometry(line)
                expect(shaft.points[0].x <= shaft.points[1].x,
                       "short double-headed arrows never reverse their shaft")
            }
        }
        var collapsed = AnnotationElement(tool: .arrow, points: [.zero, .zero],
            style: AnnotationStyle(color: .red, width: 6, curved: true, endHead: .triangle))
        collapsed.controls = [.zero, .zero]
        expect(AnnotationLinear.heads(collapsed, scale: 1).isEmpty,
               "collapsed curve does not acquire a spurious horizontal arrowhead")
        collapsed.points = [.zero, CGPoint(x: 0, y: 50)]
        collapsed.controls = collapsed.points
        expect(AnnotationLinear.endpointAdjacent(collapsed, atStart: false) == .zero,
               "degenerate endpoint control falls back to the neighboring distinct knot")
    }

    private static func testCanvasLinearPoints(_ expect: (Bool, String) -> Void) {
        let base = AnnotationStyle(color: .red, width: 4)
        expect(AnnotationLinear.creationStyle(for: .arrow, base: base).curved,
               "new arrows default to curved routing")
        expect(!AnnotationLinear.creationStyle(for: .line, base: base).curved
               && !AnnotationElement(tool: .arrow).resolvedStyle.curved,
               "straight line defaults and existing legacy annotation styles remain unchanged")
        var curve = AnnotationElement(tool: .arrow,
            points: [CGPoint(x: 20, y: 120), CGPoint(x: 180, y: 120), CGPoint(x: 260, y: 100)],
            style: AnnotationStyle(color: .red, width: 4, curved: true, endHead: .none))
        curve.controls = [CGPoint(x: 40, y: 10), CGPoint(x: 160, y: 30),
                          CGPoint(x: 200, y: 180), CGPoint(x: 240, y: 170)]
        let midpoint = AnnotationLinear.midpoints(curve)[0]
        expect(AnnotationEditGesture.handle(for: curve, at: midpoint, tolerance: 3) == .midpoint(0),
               "curve midpoint is directly reachable on canvas")
        let split = AnnotationLinear.insertingPoint(in: curve, segment: 0)
        expect(split.points == [curve.points[0], midpoint, curve.points[1], curve.points[2]],
               "clicking midpoint inserts a knot on the actual cubic rather than its bounding chord")
        expect(Array(split.controls.suffix(2)) == Array(curve.controls.suffix(2)),
               "subdivision preserves unrelated custom controls")
        let originalSamples = AnnotationPathSampling.polylines(AnnotationLinear.path(curve))[0]
        let splitSamples = AnnotationPathSampling.polylines(AnnotationLinear.path(split))[0]
        for index in 0...16 {
            expect(hypot(originalSamples[index].x - splitSamples[index * 2].x,
                         originalSamples[index].y - splitSamples[index * 2].y) < 0.000_001,
                   "midpoint insertion preserves every sampled point of the original cubic")
        }
        let gesture = AnnotationEditGesture(original: curve, anchor: midpoint, handle: .midpoint(0))
        let destination = CGPoint(x: midpoint.x + 20, y: midpoint.y + 30)
        let moved = gesture.updated(to: destination)
        expect(moved.points[1] == destination && moved.points.count == curve.points.count + 1,
               "dragging a midpoint directly places one new bend")
        expect(gesture.updated(to: CGPoint(x: destination.x + 10, y: destination.y)).points.count == moved.points.count,
               "continuous midpoint drag does not insert a vertex on each mouse sample")
        expect(Array(moved.controls.suffix(2)) == Array(curve.controls.suffix(2)),
               "midpoint dragging keeps unrelated manual curve handles intact")
        var rotated = curve
        rotated.rotation = .pi / 3
        let worldMidpoint = midpoint.applying(AnnotationGeometry.transform(rotated))
        expect(AnnotationEditGesture.handle(for: rotated, at: worldMidpoint, tolerance: 3) == .midpoint(0),
               "rotated midpoint handles hit-test in their painted coordinate system")
        let rotatedGesture = AnnotationEditGesture(original: rotated, anchor: worldMidpoint, handle: .midpoint(0))
        let rotatedDestination = destination.applying(AnnotationGeometry.transform(rotated))
        let rotatedMoved = rotatedGesture.updated(to: rotatedDestination)
        let visiblePoint = rotatedMoved.points[1].applying(AnnotationGeometry.transform(rotatedMoved))
        expect(hypot(visiblePoint.x - rotatedDestination.x, visiblePoint.y - rotatedDestination.y) < 0.000_001,
               "rotated midpoint follows the pointer without shifting the bounds-derived rotation pivot")

        let removed = AnnotationLinear.removingPoint(in: curve, index: 1)
        expect(removed.points == [curve.points[0], curve.points[2]]
               && removed.controls == [curve.controls[0], curve.controls[3]],
               "direct interior-knot removal preserves both outer tangent controls")
        expect(AnnotationLinear.removingPoint(in: curve, index: 0) == curve
               && AnnotationLinear.removingPoint(in: curve, index: curve.points.count - 1) == curve,
               "endpoint double-click cannot delete an arrow endpoint")
        var locked = curve
        locked.isLocked = true
        expect(AnnotationLinear.insertingPoint(in: locked, segment: 0) == locked
               && AnnotationLinear.removingPoint(in: locked, index: 1) == locked,
               "locked arrows reject direct point insertion and removal")
        var document = AnnotationDocument()
        document.elements = [curve]
        document.selectedIDs = [curve.id]
        document.begin()
        document.elements[0] = moved
        document.cancel()
        expect(document.elements == [curve], "cancelling a midpoint drag restores the untouched cubic")
        document.begin()
        document.elements[0] = moved
        document.commit()
        document.undo()
        expect(document.elements == [curve] && !document.history.canUndo,
               "midpoint placement and drag share one undo transaction")
    }

    private static func testBindings(_ expect: (Bool, String) -> Void) {
        let shape = AnnotationElement(tool: .rect, rect: CGRect(x: 20, y: 20, width: 100, height: 80))
        var arrow = AnnotationElement(tool: .arrow, points: [CGPoint(x: 120, y: 60), CGPoint(x: 200, y: 60)])
        var style = arrow.resolvedStyle
        style.bindEndpoints = true
        arrow.style = style
        AnnotationBindings.attach(&arrow, in: [shape], tolerance: 14)
        expect(arrow.startBinding?.targetID == shape.id && arrow.endBinding == nil,
               "only nearby endpoint attaches to a shape")
        var document = AnnotationDocument()
        document.edit { $0.elements = [shape, arrow] }
        document.begin()
        document.elements[0].rect.origin.x += 50
        document.commit()
        expect(document.elements[1].points[0] == CGPoint(x: 170, y: 60), "binding follows target translation")
        document.undo()
        expect(document.elements[1].points[0] == arrow.points[0], "one undo restores target and bound endpoint")
        document.edit { $0.elements.removeFirst() }
        expect(document.elements[0].startBinding == nil && document.elements[0].points[0] == arrow.points[0],
               "deleted target detaches without jumping endpoint")
        document.undo()
        expect(document.elements[1].startBinding?.targetID == shape.id, "undo restores binding identity")
        document.selectedIDs = [shape.id, arrow.id]
        document.edit { AnnotationSelection.apply(.duplicate, to: &$0) }
        let copiedShape = document.elements[2]
        let copiedArrow = document.elements[3]
        expect(copiedArrow.startBinding?.targetID == copiedShape.id
            && copiedArrow.startBinding?.targetID != shape.id, "duplicate remaps binding to copied target")
        var rotated = shape
        rotated.rotation = .pi / 2
        var elements = [rotated, arrow]
        AnnotationBindings.resolve(&elements)
        expect(abs(elements[1].points[0].x - 70) < 0.001 && abs(elements[1].points[0].y - 110) < 0.001,
               "binding resolves through target rotation")
        let unchanged = elements
        AnnotationBindings.resolve(&elements)
        expect(elements == unchanged, "binding resolution is idempotent")
        expect(AnnotationBindings.nearest(to: .zero, in: [arrow], tolerance: 1000) == nil,
               "linear targets cannot create recursive binding graphs")
    }

    private static func testText(_ expect: (Bool, String) -> Void) {
        var text = AnnotationElement(tool: .text, rect: CGRect(x: 20, y: 20, width: 0, height: 0), text: "Hello")
        text.rect = AnnotationRenderer.textBounds(text, scale: 1)
        let singleHeight = text.rect.height
        text.text = "  Hello\nWorld  \n"
        text.rect = AnnotationRenderer.textBounds(text, scale: 1)
        expect(text.text == "  Hello\nWorld  \n" && text.rect.height > singleHeight,
               "multiline text geometry preserves whitespace and newlines")
        for family in AnnotationStyle.FontFamily.allCases {
            for alignment in AnnotationStyle.Alignment.allCases {
                var style = text.resolvedStyle
                style.fontFamily = family
                style.textAlignment = alignment
                style.textSize = 24
                text.style = style
                text.rect = AnnotationRenderer.textBounds(text, scale: 1)
                expect(text.rect.width > 0 && text.rect.height > 24,
                       "font family \(family) alignment \(alignment) has multiline bounds")
                expect(bitmap({ AnnotationRenderer.draw(text, in: $0, scale: 1, shadowsEnabled: false) }) != nil,
                       "font family \(family) alignment \(alignment) renders")
            }
        }
        var document = AnnotationDocument()
        document.edit { $0.elements = [text] }
        document.begin()
        document.elements[0].text = "draft\ninput"
        document.elements[0].style?.textSize = 32
        document.cancel()
        expect(document.elements == [text], "cancel restores text and style together")
        document.begin()
        document.elements[0].text = "committed\ninput"
        document.elements[0].style?.textSize = 32
        document.commit()
        document.undo()
        expect(document.elements == [text], "text and inspector style edits undo in one transaction")
        for language in AppLanguage.allCases {
            expect(AnnotationTextStrings.labels(language).count == 11, "text inspector localized for \(language)")
        }
    }

    private static func testCurveControlPreservation(_ expect: (Bool, String) -> Void) {
        var style = AnnotationStyle(color: .red, width: 3)
        style.curved = true
        var arrow = AnnotationElement(tool: .arrow,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0)], style: style)
        arrow.controls = [CGPoint(x: 10, y: -10), CGPoint(x: 40, y: 10),
                          CGPoint(x: 60, y: 10), CGPoint(x: 90, y: -10)]
        let moved = AnnotationEditGesture(original: arrow, anchor: arrow.points[1], handle: .point(1))
            .updated(to: CGPoint(x: 50, y: 20))
        expect(moved.controls == [CGPoint(x: 10, y: -10), CGPoint(x: 40, y: 30),
                                 CGPoint(x: 60, y: 30), CGPoint(x: 90, y: -10)],
               "moving a curve knot preserves custom tangent handles instead of resetting the curve")
        arrow.rotation = .pi / 2
        let worldPoint = CGPoint(x: 70, y: 25)
        let control = AnnotationEditGesture(original: arrow, anchor: .zero, handle: .control(0))
            .updated(to: worldPoint)
        expect(control.controls[0] == worldPoint.applying(AnnotationGeometry.transform(arrow).inverted())
            && control.controls.dropFirst() == arrow.controls.dropFirst(),
            "rotated curve handles use local coordinates without changing unrelated handles")
        style.headSize = 0
        expect(style.sanitized().headSize == 0.5, "small arrowheads support 50 percent size")
        style.headSize = 5
        expect(style.sanitized().headSize == 2, "large arrowheads are capped at 200 percent size")
    }

    private static func testDiagramShapes(_ expect: (Bool, String) -> Void) {
        let bounds = CGRect(x: 30, y: 20, width: 140, height: 120)
        for shape in AnnotationStyle.Shape.allCases.filter(\.isDiagram) {
            var style = AnnotationStyle(color: .red, width: 3)
            style.shape = shape
            let path = AnnotationDiagramGeometry.path(in: bounds, style: style)
            expect(!path.isEmpty && bounds.insetBy(dx: -0.1, dy: -0.1).contains(path.boundingBoxOfPath),
                   "\(shape) vector geometry stays within its editable bounds")
            let element = AnnotationElement(tool: .rect, rect: bounds, style: style)
            let pixels = bitmap { AnnotationRenderer.draw(element, in: $0, scale: 1, shadowsEnabled: false) }
            expect(pixels?.contains(where: { $0 != 0 }) == true, "\(shape) renders through the shared export path")
            let resized = AnnotationEditGesture(original: element, anchor: .zero, handle: .resize(.bottomRight))
                .updated(to: CGPoint(x: 190, y: 180))
            expect(resized.resolvedStyle.shape == shape && resized.rect.width > element.rect.width,
                   "diagram resize preserves the editable shape type")
        }
        var gridStyle = AnnotationStyle(color: .red, width: 3)
        gridStyle.shape = .grid
        gridStyle.gridRows = 0
        gridStyle.gridColumns = Int.max
        let sanitized = gridStyle.sanitized()
        expect(sanitized.gridRows == 1 && sanitized.gridColumns == 12, "grid dimensions stay bounded")
        var axes = gridStyle
        axes.shape = .axes
        axes.fill = .solid
        expect(axes.sanitized().fill == .none, "axes do not acquire unintended triangular fills")
        let ticked = AnnotationDiagramGeometry.path(in: bounds, style: axes)
        axes.axisTicks = false
        let plain = AnnotationDiagramGeometry.path(in: bounds, style: axes)
        expect(ticked != plain, "axis ticks can be disabled without changing the axes tool")
        for language in AppLanguage.allCases {
            expect(AnnotationDiagramStrings.labels(language).count == 8, "diagram controls localized for \(language)")
        }
    }

    private static func testToolShortcuts(_ expect: (Bool, String) -> Void) {
        for entry in AnnotationToolShortcuts.entries {
            for key in entry.keys {
                let shift = key == "Shift-E"
                let resolved = AnnotationToolShortcuts.resolve(
                    keyCode: -1, characters: shift ? "E" : key, shift: shift, hasApplicationModifier: false)
                expect(resolved == entry.choice, "displayed tool hint \(key) resolves to its visible tool")
            }
        }
        for blocked in [true, false] {
            expect(AnnotationToolShortcuts.resolve(keyCode: 23, characters: "5", shift: false,
                hasApplicationModifier: blocked, isTyping: !blocked) == nil,
                "typing and application shortcuts do not switch annotation tools")
        }
        expect(AnnotationToolShortcuts.resolve(keyCode: 20, characters: "#", shift: true,
            hasApplicationModifier: false) == .shape(.diamond), "shifted number row keeps ZoomIt mapping")
        expect(AnnotationToolShortcuts.resolve(keyCode: 25, characters: "9", shift: false,
            hasApplicationModifier: false) == nil, "reserved 9 does not advertise an unavailable tool")
        expect(AnnotationToolShortcuts.resolve(keyCode: -1, characters: "e", shift: false,
            hasApplicationModifier: false) == nil, "plain E is not mistaken for Shift-E eraser")
        expect(Set(AnnotationToolShortcuts.entries.flatMap(\.keys)).count
            == AnnotationToolShortcuts.entries.flatMap(\.keys).count, "tool bindings are unambiguous")
        expect(AnnotationToolShortcuts.boardKey(characters: "w", controlOnly: true) == .white
            && AnnotationToolShortcuts.boardKey(characters: "k", controlOnly: true) == .black,
            "Control-W and Control-K match ZoomIt board shortcuts")
        expect(AnnotationToolShortcuts.boardKey(characters: "w", controlOnly: false) == nil
            && AnnotationToolShortcuts.boardKey(characters: "w", controlOnly: true, isTyping: true) == nil,
            "board shortcuts do not intercept normal letters or native text editing")
    }

    private static func testControlPreviews(_ expect: (Bool, String) -> Void) {
        let families: [[AnnotationControlPreview]] = [
            AnnotationStyle.Fill.allCases.map { .fill($0) },
            AnnotationStyle.Pattern.allCases.map { .pattern($0) },
            [CGFloat(2), 4, 7].map { .width($0) },
            AnnotationStyle.Shape.allCases.map { .shape($0) },
            [CGFloat(0.75), 1, 1.5].map { .headSize($0) },
            [.route(curved: false), .route(curved: true)]
        ]
        for family in families {
            for color in [AnnotationColor.black, .white] {
                let rendered = family.compactMap { preview in
                    bitmap { context in
                        context.scaleBy(x: 28 / 120, y: 28 / 120)
                        preview.draw(in: context, color: color)
                    }
                }
                expect(rendered.count == family.count && Set(rendered).count == family.count,
                       "visual inspector options remain distinct at their actual icon size")
            }
        }
        for head in AnnotationArrowhead.allCases {
            for start in [false, true] {
                let pixels = bitmap { context in
                    context.scaleBy(x: 28 / 120, y: 28 / 120)
                    AnnotationControlPreview.head(head, start: start).draw(in: context, color: .white)
                }
                expect(pixels?.contains(where: { $0 != 0 }) == true,
                       "each start/end arrowhead option renders a visible preview")
            }
        }
    }

    private static func testFreehand(_ expect: (Bool, String) -> Void) {
        var sampler = AnnotationInputSampler()
        _ = sampler.sample(.zero, timestamp: 0, hardwarePressure: nil, mode: .constant)
        expect(sampler.sample(CGPoint(x: 0.1, y: 0), timestamp: 0.01,
            hardwarePressure: nil, mode: .constant).isEmpty, "freehand input filters subpixel jitter")
        let final = sampler.sample(CGPoint(x: 0.1, y: 0), timestamp: 0.02,
            hardwarePressure: nil, mode: .constant, final: true)
        expect(final.last?.point == CGPoint(x: 0.1, y: 0), "mouse-up retains exact subpixel endpoint")
        var simulated = AnnotationInputSampler()
        _ = simulated.sample(.zero, timestamp: 0, hardwarePressure: nil, mode: .simulated)
        let samples = simulated.sample(CGPoint(x: 100_000, y: 20), timestamp: 0.01,
                                       hardwarePressure: nil, mode: .simulated)
        expect(samples.count == AnnotationInputSampler.maximumSamplesPerEvent,
               "one sparse event has bounded resampling work")
        expect(samples.last?.point == CGPoint(x: 100_000, y: 20)
            && samples.allSatisfy { $0.pressure.isFinite && $0.pressure > 0 && $0.pressure <= 1 },
               "resampling retains endpoint and finite simulated pressure")
        var stroke = AnnotationElement(tool: .freehand)
        for index in 0..<5000 {
            stroke.appendFreehand([AnnotationInputSample(point: CGPoint(x: CGFloat(index) / 10,
                y: sin(CGFloat(index) / 30) * 20 + 50), pressure: 0.5)])
        }
        expect(stroke.points.count == 5000 && stroke.pressures.count == 5000,
               "freehand is never truncated at the old 600-point limit")
        expect(AnnotationGeometry.path(stroke) == AnnotationGeometry.uncachedPath(stroke),
               "cached long stroke matches shared uncached geometry")
        for index in 5000..<5020 {
            stroke.appendFreehand([AnnotationInputSample(point: CGPoint(x: index, y: 40), pressure: 0.5)])
            expect(AnnotationGeometry.path(stroke) == AnnotationGeometry.uncachedPath(stroke),
                   "incremental append preserves exact smoothing and endpoint")
        }
        stroke.points[10].y += 20
        expect(AnnotationGeometry.path(stroke) == AnnotationGeometry.uncachedPath(stroke),
               "editing an interior point invalidates append-only cache")
        let baselineStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<30 { _ = AnnotationGeometry.uncachedPath(stroke) }
        let baseline = ProcessInfo.processInfo.systemUptime - baselineStart
        let cachedStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<30 { _ = AnnotationGeometry.path(stroke) }
        let cached = ProcessInfo.processInfo.systemUptime - cachedStart
        expect(cached < baseline, "unchanged long strokes render with less geometry work than the uncached baseline")
        print(String(format: "ANNOTATION PATH BENCHMARK 5020 points x30: uncached %.6fs, cached %.6fs", baseline, cached))
        var style = stroke.resolvedStyle
        style.pressure = .hardware
        stroke.style = style
        expect(!AnnotationGeometry.path(stroke).isEmpty, "pressure-sensitive stroke has filled geometry")
        let thin = AnnotationElement(tool: .line, points: [CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 100)])
        expect(AnnotationPathSampling.sweptHit(thin, from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50), tolerance: 2),
               "eraser sweep catches thin strokes between sparse events")
        for language in AppLanguage.allCases {
            expect(AnnotationInputStrings.labels(language).count == 5, "input controls localized for \(language)")
        }
    }

    private static func testRoughness(_ expect: (Bool, String) -> Void) {
        var line = AnnotationElement(tool: .line, points: [CGPoint(x: 20, y: 70), CGPoint(x: 170, y: 70)])
        let clean = AnnotationGeometry.path(line)
        var paths: [CGPath] = []
        for character in AnnotationStyle.Character.allCases {
            var style = line.resolvedStyle
            style.character = character
            line.style = style
            let path = AnnotationGeometry.path(line)
            AnnotationPathCache.shared.removeAll()
            expect(path == AnnotationGeometry.path(line), "rough style \(character) is deterministic across redraws")
            paths.append(path)
            for points in AnnotationPathSampling.polylines(path) {
                expect(points.first == line.points.first && points.last == line.points.last,
                       "rough paths keep bound endpoints pinned")
            }
        }
        expect(paths[0] == clean && paths[1] != clean && paths[2] != paths[1],
               "architect artist and cartoonist are distinct opt-in geometries")
        let previous = AnnotationGeometry.path(line)
        line.roughSeed &+= 1
        expect(AnnotationGeometry.path(line) != previous, "rough seed invalidates cached geometry")
        var doubled = line
        doubled.points = line.points.map { CGPoint(x: $0.x * 2, y: $0.y * 2) }
        var scale = CGAffineTransform(scaleX: 2, y: 2)
        expect(AnnotationGeometry.path(line).copy(using: &scale) == AnnotationGeometry.path(doubled, scale: 2),
               "rough geometry scales consistently between logical and Retina pixels")
        for language in AppLanguage.allCases {
            expect(AnnotationStyleStrings.characters(language).count == 4, "rough styles localized for \(language)")
        }
    }

    private static func testSmartDraw(_ expect: (Bool, String) -> Void) {
        func polygon(_ vertices: [CGPoint]) -> [CGPoint] {
            zip(vertices, vertices.dropFirst()).flatMap { a, b in
                (0..<25).map { index in
                    let t = CGFloat(index) / 25
                    return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                }
            } + [vertices.last!]
        }
        let circle = (0...128).map { index -> CGPoint in
            let angle = CGFloat(index) / 128 * 2 * .pi
            return CGPoint(x: 120 + cos(angle) * 80, y: 110 + sin(angle) * 80)
        }
        let ellipse = (0...128).map { index -> CGPoint in
            let angle = CGFloat(index) / 128 * 2 * .pi
            return CGPoint(x: 150 + cos(angle) * 120, y: 110 + sin(angle) * 50)
        }
        let fixtures: [(SmartDrawShapeKind, [CGPoint])] = [
            (.circle, circle), (.ellipse, ellipse),
            (.rectangle, polygon([CGPoint(x: 30, y: 40), CGPoint(x: 210, y: 40), CGPoint(x: 210, y: 140), CGPoint(x: 30, y: 140), CGPoint(x: 30, y: 40)])),
            (.square, polygon([CGPoint(x: 30, y: 40), CGPoint(x: 130, y: 40), CGPoint(x: 130, y: 140), CGPoint(x: 30, y: 140), CGPoint(x: 30, y: 40)])),
            (.diamond, polygon([CGPoint(x: 120, y: 20), CGPoint(x: 200, y: 100), CGPoint(x: 120, y: 180), CGPoint(x: 40, y: 100), CGPoint(x: 120, y: 20)])),
            (.arrow, polygon([CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100), CGPoint(x: 145, y: 65), CGPoint(x: 180, y: 100), CGPoint(x: 145, y: 135)]))
        ]
        for (kind, points) in fixtures {
            let candidate = SmartDrawRecognizer.recognize(points: points, duration: 1, zoomScale: 1)
            expect(candidate?.kind == kind, "ported Smart Draw recognizes \(kind), got \(String(describing: candidate?.kind))")
            expect((candidate?.confidence ?? 0) >= SmartDrawStabilityTracker.mediumConfidenceCommitThreshold,
                   "recognized \(kind) satisfies source confidence policy")
        }
        expect(SmartDrawRecognizer.recognize(points: [.zero, CGPoint(x: 2, y: 2)],
                                            duration: 1, zoomScale: 1) == nil,
               "unsupported short gestures remain freehand")
        var generation = SmartDrawRecognitionGenerationState()
        let first = generation.submit()
        let newest = generation.submit()
        expect(!generation.accepts(first) && generation.accepts(newest), "only latest recognition result can apply")
        generation.beginStroke()
        expect(!generation.accepts(newest), "closing or replacing a stroke rejects late recognition results")
        if var candidate = SmartDrawRecognizer.recognize(points: circle, duration: 1, zoomScale: 1) {
            candidate.confidence = 0.65
            var stability = SmartDrawStabilityTracker()
            expect(stability.commitCandidate(final: candidate) == nil, "medium confidence needs repeated stable observations")
            stability.update(candidate)
            stability.update(candidate)
            expect(stability.commitCandidate(final: candidate) != nil, "consistent preview observations permit medium-confidence commit")
        }
        expect(SmartDrawRecognizer.preparedPoints(Array(repeating: circle, count: 50).flatMap { $0 },
            zoomScale: 1).count <= SmartDrawRecognitionBudget.maximumInputPointCount,
               "recognition bounds input without truncating the document stroke")
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
