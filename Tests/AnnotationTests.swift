// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum AnnotationTests {
    static func run(_ expect: (Bool, String) -> Void) {
        testControlPreviews(expect)
        testColorPalette(expect)
        testSimplifiedPreferences(expect)
        testPathSampling(expect)
        testStraightLineTool(expect)
        testToolbarExpansion(expect)
        testTextPlacement(expect)
        testGrowingTextEditor(expect)
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
        testSmartDrawResults(expect)
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
            let start = CGPoint(x: 50 * scale, y: 70 * scale), end = CGPoint(x: 150 * scale, y: 170 * scale)
            var line = AnnotationLinearConstruction(element: AnnotationElement(tool: .line), at: start, viewScale: 1 / scale)
            _ = line.release(at: end, constrained: false, viewScale: 1 / scale)
            expect(line.completed?.points == [start, end], "production line input preserves coordinates at both scales")
        }
    }

    private static func testStraightLineTool(_ expect: (Bool, String) -> Void) {
        var legacy = AnnotationStyle(color: .blue, width: 4)
        legacy.curved = true
        legacy.startHead = .triangle
        legacy.endHead = .arrow
        let start = CGPoint(x: 20, y: 30), end = CGPoint(x: 150, y: 90)
        let element = AnnotationElement(tool: .line, points: [start, start], style: legacy)
        var click = AnnotationLinearConstruction(element: element, at: start)
        expect(!click.release(at: start, constrained: false, viewScale: 1), "line first click sets its start")
        click.beginPointer(at: end, constrained: false, viewScale: 1)
        expect(click.release(at: end, constrained: false, viewScale: 1), "line second click finishes without waypoints")
        guard let line = click.completed else { expect(false, "straight line completes"); return }
        expect(line.points == [start, end] && !line.resolvedStyle.curved, "line uses exactly two straight endpoints")
        expect(line.resolvedStyle.startHead == .none && line.resolvedStyle.endHead == .none, "line cannot inherit arrowheads")
        expect(AnnotationLinear.midpoints(line).isEmpty, "line does not advertise bend handles")
        expect(AnnotationLinear.insertingPoint(in: line, segment: 0) == line, "line cannot acquire a bend by insertion")
        click.add(CGPoint(x: 200, y: 140))
        expect(click.completed?.points.count == 2, "line construction stays two-point even after repeated updates")
        var drag = AnnotationLinearConstruction(element: element, at: start)
        expect(drag.release(at: end, constrained: false, viewScale: 1), "ordinary line drag still finishes on release")
        expect(AnnotationLinear.constrainedStyle(legacy, for: .arrow) == legacy, "arrow curves and heads remain configurable")
        for language in AppLanguage.allCases {
            expect(AnnotationPickerStrings.Field.allCases.allSatisfy {
                !AnnotationPickerStrings.text($0, language).isEmpty
            }, "all inspector section labels localized")
        }
    }

    private static func testSimplifiedPreferences(_ expect: (Bool, String) -> Void) {
        var style = AnnotationStyle(color: .red, width: 4)
        expect(!style.hasVisibleFill, "unchosen background hides fill options")
        style.setFillColor(.blue)
        expect(style.fill == .solid && style.hasVisibleFill, "choosing a background enables fill")
        style.fill = .crossHatch
        style.setFillColor(.green)
        expect(style.fill == .crossHatch, "changing background preserves the chosen fill pattern")
        style.setFillColor(AnnotationColor(red: 0, green: 0, blue: 0, alpha: 0))
        expect(style.fill == .none && !style.hasVisibleFill, "transparent background hides fill options")
        expect(AnnotationStyle.Pressure.selectable == [.constant, .simulated], "pressure picker omits tablet")
        expect(!AnnotationArrowhead.selectable.contains(.legacy)
               && AnnotationArrowhead.selectable.first == AnnotationArrowhead.none, "arrowhead picker offers one no-head option")
    }

    private static func testSmartDrawResults(_ expect: (Bool, String) -> Void) {
        let target = AnnotationElement(tool: .rect, rect: CGRect(x: 100, y: 100, width: 80, height: 80))
        let stroke = AnnotationElement(tool: .freehand, points: [CGPoint(x: 20, y: 140), CGPoint(x: 100, y: 140)])
        var converted = stroke
        converted.tool = .arrow
        for grouped in [false, true] {
            var changed = stroke
            if grouped { changed.groupID = UUID() } else { changed.isLocked = true }
            expect(changed.geometryRevision == stroke.geometryRevision, "lock/group does not invalidate geometry cache")
            var elements = [target, changed]
            expect(!AnnotationSmartDraw.applyResult(converted, replacing: stroke, to: &elements, tolerance: 14)
                   && elements == [target, changed], "late recognition cannot overwrite lock/group commands")
        }
        var document = AnnotationDocument()
        document.elements = [target]
        document.begin()
        document.elements.append(stroke)
        document.commit()
        expect(AnnotationSmartDraw.applyResult(converted, replacing: stroke, to: &document.state.elements, tolerance: 14),
               "unchanged stroke accepts recognition")
        expect(document.elements[1].endBinding?.targetID == target.id, "recognized arrow binds its nearby endpoint")
        document.edit { $0.elements[0].rect.origin.x += 40 }
        expect(document.elements[1].points.last == CGPoint(x: 140, y: 140), "recognized arrow follows target movement")
        document.undo()
        expect(document.elements[1].points.last == CGPoint(x: 100, y: 140), "target move undo restores recognized arrow")
        document.undo()
        expect(document.elements == [target], "one creation undo removes the recognized arrow")
        document.redo()
        expect(document.elements.count == 2 && document.elements[1].tool == .arrow
               && document.elements[1].endBinding?.targetID == target.id, "redo restores recognized geometry and bindings")
    }

    private static func testGrowingTextEditor(_ expect: (Bool, String) -> Void) {
        let bounds = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        for alignment in AnnotationStyle.Alignment.allCases {
            for scale: CGFloat in [0.5, 1, 2] {
                var style = AnnotationStyle(color: .blue, width: 4)
                style.textAlignment = alignment
                let text = AnnotationElement(tool: .text, rect: CGRect(x: 1000, y: 700, width: 900, height: 420),
                                             style: style, centersTextVertically: true)
                let frame = AnnotationTextPlacement.editorFrame(for: text,
                    preferredSize: CGSize(width: 100 / scale, height: 80 / scale), bounds: bounds, viewScale: scale)
                expect(frame.width > 400 && frame.height > 200 && frame.contains(text.rect),
                       "large text expands past old editor limits at every zoom/alignment")
                expect((frame.width - text.rect.width) * scale >= 3.99
                       && (frame.height - text.rect.height) * scale >= 19.99,
                       "growing editor retains physical caret padding")
                expect(frame.midY == text.rect.midY, "growth preserves label vertical anchor")
                switch alignment {
                case .left: expect(frame.minX == text.rect.minX, "growth preserves left anchor")
                case .center: expect(frame.midX == text.rect.midX, "growth preserves center anchor")
                case .right: expect(frame.maxX == text.rect.maxX, "growth preserves right anchor")
                }
            }
        }
        let overflow = AnnotationElement(tool: .text, rect: CGRect(x: 2900, y: 1900, width: 600, height: 400))
        let frame = AnnotationTextPlacement.editorFrame(for: overflow, bounds: bounds)
        expect(frame.contains(overflow.rect) && frame.origin == overflow.rect.origin,
               "canvas edges do not squeeze text into a scrolling box or move its anchor")
    }

    private static func testTextPlacement(_ expect: (Bool, String) -> Void) {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 240)
        let shape = AnnotationElement(tool: .rect, rect: CGRect(x: 40, y: 40, width: 120, height: 80))
        expect(AnnotationTextPlacement.target(at: CGPoint(x: 42, y: 80), elements: [shape], scale: 1,
            imageSize: bounds.size) == .create(CGPoint(x: 100, y: 80), centered: true), "double click centers text on shape")
        expect(AnnotationTextPlacement.target(at: CGPoint(x: 280, y: 200), elements: [shape], scale: 1,
            imageSize: bounds.size) == .create(CGPoint(x: 280, y: 200), centered: false), "empty double click uses pointer")
        var locked = shape
        locked.isLocked = true
        expect(AnnotationTextPlacement.target(at: CGPoint(x: 100, y: 80), elements: [locked], scale: 1,
            imageSize: bounds.size) == .locked, "double click respects locked shapes")
        var style = AnnotationStyle(color: .blue, width: 4)
        style.textAlignment = .center
        var text = AnnotationElement(tool: .text, rect: CGRect(x: 100, y: 80, width: 0, height: 0),
                                     style: style, centersTextVertically: true)
        for value in ["", "Label", "A longer\nmultiline label"] {
            text.text = value
            text.rect = AnnotationRenderer.textBounds(text, scale: 1)
            expect(text.rect.midX == 100 && text.rect.midY == 80, "centered text preserves anchor as text grows")
        }
        let frame = AnnotationTextPlacement.editorFrame(for: text, preferredSize: CGSize(width: 400, height: 200),
                                                        bounds: bounds)
        expect(frame.midX == 100 && frame.midY == 80 && bounds.contains(frame), "native editor stays centered near edges")
        expect(AnnotationTextPlacement.target(at: CGPoint(x: 42, y: 80), elements: [shape, text], scale: 1,
            imageSize: bounds.size) == .text(text.id), "double click on shape reopens its center label")
        var duplicated = AnnotationDocument.Snapshot(elements: [text], selection: [text.id])
        AnnotationSelection.apply(.duplicate, to: &duplicated)
        expect(duplicated.elements.last?.centersTextVertically == true, "duplicating a label preserves its vertical anchor")
        for alignment in AnnotationStyle.Alignment.allCases {
            var aligned = text
            aligned.centersTextVertically = false
            aligned.style?.textAlignment = alignment
            let before = aligned.rect
            aligned.text += "\nAdditional line"
            aligned.rect = AnnotationRenderer.textBounds(aligned, scale: 1)
            expect(aligned.rect.minY == before.minY, "paragraph alignment does not move ordinary text vertically")
            switch alignment {
            case .left: expect(aligned.rect.minX == before.minX, "left alignment preserves leading anchor")
            case .center: expect(aligned.rect.midX == before.midX, "center alignment preserves horizontal center")
            case .right: expect(aligned.rect.maxX == before.maxX, "right alignment preserves trailing anchor")
            }
        }
        for tool in ScreenshotSupport.Tool.allCases {
            expect(AnnotationElement(tool: tool).selectsAfterCreation == [.rect, .ellipse, .arrow, .line].contains(tool),
                   "auto-select affects geometric drawing tools only: \(tool)")
        }
    }

    private static func testToolbarExpansion(_ expect: (Bool, String) -> Void) {
        for visible in [CGRect(x: 0, y: 24, width: 1280, height: 760),
                        CGRect(x: -1920, y: -900, width: 1920, height: 1056),
                        CGRect(x: 500, y: 1400, width: 900, height: 520)] {
            let collapsed = AnnotationDisplayGeometry.toolbarFrame(size: CGSize(width: 442, height: 207),
                                                                  visibleFrame: visible)
            for height: CGFloat in [280, 460, 800] {
                let lateResize = CGRect(x: collapsed.minX, y: collapsed.maxY - height, width: 442, height: height)
                let fitted = AnnotationDisplayGeometry.clampedToolbarFrame(lateResize, visibleFrame: visible)
                expect(visible.contains(fitted), "late toolbar expansion stays on owning screen")
                expect(AnnotationDisplayGeometry.clampedToolbarFrame(fitted, visibleFrame: visible) == fitted,
                       "resize clamp is idempotent")
            }
        }
    }

    private static func testColorPalette(_ expect: (Bool, String) -> Void) {
        expect(AnnotationColorPalette.colors.count == 15, "palette has three rows of five colors")
        for source in ["abc", "#AbC", "AABBCC", "  #aabbcc\n"] {
            expect(AnnotationColorPalette.parse(source).map(AnnotationColorPalette.hex) == "AABBCC", "RGB hex input")
        }
        expect(AnnotationColorPalette.parse("#1234").map(AnnotationColorPalette.hex) == "11223344", "short RGBA")
        expect(AnnotationColorPalette.parse("12345678").map(AnnotationColorPalette.hex) == "12345678", "RGBA input")
        expect(AnnotationColorPalette.parse("ABCDEF", alpha: 0.4)?.alpha == 0.4, "RGB preserves alpha")
        for text in ["", "#", "12", "12345", "1234567", "123456789", "0x123456", "GGGGGG", "##ffffff", "ab cd ef"] {
            expect(AnnotationColorPalette.parse(text) == nil, "invalid hex is rejected: \(text)")
        }
        expect(AnnotationColorPalette.parse("FFFFFF00", allowsAlpha: false) == nil, "redaction rejects transparent hex")
        expect(AnnotationColorPalette.parse("FFFFFF", allowsAlpha: false) == .white, "redaction accepts opaque hex")
        expect(AnnotationColorPalette.hex(AnnotationColor(red: .nan, green: 2, blue: -1)) == "00FF00", "hex clamps channels")
        for color in AnnotationColorPalette.colors where color.alpha > 0 {
            let shades = AnnotationColorPalette.shades(of: color)
            expect(shades.count == 5 && Set(shades.map(AnnotationColorPalette.hex)).count == 5, "five distinct shades")
            expect(shades.allSatisfy { $0 == $0.clamped() && $0.alpha == color.alpha }, "shades preserve alpha")
        }
        for language in AppLanguage.allCases {
            expect(AnnotationPickerStrings.labels(language).count == 9, "picker localization for \(language)")
        }
        expect(!AnnotationToolShortcuts.primaryEntries.contains { $0.choice.tool == .redact }, "no main redact icon")
        expect(AnnotationToolShortcuts.primaryEntries.count == 10, "ten main tools plus custom-shape button")
    }

    private static func testPathSampling(_ expect: (Bool, String) -> Void) {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addQuadCurve(to: CGPoint(x: 16, y: 0), control: CGPoint(x: 8, y: 16))
        path.move(to: CGPoint(x: 20, y: 0))
        path.addCurve(to: CGPoint(x: 36, y: 0), control1: CGPoint(x: 20, y: 16), control2: CGPoint(x: 36, y: 16))
        path.closeSubpath()
        let lines = AnnotationPathSampling.polylines(path)
        expect(lines.count == 2 && lines[0].count == 17 && lines[1].count == 18, "sixteen samples and subpaths preserved")
        guard lines.count == 2, lines[0].count == 17, lines[1].count == 18 else { return }
        expect(lines[0][8] == CGPoint(x: 8, y: 8), "quadratic midpoint")
        expect(lines[1][8] == CGPoint(x: 28, y: 12), "cubic midpoint")
        expect(lines[0].last == CGPoint(x: 16, y: 0) && lines[1][16] == CGPoint(x: 36, y: 0), "exact curve endpoints")
        expect(lines[1].first == lines[1].last, "closed curve segment preserved")
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
        let sharpDiamond = AnnotationGeometry.path(diamond)
        style.roundness = 1
        diamond.style = style
        let roundedDiamond = AnnotationGeometry.path(diamond)
        expect(roundedDiamond != sharpDiamond && roundedDiamond.boundingBoxOfPath.minY > diamond.rect.minY,
               "diamond roundness changes its actual rendered and hit-test geometry")
        let roundedBinding = AnnotationBindings.nearest(to: CGPoint(x: diamond.rect.midX, y: diamond.rect.minY),
                                                        in: [diamond], tolerance: 14)
        expect((roundedBinding?.anchor.y ?? 0) > 0, "bindings follow the rounded diamond perimeter rather than its clipped corner")
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
        let midpoint = CGPoint(x: 90, y: 80)
        expect(AnnotationEditGesture.owner(at: midpoint, in: [element], selection: [], scale: 1,
                                          imageSize: CGSize(width: 200, height: 200)) == nil,
               "direct point editing requires selection")
        let inserted = AnnotationLinear.insertingPoint(in: element, segment: 0)
        expect(inserted.points.count == 3 && AnnotationLinear.removingPoint(in: element, index: 1) == element,
               "direct insertion works while removing an endpoint is rejected")
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
                if tool == .line {
                    expect(!clicks.release(at: .zero, constrained: false, viewScale: scale), "line click starts at every zoom")
                    let end = CGPoint(x: 100, y: 90)
                    clicks.beginPointer(at: end, constrained: true, viewScale: scale)
                    expect(clicks.release(at: end, constrained: true, viewScale: scale)
                           && clicks.completed?.points == [.zero, AnnotationLinear.constrained(end, from: .zero)],
                           "line second click completes the constrained straight segment")
                    var returned = AnnotationLinearConstruction(element: element, at: .zero, viewScale: scale)
                    returned.updatePreview(at: CGPoint(x: 5 / scale, y: 0), constrained: false, viewScale: scale)
                    expect(returned.release(at: .zero, constrained: false, viewScale: scale) && returned.completed == nil,
                           "zero-length line drag ends without creating a path")
                    continue
                }
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
        expect(AnnotationLinear.creationStyle(for: .arrow, base: base).endHead == .arrow
               && AnnotationElement(tool: .arrow).resolvedStyle.endHead == .legacy,
               "new arrows use open heads without restyling existing legacy screenshot arrows")
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
        axes.axisNegative = true
        let negative = AnnotationDiagramGeometry.path(in: bounds, style: axes)
        let axesPixels = bitmap { context in
            AnnotationRenderer.draw(AnnotationElement(tool: .rect, rect: bounds, style: axes.sanitized()),
                                    in: context, scale: 1, shadowsEnabled: false)
        }
        expect(axesPixels?.dropFirst((50 * 200 + 65) * 4).prefix(4).allSatisfy { $0 == 0 } == true,
               "negative axes leave quadrant interiors transparent in the actual renderer")
        expect(negative.boundingBoxOfPath == bounds,
               "negative axes extend across all four quadrants of the shape")
        expect(AnnotationStyle(color: .red, width: 3).bindEndpoints,
               "nearby endpoint binding is enabled without an opt-in checkbox")
        for action in AnnotationSelectionAction.allCases {
            expect(NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil) != nil,
                   "\(action) selection command has a supported icon")
        }
        for language in AppLanguage.allCases {
            expect(AnnotationDiagramStrings.labels(language).count == 8, "diagram controls localized for \(language)")
        }
    }

    private static func testToolShortcuts(_ expect: (Bool, String) -> Void) {
        expect(GlobalShortcut.screenAnnotationDefault.storageValue == "control:19",
               "screen annotation defaults to Control-2")
        expect(!ScreenAnnotationSupport.activationClosesOverlay(hasOverlay: false, isDrawing: false),
               "Control-2 opens drawing when no overlay exists")
        expect(ScreenAnnotationSupport.activationClosesOverlay(hasOverlay: true, isDrawing: true),
               "Control-2 closes an overlay that is already drawing")
        expect(!ScreenAnnotationSupport.activationClosesOverlay(hasOverlay: true, isDrawing: false),
               "Control-2 resumes drawing after Escape enters Interact without discarding annotations")
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
            hasApplicationModifier: false) == .tool(.highlighter), "9 selects the highlighter")
        expect(AnnotationToolShortcuts.hint(for: .tool(.highlighter)) == "9",
               "highlighter displays its numeric shortcut and retains H as an alias")
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
            AnnotationStyle.Character.allCases.map { .character($0) },
            AnnotationStyle.Pressure.allCases.map { .pressure($0) },
            [.edges(rounded: false), .edges(rounded: true)],
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
        let rect = CGRect(x: 40, y: 40, width: 400, height: 260)
        var sketch = AnnotationElement(tool: .rect, rect: rect,
            style: AnnotationStyle(color: .red, width: 3, character: .cartoonist))
        var accentCount = 0
        for seed: UInt64 in 0..<8 {
            sketch.roughSeed = seed
            let outline = AnnotationGeometry.path(sketch)
            AnnotationPathCache.shared.removeAll()
            expect(outline == AnnotationGeometry.path(sketch), "sketched shape remains deterministic")
            expect(outline.contains(CGPoint(x: rect.midX, y: rect.midY)), "sketched contours retain fill and interior hit geometry")
            expect(rect.insetBy(dx: -16, dy: -16).contains(outline.boundingBoxOfPath), "corner overdraw stays bounded")
            let contours = AnnotationPathSampling.polylines(outline)
            expect(contours.filter { $0.count > 3 && $0.first == $0.last }.count == 2, "sketch retains two closed outlines")
            accentCount += contours.filter { $0.first != $0.last }.count
            var current = CGPoint.zero
            var largestBend: CGFloat = 0
            outline.applyWithBlock { pointer in
                let item = pointer.pointee
                switch item.type {
                case .moveToPoint: current = item.points[0]
                case .addCurveToPoint:
                    largestBend = max(largestBend,
                        ScreenshotSupport.distance(from: item.points[0], toSegment: current, item.points[2]),
                        ScreenshotSupport.distance(from: item.points[1], toSegment: current, item.points[2]))
                    current = item.points[2]
                case .addLineToPoint: current = item.points[0]
                default: break
                }
            }
            expect(largestBend <= 2.5, "sketched rectangle edges avoid exaggerated lens-shaped bows")
        }
        expect(accentCount > 0, "seeded sketch samples include small corner overshoots")
        var twice = sketch
        twice.rect = CGRect(x: rect.minX * 2, y: rect.minY * 2, width: rect.width * 2, height: rect.height * 2)
        var doubledTransform = CGAffineTransform(scaleX: 2, y: 2)
        expect(AnnotationGeometry.path(sketch).copy(using: &doubledTransform) == AnnotationGeometry.path(twice, scale: 2),
               "closed-shape roughness preserves Retina scaling")
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
            var final = candidate
            final.element.rect.origin.x += 30
            final.rotation += 0.2
            expect(stability.commitCandidate(final: final) == final, "acceptance returns final geometry without unused preview interpolation")
            stability.update(nil)
            stability.update(nil)
            stability.update(nil)
            expect(stability.commitCandidate(final: candidate) == nil, "missing observations still release stability")
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
        expect(AnnotationStyle.Character.selectable == [.architect, .cartoonist],
               "roughness picker offers only clean and rough")
        var retired = style
        retired.character = .artist
        retired.pressure = .hardware
        do {
            let data = try JSONEncoder().encode(["pen": retired])
            let original = try JSONDecoder().decode([String: AnnotationStyle].self, from: data)
            expect(original["pen"]?.character == .artist, "legacy roughness remains decodable without restyling elements")
            expect(original["pen"]?.pressure == .hardware, "legacy tablet pressure remains decodable")
            for key in [DefaultsKey.screenAnnotationStyles, DefaultsKey.screenshotAnnotationStyles] {
                defaults.set(String(decoding: data, as: UTF8.self), forKey: key)
                let migrated = AnnotationStylePreferences.load(defaults: defaults, key: key)["pen"]
                expect(migrated == style, "retired roughness defaults migrate to clean and preserve other fields")
                AnnotationStylePreferences.save(["pen": retired], defaults: defaults, key: key)
                expect(AnnotationStylePreferences.load(defaults: defaults, key: key)["pen"] == style,
                       "saved tool defaults cannot reintroduce the retired option")
            }
        } catch {
            expect(false, "roughness migration fixture: \(error)")
        }
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
        let keys = AnnotationToolShortcuts.entries.flatMap(\.keys)
        expect(Set(keys).count == keys.count, "production tool shortcuts are unambiguous")
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
