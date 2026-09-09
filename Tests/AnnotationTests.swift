// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum AnnotationTests {
    static func run(_ expect: (Bool, String) -> Void) {
        testEditing(expect)
        testSelection(expect)
        testShapeStyles(expect)
        testLinear(expect)
        testBindings(expect)
        testText(expect)
        testFreehand(expect)
        testRoughness(expect)
        testSmartDraw(expect)
        testPreferencesAndChannels(expect)
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
                if let head1 = AnnotationLinear.heads(element, scale: 1).first?.0 {
                    var doubled = element
                    doubled.points = element.points.map { CGPoint(x: $0.x * 2, y: $0.y * 2) }
                    let head2 = AnnotationLinear.heads(doubled, scale: 2).first?.0
                    expect(abs((head2?.boundingBoxOfPath.height ?? 0) - head1.boundingBoxOfPath.height * 2) < 0.001,
                           "arrowhead \(head) size \(size) preserves logical dimensions at Retina scale")
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

    private static func testBindings(_ expect: (Bool, String) -> Void) {
        let shape = AnnotationElement(tool: .rect, rect: CGRect(x: 20, y: 20, width: 100, height: 80))
        var arrow = AnnotationElement(tool: .arrow, points: [CGPoint(x: 120, y: 60), CGPoint(x: 200, y: 60)])
        var style = arrow.resolvedStyle
        style.bindEndpoints = true
        arrow.style = style
        AnnotationBindings.attach(&arrow, in: [shape], tolerance: 14)
        expect(arrow.startBinding?.targetID == shape.id && arrow.endBinding == nil,
               "only nearby endpoint attaches to a shape")
        let overlapping = AnnotationElement(tool: .rect, rect: shape.rect)
        AnnotationBindings.attach(&arrow, in: [shape, overlapping], tolerance: 14)
        expect(arrow.startBinding?.targetID == shape.id, "existing bindings do not jump to overlapping new targets")
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
        var one = AnnotationInputSampler(), two = AnnotationInputSampler()
        _ = one.sample(.zero, timestamp: 0, hardwarePressure: nil, mode: .simulated)
        _ = two.sample(.zero, timestamp: 0, hardwarePressure: nil, mode: .simulated, coordinateScale: 2)
        let oneSample = one.sample(CGPoint(x: 50, y: 20), timestamp: 0.1, hardwarePressure: nil, mode: .simulated)
        let twoSample = two.sample(CGPoint(x: 100, y: 40), timestamp: 0.1, hardwarePressure: nil, mode: .simulated, coordinateScale: 2)
        expect(oneSample.last?.pressure == twoSample.last?.pressure && oneSample.count == twoSample.count,
               "pressure and resampling are invariant to canvas coordinate scale")
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
        let longBuilds = AnnotationPathCache.shared.statistics.fullBuilds
        let baselineStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<30 { _ = AnnotationGeometry.uncachedPath(stroke) }
        let baseline = ProcessInfo.processInfo.systemUptime - baselineStart
        let cachedStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<30 { _ = AnnotationGeometry.path(stroke) }
        let cached = ProcessInfo.processInfo.systemUptime - cachedStart
        expect(AnnotationPathCache.shared.statistics.fullBuilds == longBuilds,
               "unchanged long strokes do not rebuild geometry")
        print(String(format: "ANNOTATION PATH BENCHMARK 5020 points x30: uncached %.6fs, cached %.6fs", baseline, cached))
        var style = stroke.resolvedStyle
        style.pressure = .hardware
        stroke.style = style
        expect(!AnnotationGeometry.path(stroke).isEmpty, "pressure-sensitive stroke has filled geometry")
        let thin = AnnotationElement(tool: .line, points: [CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 100)])
        expect(AnnotationPathSampling.sweptHit(thin, from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50), tolerance: 2),
               "eraser sweep catches thin strokes between sparse events")
        AnnotationPathCache.shared.removeAll()
        let scene = (0..<200).map { index in
            AnnotationElement(tool: .rect, rect: CGRect(x: index, y: index, width: 40, height: 30))
        }
        for element in scene { _ = AnnotationGeometry.path(element) }
        let builds = AnnotationPathCache.shared.statistics.fullBuilds
        let sceneStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<30 { for element in scene { _ = AnnotationGeometry.uncachedPath(element) } }
        let sceneBaseline = ProcessInfo.processInfo.systemUptime - sceneStart
        let sceneCachedStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<30 { for element in scene { _ = AnnotationGeometry.path(element) } }
        let sceneCached = ProcessInfo.processInfo.systemUptime - sceneCachedStart
        expect(AnnotationPathCache.shared.statistics.fullBuilds == builds,
               "unchanged many-element scene does not rebuild paths")
        expect(AnnotationPathCache.shared.statistics.entries == scene.count,
               "repeated scene rendering retains one body-cache entry per element")
        print(String(format: "ANNOTATION SCENE BENCHMARK 200 elements x30: uncached %.6fs, cached %.6fs", sceneBaseline, sceneCached))
        for index in 0..<400 {
            _ = AnnotationGeometry.path(AnnotationElement(tool: .rect, rect: CGRect(x: index, y: 0, width: 20, height: 20)))
        }
        expect(AnnotationPathCache.shared.statistics.entries <= 256, "geometry cache bounds retained entries without truncating documents")
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

    private static func testPreferencesAndChannels(_ expect: (Bool, String) -> Void) {
        let suite = "com.vorssaint.annotation-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            expect(false, "isolated annotation preference suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        var style = AnnotationStyle(color: .purple, width: 9)
        style.fill = .crossHatch
        style.curved = true
        style.fontFamily = .serif
        style.isHighlighter = true
        AnnotationStylePreferences.save(["pen": style], defaults: defaults, key: DefaultsKey.screenAnnotationStyles)
        expect(AnnotationStylePreferences.load(defaults: defaults, key: DefaultsKey.screenAnnotationStyles)["pen"] == style,
               "typed per-tool styles round-trip through isolated preferences")
        expect(AnnotationStylePreferences.load(defaults: defaults, key: DefaultsKey.screenshotAnnotationStyles).isEmpty,
               "live and screenshot defaults remain scoped to their host")
        let primary = AnnotationStyle(color: .red, width: 2)
        var other = AnnotationStyle(color: .blue, width: 9)
        other.fill = .hatch
        var updated = primary
        updated.color = .green
        let merged = other.applyingChanges(from: primary, to: updated)
        expect(merged.color == .green && merged.width == 9 && merged.fill == .hatch,
               "multi-selection color edits preserve unrelated mixed widths and fills")
        var document = AnnotationDocument()
        let element = AnnotationElement(tool: .rect, rect: CGRect(x: 20, y: 20, width: 100, height: 80), style: primary)
        document.edit { $0.elements = [element]; $0.selection = [element.id] }
        document.begin()
        document.edit { $0.elements[0].style?.color = .green }
        document.edit { $0.elements[0].style?.fillColor = .purple }
        document.commit()
        document.undo()
        expect(document.elements == [element], "color channel switches coalesce under one outer picker transaction")
        document.begin()
        document.edit { AnnotationSelection.transform(&$0, rotation: 37 * .pi / 180, factor: 1.7) }
        document.commit()
        expect(abs(document.elements[0].rotation - 37 * .pi / 180) < 0.001
            && abs(document.elements[0].rect.width - 170) < 0.001, "selection supports arbitrary rotation and scale")
        document.undo()
        expect(document.elements == [element], "continuous transforms remain one undo transaction")
        let keys = AnnotationTool.allCases.map(\.shortcutKey)
        expect(Set(keys).count == keys.count, "live tool shortcuts are unambiguous")
        expect(ScreenshotSupport.Tool.allCases.prefix(9) == [.select, .arrow, .pixelate, .crop, .text, .sticker, .rect, .highlight, .freehand],
               "screenshot tool order and numbered defaults remain unchanged")
        var redactStyle = primary
        redactStyle.opacity = 0
        redactStyle.color.alpha = 0
        let redact = AnnotationElement(tool: .redact, rect: CGRect(x: 20, y: 20, width: 100, height: 80), style: redactStyle)
        let redacted = bitmap { AnnotationRenderer.draw(redact, in: $0, scale: 1, shadowsEnabled: false) }
        let pixel = redacted.map { Array($0[((50 * 200 + 50) * 4)..<((50 * 200 + 50) * 4 + 4)]) }
        expect(pixel?.last == 255, "solid redaction cannot accidentally become transparent: \(String(describing: pixel))")
    }

    private static func bitmap(_ draw: (CGContext) -> Void) -> Data? {
        guard let context = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8,
            bytesPerRow: 800, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.translateBy(x: 0, y: 200)
        context.scaleBy(x: 1, y: -1)
        draw(context)
        return Data(bytes: data, count: 160_000)
    }
}
