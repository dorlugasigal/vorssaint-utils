// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI
import Vision

/// Everything the annotation editor can do to one capture: the mutable
/// document (image, annotations, undo history) and the export paths. The
/// SwiftUI editor view observes this model; geometry is in image pixels.
final class ScreenshotEditorModel: ObservableObject, BackdropEditing {
    @Published private(set) var baseImage: CGImage
    @Published var annotations: [ScreenshotSupport.Annotation] = []
    @Published var selectedIDs: Set<UUID> = []
    var selectedID: UUID? {
        get { annotations.first(where: { selectedIDs.contains($0.id) })?.id }
        set { selectedIDs = AnnotationSelection.expandingGroups(Set(newValue.map { [$0] } ?? []), in: annotations) }
    }
    @Published var editingTextID: UUID?
    @Published var tool: ScreenshotSupport.Tool {
        didSet {
            if tool != oldValue, linearConstruction != nil { cancelLinearConstruction() }
            UserDefaults.standard.set(tool.rawValue, forKey: DefaultsKey.screenshotLastTool)
            if tool != .select { clearTextSelection() }
            if tool != oldValue, tool != .select {
                selectedID = nil
                editingTextID = nil
            }
            if tool == .crop, oldValue != .crop {
                selectedID = nil
                cropDraft = CGRect(origin: .zero, size: imageSize)
            } else if oldValue == .crop {
                cropDraft = nil
                cropLoupePoint = nil
            }
        }
    }
    /// Words recognized in the capture and selectable with the select tool.
    @Published private(set) var textWords: [ScreenshotSupport.RecognizedWord] = []
    @Published private(set) var selectedWordIndexes: [Int] = []
    private var textSelectionAnchor: CGPoint?
    /// A QR code found in the capture, offered as a copy or open action.
    @Published private(set) var qrReading: BarcodeDetector.Reading?
    @Published var color: ScreenshotSupport.ColorID {
        didSet {
            UserDefaults.standard.set(color.rawValue, forKey: DefaultsKey.screenshotLastColor)
            applyStyleToSelection()
        }
    }
    @Published var stroke: ScreenshotSupport.StrokeID {
        didSet {
            UserDefaults.standard.set(stroke.rawValue, forKey: DefaultsKey.screenshotLastStroke)
            applyStyleToSelection()
        }
    }
    @Published var sticker: ScreenshotSupport.StickerID {
        didSet {
            UserDefaults.standard.set(sticker.rawValue,
                                      forKey: DefaultsKey.screenshotLastSticker)
            applyStickerToSelection()
        }
    }
    @Published var annotationShadowsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(annotationShadowsEnabled,
                                      forKey: DefaultsKey.screenshotAnnotationShadows)
            refreshDirtyState()
        }
    }
    /// The full backdrop configuration (kind, colors or image, margin and
    /// corner sliders), persisted as JSON and applied live on the canvas.
    @Published var backdropStyle: ScreenshotSupport.BackdropStyle {
        didSet {
            UserDefaults.standard.set(backdropStyle.encoded(),
                                      forKey: DefaultsKey.screenshotBackdropStyle)
            reloadBackdropImageIfNeeded()
            refreshDirtyState()
        }
    }
    /// Custom backdrops the user chose to keep.
    @Published private(set) var backdropPresets: [ScreenshotSupport.BackdropStyle] {
        didSet {
            UserDefaults.standard.set(
                ScreenshotSupport.encodedBackdropPresets(backdropPresets),
                forKey: DefaultsKey.screenshotBackdropPresets)
        }
    }
    /// Loaded image for an image-kind backdrop; nil when missing on disk,
    /// which quietly renders as no backdrop.
    @Published private(set) var backdropImage: CGImage?
    @Published var cropDraft: CGRect?
    /// Exact image pixel under a crop resize grip. Nil while moving the
    /// whole crop so the loupe appears only when it adds precision.
    @Published private(set) var cropLoupePoint: CGPoint?
    /// Continuous zoom (view points per image pixel); nil fits the window.
    @Published var zoomOverride: CGFloat?
    /// What the view actually laid out last, so pinch and scroll zoom start
    /// from the visible scale even in fit mode. Plain var on purpose: the
    /// view writes it during layout.
    var currentDisplayZoom: CGFloat = 0.5
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    /// True while there is work that never left the app: closing then asks.
    @Published private(set) var isDirty = false

    let scale: CGFloat
    private(set) var pixelated: CGImage?

    private struct Snapshot: Equatable {
        let image: CGImage
        let annotations: [ScreenshotSupport.Annotation]
        let selection: Set<UUID>
        static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
            lhs.image === rhs.image && lhs.annotations == rhs.annotations
        }
    }
    private var history = AnnotationHistory<Snapshot>()
    private var snapshot: Snapshot { Snapshot(image: baseImage, annotations: annotations, selection: selectedIDs) }
    private var cleanImage: CGImage?
    private var cleanAnnotations: [ScreenshotSupport.Annotation] = []
    private var cleanBackdropStyle = ScreenshotSupport.BackdropStyle()
    private var cleanAnnotationShadowsEnabled = false

    // Gesture state, in image pixels.
    private var dragStart: CGPoint = .zero
    private var draftID: UUID?
    private var annotationGesture: AnnotationEditGesture?
    private var groupGestures: [AnnotationEditGesture] = []
    @Published private(set) var selectionMarquee: CGRect?
    private var additiveSelection = false
    private var marqueeSelection: Set<UUID> = []
    private var linearConstruction: AnnotationLinearConstruction?
    private var strokeSampler = AnnotationInputSampler()
    private let smartDraw = AnnotationSmartDraw()
    private var strokeStartTime: TimeInterval = 0
    @Published var smartDrawEnabled = false {
        didSet {
            UserDefaults.standard.set(smartDrawEnabled, forKey: DefaultsKey.screenshotSmartDraw)
            if !smartDrawEnabled { smartDraw.cancel() }
        }
    }
    var hasLinearConstruction: Bool { linearConstruction != nil }
    private var activeHandle: ScreenshotSupport.Handle?
    private var cropResizeOrigin: CGRect?
    private var cropMoveOrigin: CGRect?
    private var cropSelectionOrigin: CGRect?
    private var dragRegistered = false
    private var editingSelectedAnnotation = false
    private var newTextID: UUID?
    private var annotationStyleDefaults: AnnotationStyle?
    private var freehandStyleDefaults: AnnotationStyle?

    var creationStyle: AnnotationStyle {
        if tool == .freehand, let freehandStyleDefaults { return freehandStyleDefaults }
        return annotationStyleDefaults ?? AnnotationElement(tool: tool, color: color, stroke: stroke).resolvedStyle
    }

    var shapeGhost: AnnotationElement? {
        annotations.first { AnnotationInteractionFeedback.isShapeGhost($0, draftID: draftID) }
    }

    var inspectorStyle: AnnotationStyle {
        annotations.first(where: { $0.id == selectedID })?.resolvedStyle
            ?? creationStyle
    }
    var inspectorTool: ScreenshotSupport.Tool {
        annotations.first(where: { $0.id == selectedID })?.tool ?? tool
    }

    func selectShape(_ shape: AnnotationStyle.Shape) {
        selectedID = nil
        tool = .rect
        var style = inspectorStyle
        style.shape = shape
        setInspectorStyle(style)
    }

    func styleEditingChanged(_ editing: Bool) {
        if editing { history.begin(snapshot) } else {
            if editingTextID == nil { history.commit(snapshot) }
            refreshUndoFlags()
            refreshDirtyState()
        }
    }

    func setInspectorStyle(_ value: AnnotationStyle) {
        let style = value.sanitized()
        if selectedID != nil {
            let indexes = annotations.indices.filter {
                selectedIDs.contains(annotations[$0].id) && !annotations[$0].isLocked
                    && annotations[$0].resolvedStyle != style
            }
            guard !indexes.isEmpty else { return }
            registerUndo()
            for index in indexes {
                annotations[index].style = style
                if !style.bindEndpoints { annotations[index].startBinding = nil; annotations[index].endBinding = nil }
                if annotations[index].tool == .text {
                    annotations[index].rect = AnnotationRenderer.textBounds(annotations[index], scale: scale)
                }
            }
            AnnotationBindings.finishEdit(selectedIDs, elements: &annotations, tolerance: 14 * scale)
        } else {
            if tool == .freehand { freehandStyleDefaults = style }
            else { annotationStyleDefaults = style }
            objectWillChange.send()
        }
    }

    var imageSize: CGSize {
        CGSize(width: baseImage.width, height: baseImage.height)
    }

    /// Natural on-screen size in points (pixels over capture scale).
    var pointSize: CGSize {
        CGSize(width: CGFloat(baseImage.width) / scale, height: CGFloat(baseImage.height) / scale)
    }

    init(image: CGImage, scale: CGFloat) {
        baseImage = image
        self.scale = scale
        let defaults = UserDefaults.standard
        smartDrawEnabled = defaults.bool(forKey: DefaultsKey.screenshotSmartDraw)
        var lastTool = ScreenshotSupport.Tool(
            rawValue: defaults.string(forKey: DefaultsKey.screenshotLastTool) ?? "") ?? .arrow
        if lastTool == .select || lastTool == .crop { lastTool = .arrow }
        tool = lastTool
        color = ScreenshotSupport.ColorID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastColor))
        stroke = ScreenshotSupport.StrokeID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastStroke))
        sticker = ScreenshotSupport.StickerID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastSticker))
        annotationShadowsEnabled = defaults.bool(
            forKey: DefaultsKey.screenshotAnnotationShadows)
        let rawStyle = defaults.string(forKey: DefaultsKey.screenshotBackdropStyle) ?? ""
        backdropStyle = ScreenshotSupport.BackdropStyle.decoded(rawStyle)
        backdropPresets = ScreenshotSupport.decodedBackdropPresets(
            defaults.string(forKey: DefaultsKey.screenshotBackdropPresets))
        pixelated = nil
        reloadBackdropImageIfNeeded()
        recordCleanState()
    }

    /// Backdrop margin in image pixels for the current settings; zero while
    /// the backdrop is off. The live canvas and the exporter share this.
    var backdropPaddingPixels: CGFloat {
        showsBackdrop
            ? ScreenshotSupport.backdropPadding(for: imageSize,
                                                factor: CGFloat(backdropStyle.padding))
            : 0
    }

    /// Corner rounding of the capture card in image pixels.
    var cardCornerPixels: CGFloat {
        ScreenshotSupport.cardCornerRadius(for: imageSize,
                                           factor: CGFloat(backdropStyle.cornerRadius))
    }

    /// True when something actually paints behind the capture (an image
    /// backdrop whose file vanished counts as nothing).
    var showsBackdrop: Bool {
        if case .none = backdropFill { return false }
        return true
    }

    /// The style resolved into what the renderer paints, shared by the live
    /// canvas and the exporter.
    var backdropFill: ScreenshotRenderer.BackdropFill {
        let style = backdropStyle.sanitized()
        switch style.kind {
        case .none:
            return .none
        case .preset:
            guard let id = style.presetID,
                  let preset = ScreenshotSupport.BackdropID(rawValue: id)
            else { return .none }
            return .colors(preset.stops)
        case .solid, .gradient:
            let colors = (style.colors ?? []).map {
                (red: $0[0], green: $0[1], blue: $0[2])
            }
            return colors.isEmpty ? .none : .colors(colors)
        case .image:
            guard let backdropImage else { return .none }
            return .image(backdropImage)
        }
    }

    private func reloadBackdropImageIfNeeded() {
        guard backdropStyle.kind == .image, let path = backdropStyle.imagePath else {
            backdropImage = nil
            return
        }
        if backdropImage != nil, loadedBackdropPath == path { return }
        loadedBackdropPath = path
        backdropImage = Self.loadBackdropImage(path)
    }

    private var loadedBackdropPath: String?

    /// Loads and caps a backdrop image; wallpapers can be 6K and the fill
    /// never needs more than the export canvas.
    private static func loadBackdropImage(_ path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Backdrop presets

    /// Keeps the current custom backdrop (colors or image) in the presets
    /// row; duplicates are ignored.
    func saveCurrentBackdropAsPreset() {
        let style = backdropStyle.sanitized()
        guard style.kind != .none, style.kind != .preset else { return }
        var snapshot = style
        // A preset is the look, not this capture's sliders.
        snapshot.padding = 0.5
        snapshot.cornerRadius = 0.1
        snapshot.blur = 0
        guard !backdropPresets.contains(where: {
            var candidate = $0
            candidate.padding = 0.5
            candidate.cornerRadius = 0.1
            candidate.blur = 0
            return candidate == snapshot
        }) else { return }
        backdropPresets = Array((backdropPresets + [snapshot])
            .suffix(ScreenshotSupport.backdropPresetLimit))
    }

    func removeBackdropPreset(at index: Int) {
        guard backdropPresets.indices.contains(index) else { return }
        backdropPresets.remove(at: index)
    }

    // MARK: - Selectable text on the canvas

    var selectedText: String {
        ScreenshotSupport.joinedWords(textWords, selected: selectedWordIndexes)
    }

    func clearTextSelection() {
        textSelectionAnchor = nil
        if !selectedWordIndexes.isEmpty { selectedWordIndexes = [] }
    }

    func wordIndex(at point: CGPoint) -> Int? {
        textWords.firstIndex { $0.rect.insetBy(dx: -2 * scale, dy: -2 * scale).contains(point) }
    }

    /// Word-level recognition of the base capture, off the main thread; the
    /// boxes land in image pixels with their line index.
    func recognizeText() {
        let image = baseImage
        let width = CGFloat(image.width)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var words: [ScreenshotSupport.RecognizedWord] = []
            let maximumTilePixels = 12_000_000
            let tileHeight = min(image.height,
                                 max(512, min(4096,
                                     maximumTilePixels / max(image.width, 1))))
            var tileY = 0
            var lineOffset = 0
            while tileY < image.height {
                guard let current = self, image === current.baseImage else { return }
                let currentHeight = min(tileHeight, image.height - tileY)
                guard let tile = image.cropping(to: CGRect(x: 0,
                                                           y: tileY,
                                                           width: image.width,
                                                           height: currentHeight))
                else { break }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                let handler = VNImageRequestHandler(cgImage: tile, options: [:])
                try? handler.perform([request])
                let observations = request.results ?? []
                for (line, observation) in observations.enumerated() {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let text = candidate.string
                    var searchStart = text.startIndex
                    for raw in text.split(separator: " ") {
                        let word = String(raw)
                        guard let range = text.range(of: word,
                                                   range: searchStart..<text.endIndex),
                              let box = try? candidate.boundingBox(for: range)?.boundingBox
                        else { continue }
                        searchStart = range.upperBound
                        let rect = CGRect(x: box.minX * width,
                                          y: CGFloat(tileY)
                                            + (1 - box.maxY) * CGFloat(currentHeight),
                                          width: box.width * width,
                                          height: box.height * CGFloat(currentHeight))
                        words.append(ScreenshotSupport.RecognizedWord(
                            text: word,
                            rect: rect,
                            line: lineOffset + line))
                    }
                }
                lineOffset += observations.count
                tileY += currentHeight
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, image === self.baseImage else { return }
                self.textWords = words
            }
        }
    }

    /// Scans the capture for a QR code off the main thread; the result drives
    /// the copy or open action in the toolbar. Re-run whenever the base image
    /// changes (crop, undo) so a cropped out code stops being offered.
    func recognizeQRCodes() {
        let image = baseImage
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let current = self, image === current.baseImage else { return }
            let reading = BarcodeDetector.read(image)
            DispatchQueue.main.async { [weak self] in
                guard let self, image === self.baseImage else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.qrReading = reading
                }
            }
        }
    }

    // MARK: - Zoom

    static let zoomRange: ClosedRange<CGFloat> = 0.05...3

    /// Multiplies the current zoom (pinch, ⌃ scroll, ⌘ plus and minus).
    func adjustZoom(by factor: CGFloat) {
        let current = zoomOverride ?? currentDisplayZoom
        zoomOverride = min(max(current * factor, Self.zoomRange.lowerBound),
                           Self.zoomRange.upperBound)
    }

    /// Absolute zoom for pinch gestures anchored at the gesture's start.
    func setZoom(_ zoom: CGFloat) {
        zoomOverride = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    // MARK: - Undo

    private func registerUndo() {
        history.checkpoint(snapshot)
        refreshUndoFlags()
        isDirty = true
    }

    func undo() {
        smartDraw.cancel()
        if linearConstruction != nil { cancelLinearConstruction(); return }
        guard let last = history.undo(snapshot) else { return }
        restore(last)
    }

    func redo() {
        smartDraw.cancel()
        if linearConstruction != nil { cancelLinearConstruction(); return }
        guard let next = history.redo(snapshot) else { return }
        restore(next)
    }

    private func restore(_ state: Snapshot) {
        if state.image !== baseImage {
            baseImage = state.image
            pixelated = nil
            clearTextSelection()
            recognizeText()
            recognizeQRCodes()
        }
        annotations = state.annotations
        if annotations.contains(where: { $0.tool == .pixelate }) {
            ensurePixelated()
        } else {
            pixelated = nil
        }
        selectedIDs = state.selection.intersection(Set(annotations.map(\.id)))
        editingTextID = nil
        newTextID = nil
        cropDraft = nil
        refreshUndoFlags()
        refreshDirtyState()
    }

    private func refreshUndoFlags() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    func markExported() {
        recordCleanState()
    }

    private func recordCleanState() {
        cleanImage = baseImage
        cleanAnnotations = annotations
        cleanBackdropStyle = backdropStyle.sanitized()
        cleanAnnotationShadowsEnabled = annotationShadowsEnabled
        isDirty = false
    }

    private func refreshDirtyState() {
        guard let cleanImage else { return }
        isDirty = baseImage !== cleanImage
            || annotations != cleanAnnotations
            || backdropStyle.sanitized() != cleanBackdropStyle
            || annotationShadowsEnabled != cleanAnnotationShadowsEnabled
    }

    // MARK: - Selection styling

    /// Applies color or thickness changes to the selected annotation.
    private func applyStyleToSelection() {
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID && !$0.isLocked })
        else { return }
        guard annotations[index].color != color || annotations[index].stroke != stroke else { return }
        registerUndo()
        annotations[index].color = color
        annotations[index].stroke = stroke
        if var style = annotations[index].style {
            let rgb = color.components
            style.color = AnnotationColor(red: rgb.red, green: rgb.green, blue: rgb.blue)
            style.width = stroke.width
            annotations[index].style = style
        }
        if annotations[index].tool == .text {
            annotations[index].rect = ScreenshotRenderer.textBounds(
                annotations[index].text,
                at: annotations[index].rect.origin,
                stroke: stroke,
                scale: scale)
        }
    }

    private func applyStickerToSelection() {
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID }),
              annotations[index].tool == .sticker, !annotations[index].isLocked,
              annotations[index].text != sticker.rawValue
        else { return }
        registerUndo()
        annotations[index].text = sticker.rawValue
    }

    // MARK: - Gestures (image-pixel coordinates)

    func beginDrag(at point: CGPoint, extendingSelection: Bool = false) {
        smartDraw.cancel()
        strokeStartTime = ProcessInfo.processInfo.systemUptime
        if var construction = linearConstruction {
            construction.add(point)
            linearConstruction = construction
            previewLinear(at: point)
            return
        }
        history.begin(snapshot)
        dragStart = point
        dragRegistered = false
        editingSelectedAnnotation = false
        additiveSelection = extendingSelection
        if tool == .select, extendingSelection, let hit = hitTest(point) {
            let ids = AnnotationSelection.expandingGroups([hit], in: annotations)
            selectedIDs = ids.isSubset(of: selectedIDs) ? selectedIDs.subtracting(ids) : selectedIDs.union(ids)
            return
        }
        if tool != .select, tool != .crop, selectedAnnotationOwns(point) {
            editingSelectedAnnotation = true
            beginSelectDrag(at: point)
            return
        }
        if tool != .select && tool != .crop { selectedID = nil }
        switch tool {
        case .select:
            beginSelectDrag(at: point)
        case .crop:
            let bounds = CGRect(origin: .zero, size: imageSize)
            if let draft = cropDraft,
               let handle = ScreenshotSupport.handle(at: point, rect: draft,
                                                     tolerance: 14 * scale) {
                activeHandle = handle
                cropResizeOrigin = draft
                cropLoupePoint = handle.position(in: draft)
            } else if let draft = cropDraft,
                      ScreenshotSupport.startsNewCropSelection(
                        at: point, draft: draft, within: bounds) {
                cropSelectionOrigin = draft
            } else if let draft = cropDraft, draft.contains(point) {
                cropMoveOrigin = draft
            }
        case .arrow, .line:
            registerUndo()
            dragRegistered = true
            let annotation = ScreenshotSupport.Annotation(
                tool: tool, points: [point, point], color: color, stroke: stroke, style: annotationStyleDefaults)
            annotations.append(annotation)
            draftID = annotation.id
            if inspectorStyle.multiClick {
                linearConstruction = AnnotationLinearConstruction(element: annotation, at: point)
            }
        case .freehand:
            registerUndo()
            dragRegistered = true
            var annotation = ScreenshotSupport.Annotation(
                tool: tool, color: color, stroke: stroke, style: freehandStyleDefaults ?? annotationStyleDefaults)
            strokeSampler = AnnotationInputSampler()
            annotation.appendFreehand(strokeSampler.sample(point, timestamp: NSApp?.currentEvent?.timestamp ?? 0,
                hardwarePressure: nil, mode: annotation.resolvedStyle.pressure))
            annotations.append(annotation)
            draftID = annotation.id
        case .rect, .ellipse, .highlight, .pixelate, .redact:
            if tool == .pixelate { ensurePixelated() }
            registerUndo()
            dragRegistered = true
            let annotation = ScreenshotSupport.Annotation(
                tool: tool, rect: CGRect(origin: point, size: .zero),
                color: color, stroke: stroke, style: annotationStyleDefaults)
            annotations.append(annotation)
            draftID = annotation.id
        case .text, .sticker, .counter:
            break
        }
    }

    private func beginSelectDrag(at point: CGPoint) {
        if let selectedID,
           let selected = annotations.first(where: { $0.id == selectedID }) {
            let tolerance = 12 * scale
            if selectedIDs.count == 1,
               let handle = AnnotationEditGesture.handle(for: selected, at: point, tolerance: tolerance) {
                annotationGesture = AnnotationEditGesture(original: selected, anchor: point, handle: handle)
                return
            }
        }
        if let hit = hitTest(point), !selectedIDs.contains(hit) { selectedID = hit }
        else if hitTest(point) == nil { selectedID = nil }
        if let selectedID, let hit = annotations.first(where: { $0.id == selectedID }) {
            if hit.tool == .sticker {
                self.selectedID = nil
                sticker = ScreenshotSupport.StickerID.sanitized(hit.text)
                self.selectedID = selectedID
            }
            annotationGesture = AnnotationEditGesture(original: hit, anchor: point, handle: .move)
            groupGestures = annotations.filter { selectedIDs.contains($0.id) }
                .map { AnnotationEditGesture(original: $0, anchor: point, handle: .move) }
            clearTextSelection()
        } else if let word = wordIndex(at: point) {
            // A drag over recognized text selects intersecting words.
            textSelectionAnchor = point
            selectedWordIndexes = [word]
        } else {
            marqueeSelection = additiveSelection ? selectedIDs : []
            selectionMarquee = CGRect(origin: point, size: .zero)
        }
    }

    func continueDrag(to point: CGPoint, final: Bool = false) {
        defer { AnnotationBindings.resolve(&annotations) }
        let point = NSEvent.modifierFlags.contains(.shift) && (tool == .arrow || tool == .line)
            && !editingSelectedAnnotation ? AnnotationLinear.constrained(point, from: dragStart) : point
        if linearConstruction != nil { previewLinear(at: point); return }
        if editingSelectedAnnotation {
            continueSelectDrag(to: point)
            return
        }
        switch tool {
        case .select:
            continueSelectDrag(to: point)
        case .crop:
            let bounds = CGRect(origin: .zero, size: imageSize)
            if let handle = activeHandle, let origin = cropResizeOrigin {
                let rect = ScreenshotSupport.resizedRect(origin, dragging: handle, to: point)
                let snapped = ScreenshotSupport.pixelSnappedCropRect(rect, within: bounds)
                cropDraft = snapped
                cropLoupePoint = handle.position(in: snapped)
            } else if cropSelectionOrigin != nil {
                cropDraft = ScreenshotSupport.pixelSnappedCropRect(
                    ScreenshotSupport.selectionRect(from: dragStart, to: point),
                    within: bounds)
            } else if let origin = cropMoveOrigin {
                let delta = CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y)
                cropDraft = ScreenshotSupport.pixelSnappedCropRect(
                    ScreenshotSupport.movedRect(origin, by: delta, within: bounds),
                    within: bounds)
            }
        case .arrow, .line:
            updateDraft { $0.points = [dragStart, point] }
        case .freehand:
            let event = NSApp?.currentEvent
            let hardware = event?.subtype == .tabletPoint ? event.map { CGFloat($0.pressure) } : nil
            let mode = annotations.first(where: { $0.id == draftID })?.resolvedStyle.pressure ?? .constant
            let samples = strokeSampler.sample(point, timestamp: event?.timestamp ?? ProcessInfo.processInfo.systemUptime,
                hardwarePressure: hardware, mode: mode, final: final)
            updateDraft { $0.appendFreehand(samples) }
            if smartDrawEnabled, let element = annotations.first(where: { $0.id == draftID }),
               !element.resolvedStyle.isHighlighter {
                let now = ProcessInfo.processInfo.systemUptime
                smartDraw.preview(element, timestamp: now, duration: now - strokeStartTime, scale: 1 / scale)
            }
        case .rect, .ellipse, .highlight, .pixelate, .redact:
            updateDraft { $0.rect = ScreenshotSupport.selectionRect(from: dragStart, to: point) }
        case .text, .sticker, .counter:
            break
        }
    }

    private func continueSelectDrag(to point: CGPoint) {
        if selectionMarquee != nil {
            let rect = ScreenshotSupport.selectionRect(from: dragStart, to: point)
            selectionMarquee = rect
            selectedIDs = marqueeSelection.union(AnnotationSelection.marquee(rect, elements: annotations))
            return
        }
        if let anchor = textSelectionAnchor {
            selectedWordIndexes = ScreenshotSupport.wordSelection(
                anchor: anchor, current: point, boxes: textWords.map(\.rect))
            return
        }
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID })
        else { return }
        if !dragRegistered {
            registerUndo()
            dragRegistered = true
        }
        if !groupGestures.isEmpty {
            for gesture in groupGestures {
                if let index = annotations.firstIndex(where: { $0.id == gesture.original.id }) {
                    annotations[index] = gesture.updated(to: point)
                }
            }
        } else if let annotationGesture { annotations[index] = annotationGesture.updated(to: point) }
    }

    /// `isTap` is decided by the view in screen points, so a click stays a
    /// click at any zoom level; deciding it here in image pixels made taps
    /// on zoomed-out Retina captures read as drags (the text tool bug).
    func endDrag(at point: CGPoint, isTap: Bool) {
        if linearConstruction != nil {
            linearConstruction?.add(point)
            previewLinear(at: point)
            return
        }
        defer {
            AnnotationBindings.finishEdit(selectedIDs.union(Set(draftID.map { [$0] } ?? [])),
                                          elements: &annotations, tolerance: 14 * scale)
            if editingTextID == nil { history.commit(snapshot) }
            recognizeCompletedStroke()
            refreshUndoFlags()
            refreshDirtyState()
            annotationGesture = nil
            groupGestures.removeAll()
            selectionMarquee = nil
            additiveSelection = false
            draftID = nil
            activeHandle = nil
            cropResizeOrigin = nil
            cropMoveOrigin = nil
            cropSelectionOrigin = nil
            cropLoupePoint = nil
            dragRegistered = false
            editingSelectedAnnotation = false
        }
        if !isTap { continueDrag(to: point, final: true) }
        if editingSelectedAnnotation {
            finishSelectDrag(at: point, isTap: isTap)
            return
        }
        switch tool {
        case .text:
            guard isTap else { return }
            if selectExistingAnnotation(at: point) { return }
            registerUndo()
            var annotation = ScreenshotSupport.Annotation(
                tool: .text, color: color, stroke: stroke, style: annotationStyleDefaults)
            annotation.rect = ScreenshotRenderer.textBounds("", at: point, stroke: stroke, scale: scale)
            annotations.append(annotation)
            newTextID = annotation.id
            selectedID = annotation.id
            editingTextID = annotation.id
        case .sticker:
            guard isTap else { return }
            if selectExistingAnnotation(at: point) { return }
            registerUndo()
            let bounds = CGRect(origin: .zero, size: imageSize)
            let side = ScreenshotSupport.stickerSide(for: imageSize, scale: scale)
            let annotation = ScreenshotSupport.Annotation(
                tool: .sticker,
                rect: ScreenshotSupport.stickerRect(centeredAt: point,
                                                     side: side,
                                                     within: bounds),
                text: sticker.rawValue,
                color: color,
                stroke: stroke)
            annotations.append(annotation)
            selectedID = annotation.id
        case .counter:
            guard isTap else { return }
            if selectExistingAnnotation(at: point) { return }
            registerUndo()
            let annotation = ScreenshotSupport.Annotation(
                tool: .counter,
                rect: CGRect(x: point.x, y: point.y, width: 0, height: 0),
                color: color, stroke: stroke, number: 1)
            annotations.append(annotation)
            annotations = ScreenshotSupport.renumberingCounters(annotations)
            selectedID = annotation.id
        case .arrow, .line, .rect, .ellipse, .highlight, .pixelate, .redact, .freehand:
            if isTap {
                // A tap never leaves a degenerate shape behind; treat it as
                // picking whatever is under the cursor instead.
                annotations.removeAll { $0.id == draftID }
                refreshUndoFlags()
                refreshDirtyState()
                _ = selectExistingAnnotation(at: point)
            } else if let draftID {
                selectedID = draftID
            }
        case .select:
            finishSelectDrag(at: point, isTap: isTap)
        case .crop:
            if isTap, let origin = cropSelectionOrigin {
                cropDraft = origin
            }
        }
    }

    /// The visible selection remains directly editable after creation. A new
    /// tool or a gesture outside it ends that priority and creates normally.
    func selectedAnnotationOwns(_ point: CGPoint) -> Bool {
        guard let selectedID,
              let selected = annotations.first(where: { $0.id == selectedID })
        else { return false }
        let tolerance = 12 * scale
        if AnnotationEditGesture.handle(for: selected, at: point, tolerance: tolerance) != nil { return true }
        if selected.tool.resizesWithHandles,
           ScreenshotSupport.handle(at: point, rect: selected.rect,
                                    tolerance: tolerance) != nil {
            return true
        }
        if selected.points.prefix(2).contains(where: {
            hypot(point.x - $0.x, point.y - $0.y) < tolerance
        }) {
            return true
        }
        return hitTest(point) == selectedID
    }

    private func finishSelectDrag(at point: CGPoint, isTap: Bool) {
        textSelectionAnchor = nil
        if additiveSelection { return }
        guard isTap, !dragRegistered else { return }
        selectedID = hitTest(point)
        if let selectedID,
           let hit = annotations.first(where: { $0.id == selectedID }),
           hit.tool == .text {
            editingTextID = selectedID
        } else if selectedID == nil, let word = wordIndex(at: point) {
            selectedWordIndexes = [word]
        } else if selectedID == nil {
            clearTextSelection()
        }
    }

    /// A click on an existing mark always means "edit this", even while a
    /// creation tool is active. Real drags still create with the active tool.
    /// Sticker selection updates the style picker without mutating the mark;
    /// text enters its inline editor immediately.
    @discardableResult
    private func selectExistingAnnotation(at point: CGPoint) -> Bool {
        guard let hitID = hitTest(point, includeShapeInteriors: false),
              let hit = annotations.first(where: { $0.id == hitID })
        else {
            selectedID = nil
            return false
        }
        if hit.tool == .sticker {
            selectedID = nil
            sticker = ScreenshotSupport.StickerID.sanitized(hit.text)
        }
        selectedID = hitID
        editingTextID = hit.tool == .text ? hitID : nil
        clearTextSelection()
        tool = .select
        return true
    }

    private func recognizeCompletedStroke() {
        guard smartDrawEnabled, let completed = annotations.first(where: { $0.id == draftID && $0.tool == .freehand }),
              !completed.resolvedStyle.isHighlighter else { return }
        smartDraw.finish(completed, duration: ProcessInfo.processInfo.systemUptime - strokeStartTime, scale: 1 / scale) { [weak self] converted in
            guard let self, let index = self.annotations.firstIndex(where: {
                $0.id == completed.id && $0.geometryRevision == completed.geometryRevision
            }) else { return }
            self.annotations[index] = converted
            self.refreshDirtyState()
        }
    }

    func previewLinear(at point: CGPoint) {
        guard var construction = linearConstruction,
              let index = annotations.firstIndex(where: { $0.id == construction.element.id }) else { return }
        construction.preview = point
        linearConstruction = construction
        annotations[index] = construction.displayed
    }

    func finishLinearConstruction() {
        guard let construction = linearConstruction else { return }
        guard let element = construction.completed,
              let index = annotations.firstIndex(where: { $0.id == element.id }) else {
            cancelLinearConstruction()
            return
        }
        annotations[index] = element
        selectedID = element.id
        AnnotationBindings.finishEdit([element.id], elements: &annotations, tolerance: 14 * scale)
        linearConstruction = nil
        draftID = nil
        history.commit(snapshot)
        refreshUndoFlags()
        refreshDirtyState()
    }

    func cancelLinearConstruction() {
        if let original = history.cancel() { restore(original) }
        linearConstruction = nil
        draftID = nil
    }

    func editLinearPoints(_ insert: Bool) {
        var updated = annotations
        for index in updated.indices where selectedIDs.contains(updated[index].id) {
            AnnotationLinear.editPoints(insert, in: &updated[index])
        }
        guard updated != annotations else { return }
        registerUndo()
        annotations = updated
    }

    private func updateDraft(_ mutate: (inout ScreenshotSupport.Annotation) -> Void) {
        guard let draftID,
              let index = annotations.firstIndex(where: { $0.id == draftID })
        else { return }
        mutate(&annotations[index])
    }

    /// `includeShapeInteriors: false` is the creation-tap variant: area
    /// shapes (boxes, ellipses, highlights, censors) only answer near their
    /// edge, so their inside stays free for placing a new text, sticker or
    /// counter — the tap that used to create one there must keep doing so.
    func hitTest(_ point: CGPoint, includeShapeInteriors: Bool = true) -> UUID? {
        annotations.last {
            AnnotationGeometry.hit($0, at: point, scale: scale, imageSize: imageSize,
                                   includeShapeInteriors: includeShapeInteriors)
        }?.id
    }

    // MARK: - Edits

    func deleteSelected() {
        performSelectionAction(.delete)
        editingTextID = nil
        if !annotations.contains(where: { $0.id == newTextID }) { newTextID = nil }
    }

    func performSelectionAction(_ action: AnnotationSelectionAction) {
        var state = AnnotationDocument.Snapshot(elements: annotations, selection: selectedIDs)
        AnnotationSelection.apply(action, to: &state)
        if annotations != state.elements { registerUndo() }
        annotations = state.elements
        selectedIDs = state.selection
        refreshDirtyState()
    }

    /// Moves the selected annotation one step through the drawing order, so a
    /// box drawn last can sit behind text written first. Counters are numbered
    /// by their place in the array, so moving one past another renumbers both,
    /// the same way deleting one already does.
    func moveSelected(_ move: ScreenshotSupport.LayerMove) {
        performSelectionAction(move == .forward ? .forward : .backward)
    }

    func commitText(_ id: UUID, text: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id && !$0.isLocked }) else { return }
        history.begin(snapshot)
        editingTextID = nil
        if text.isEmpty {
            annotations.remove(at: index)
            if selectedID == id { selectedID = nil }
        } else {
            annotations[index].text = text
            annotations[index].rect = AnnotationRenderer.textBounds(annotations[index], scale: scale)
        }
        newTextID = nil
        history.commit(snapshot)
        refreshUndoFlags()
        refreshDirtyState()
    }

    func cancelTextEditing() {
        if let original = history.cancel() { restore(original) }
        editingTextID = nil
        newTextID = nil
    }

    func applyCrop() {
        guard let draft = cropDraft else {
            tool = .select
            return
        }
        let cropRect = ScreenshotSupport.pixelSnappedCropRect(
            draft,
            within: CGRect(origin: .zero, size: imageSize))
        guard cropRect.width >= 8, cropRect.height >= 8,
              let cropped = baseImage.cropping(to: cropRect)
        else {
            tool = .select
            return
        }
        registerUndo()
        baseImage = cropped
        pixelated = nil
        clearTextSelection()
        textWords = textWords.compactMap { word in
            let moved = word.rect.offsetBy(dx: -cropRect.minX, dy: -cropRect.minY)
            guard moved.intersects(CGRect(origin: .zero, size: CGSize(width: cropped.width,
                                                                      height: cropped.height)))
            else { return nil }
            return ScreenshotSupport.RecognizedWord(text: word.text, rect: moved, line: word.line)
        }
        annotations = annotations.map { annotation in
            var moved = annotation
            moved.rect = annotation.rect.offsetBy(dx: -cropRect.minX, dy: -cropRect.minY)
            moved.points = annotation.points.map {
                CGPoint(x: $0.x - cropRect.minX, y: $0.y - cropRect.minY)
            }
            return moved
        }
        if annotations.contains(where: { $0.tool == .pixelate }) {
            ensurePixelated()
        }
        cropDraft = nil
        selectedID = nil
        tool = .select
        recognizeText()
        recognizeQRCodes()
    }

    // MARK: - Output

    func exportImage(withBackdrop: Bool = true) -> CGImage? {
        if annotations.contains(where: { $0.tool == .pixelate }) {
            ensurePixelated()
        }
        let downscale = UserDefaults.standard.bool(forKey: DefaultsKey.screenshotDownscale)
        return ScreenshotRenderer.renderExport(
            baseImage: baseImage,
            annotations: AnnotationInteractionFeedback.committed(annotations, draftID: draftID),
            pixelated: pixelated,
            scale: scale,
            annotationShadowsEnabled: annotationShadowsEnabled,
            style: backdropStyle.sanitized(),
            fill: withBackdrop ? backdropFill : .none,
            downscaleTo1x: downscale)
    }

    private func ensurePixelated() {
        guard pixelated == nil else { return }
        pixelated = ScreenshotRenderer.pixelatedImage(from: baseImage)
    }
}

// MARK: - Window controller

/// Hosts one editor window per capture and owns everything with a side
/// effect: clipboard, files, pins, text recognition and the close-confirm.
final class ScreenshotEditorController: NSObject, NSWindowDelegate {
    let model: ScreenshotEditorModel
    private var window: NSWindow?
    var windowNumber: Int? { window?.windowNumber }
    private var keyMonitor: Any?
    private var scrollMonitor: Any?

    var protectedWindowIDs: Set<CGWindowID> {
        guard let window, window.isVisible, window.windowNumber > 0 else { return [] }
        return [CGWindowID(window.windowNumber)]
    }
    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(L10n.shared.language)
    }

    init(capture: ScreenshotSelectionController.Capture) {
        model = ScreenshotEditorModel(image: capture.image, scale: capture.scale)
        super.init()
    }

    func show() {
        let screen = NSScreen.pointerVisibleFrame
        let minimumSize = ScreenshotSupport.editorMinimumContentSize(visibleSize: screen.size)
        // The hosting view rewrites the window's size limits on its first
        // layout pass, so a contentMinSize set on the window is silently
        // lost. Declare the minimum on the hosted view and track just that:
        // the hosting controller then maintains contentMinSize itself.
        let content = ScreenshotEditorView(model: model, controller: self)
            .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: host)
        // One continuous surface: the canvas fills the window and the
        // controls float over it, so the editor reads as a single object.
        window.title = strings.editorTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Keep the editor dark so canvas contrast and popovers stay consistent.
        window.appearance = NSAppearance(named: .darkAqua)
        // Content drags edit annotations. Only the title strip moves the window.
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

        // Chrome must equal the view's designed margins exactly (rail 64 +
        // sides, action band above, style band below), so a fresh window
        // opens with zero leftover stage around the capture.
        let contentSize = ScreenshotSupport.editorContentSize(
            imagePointSize: model.pointSize,
            visibleSize: screen.size)
        window.setContentSize(contentSize)
        window.center()

        self.window = window
        installKeyMonitor()
        model.recognizeText()
        model.recognizeQRCodes()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    /// Closes without the discard confirmation used by the titlebar button.
    func discardAndClose() {
        window?.close()
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window,
                  ScreenshotSupport.editorOwnsKeyEvent(
                    eventWindowNumber: event.windowNumber,
                    editorWindowNumber: window.windowNumber,
                    editorIsKey: window.isKeyWindow)
            else { return event }
            // While a text field edits, every key belongs to it.
            if window.firstResponder is NSText || self.model.editingTextID != nil {
                return event
            }
            return self.handleKey(event) ? nil : event
        }
        // Control-scroll adjusts canvas zoom.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window,
                  ScreenshotSupport.editorOwnsKeyEvent(
                    eventWindowNumber: event.windowNumber,
                    editorWindowNumber: window.windowNumber,
                    editorIsKey: window.isKeyWindow),
                  event.modifierFlags.contains(.control)
            else { return event }
            let delta = event.scrollingDeltaY
            guard delta != 0 else { return nil }
            let clamped = max(-24, min(24, delta))
            self.model.adjustZoom(by: 1 + clamped * 0.014)
            return nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = Int(event.keyCode)

        if flags.contains(.command) {
            switch key {
            case kVK_ANSI_C:
                // Text selected on the canvas copies as text and keeps the
                // editor open; otherwise the capture leaves as an image.
                if !model.selectedWordIndexes.isEmpty {
                    copySelectedText()
                } else {
                    copyToClipboard()
                }
                return true
            case kVK_ANSI_S:
                if flags.contains(.shift) { saveAs() } else { save() }
                return true
            case kVK_ANSI_Z:
                if flags.contains(.shift) { model.redo() } else { model.undo() }
                return true
            case kVK_ANSI_P: pin(); return true
            case kVK_Delete, kVK_ForwardDelete:
                discardAndClose()
                return true
            case kVK_ANSI_0: model.zoomOverride = nil; return true
            case kVK_ANSI_1: model.zoomOverride = 1 / model.scale; return true
            case kVK_ANSI_Equal: model.adjustZoom(by: 1.25); return true
            case kVK_ANSI_Minus: model.adjustZoom(by: 0.8); return true
            default:
                return false
            }
        }
        guard flags.isDisjoint(with: [.command, .control, .option]) else { return false }
        if UserDefaults.standard.bool(forKey: DefaultsKey.screenshotToolShortcutsEnabled),
           case .shape(let shape)? = AnnotationToolShortcuts.resolve(
               keyCode: key, characters: event.charactersIgnoringModifiers,
               shift: flags.contains(.shift), hasApplicationModifier: false),
           shape.isDiagram {
            if !event.isARepeat { model.selectShape(shape) }
            return true
        }

        switch key {
        case kVK_Delete, kVK_ForwardDelete:
            model.deleteSelected()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if model.hasLinearConstruction {
                model.finishLinearConstruction()
                return true
            }
            if model.tool == .crop, model.cropDraft != nil {
                model.applyCrop()
            } else {
                copyToClipboard()
            }
            return true
        case kVK_Escape:
            if model.tool == .crop, model.cropDraft != nil {
                model.tool = .select
            } else if !model.selectedWordIndexes.isEmpty {
                model.clearTextSelection()
            } else if model.selectedID != nil {
                model.selectedID = nil
            } else {
                window?.performClose(nil)
            }
            return true
        default:
            guard let character = event.characters?.first,
                  let number = Int(String(character)),
                  let tool = ScreenshotSupport.Tool.shortcutTool(
                    number: number,
                    orderRaw: UserDefaults.standard.string(forKey: DefaultsKey.screenshotToolOrder),
                    enabled: UserDefaults.standard.bool(
                        forKey: DefaultsKey.screenshotToolShortcutsEnabled))
            else { return false }
            if tool == .rect { model.selectShape(.standard) } else { model.tool = tool }
            return true
        }
    }

    // MARK: Export actions

    /// Uploads the rendered editor result without copying the URL or closing
    /// the editor. The view presents the owner controls after it succeeds.
    func share(duration: ScreenshotShareDuration,
               completion: @escaping (ScreenshotShareRecord?) -> Void) {
        guard let image = model.exportImage() else {
            QuickToolHUD.show(icon: "link", message: strings.shareFailedHUD)
            completion(nil)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            let data = await Task.detached(priority: .userInitiated) {
                ScreenshotRenderer.pngData(from: image)
            }.value
            guard let data else {
                QuickToolHUD.show(icon: "link", message: self.strings.shareFailedHUD)
                completion(nil)
                return
            }
            do {
                let record = try await ScreenshotShareService.shared.createLink(
                    pngData: data, duration: duration)
                guard self.window != nil else {
                    try? await ScreenshotShareService.shared.delete(record)
                    completion(nil)
                    return
                }
                self.model.markExported()
                completion(record)
            } catch {
                QuickToolHUD.show(icon: "link", message: self.strings.shareFailedHUD)
                NSSound.beep()
                completion(nil)
            }
        }
    }

    /// Every final output closes the editor: the capture leaves the app
    /// and the window's job is done, so nothing lingers to tidy up.
    func copyToClipboard() {
        guard let image = model.exportImage() else { return }
        guard Self.copyImage(image, fileNamePrefix: strings.fileNamePrefix) else {
            NSSound.beep()
            return
        }
        model.markExported()
        QuickToolHUD.show(icon: "camera.viewfinder", message: strings.copiedHUD)
        window?.close()
    }

    @discardableResult
    static func copyImage(_ image: CGImage, fileNamePrefix: String) -> Bool {
        guard let data = ScreenshotRenderer.pngData(from: image),
              let base = FileManager.default.urls(for: .cachesDirectory,
                                                  in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier
        else { return false }
        let folder = base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Copied Screenshots", isDirectory: true)
        let name = ScreenshotSupport.fileName(prefix: fileNamePrefix, date: Date())
        guard let url = try? ScreenshotSupport.copiedFile(data: data, name: name,
                                                         directory: folder) else {
            return false
        }
        guard copyFile(url, payload: clipboardPayload(from: image, png: data)) else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        ScreenshotSupport.pruneCopiedFiles(in: folder, preserving: url)
        return true
    }

    @discardableResult
    static func copyFile(_ url: URL, payload: ClipboardPayload? = nil) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        guard item.setString(url.absoluteString, forType: .fileURL) else { return false }
        if let png = payload?.png {
            item.setData(png, forType: .png)
        }
        if let tiff = payload?.tiff {
            item.setData(tiff, forType: .tiff)
        }
        return pasteboard.writeObjects([item])
    }

    struct ClipboardPayload: Sendable {
        let png: Data?
        let tiff: Data?
    }

    static func clipboardPayload(from image: CGImage) -> ClipboardPayload {
        clipboardPayload(from: image, png: ScreenshotRenderer.pngData(from: image))
    }

    static func clipboardPayload(from image: CGImage, png: Data?) -> ClipboardPayload {
        let bitmap = NSBitmapImageRep(cgImage: image)
        return ClipboardPayload(png: png, tiff: bitmap.tiffRepresentation)
    }

    @discardableResult
    static func copyClipboardPayload(_ payload: ClipboardPayload) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let png = payload.png {
            item.setData(png, forType: .png)
        }
        if let tiff = payload.tiff {
            item.setData(tiff, forType: .tiff)
        }
        return pasteboard.writeObjects([item])
    }

    func save() {
        guard let image = model.exportImage(),
              let data = ScreenshotRenderer.pngData(from: image)
        else { return }
        let (url, consumedNumber) = ScreenshotService.saveDestination(strings: strings)
        do {
            try data.write(to: url, options: .atomic)
            model.markExported()
            QuickToolHUD.show(icon: "camera.viewfinder",
                              message: String(format: strings.savedHUDFormat,
                                              url.deletingLastPathComponent().lastPathComponent))
            window?.close()
        } catch {
            if let consumedNumber {
                ScreenshotService.rewindNumberSequence(toReuse: consumedNumber)
            }
            NSSound.beep()
        }
    }

    func saveAs() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = ScreenshotSupport.fileName(
            prefix: strings.fileNamePrefix, date: Date())
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard let image = self.model.exportImage(),
                  let data = ScreenshotRenderer.pngData(from: image)
            else { return }
            do {
                try data.write(to: url, options: .atomic)
                self.model.markExported()
                self.window?.close()
            } catch {
                NSSound.beep()
            }
        }
    }

    /// Pinning snapshots the current export and leaves the editor open.
    func pin() {
        guard let image = model.exportImage(withBackdrop: false) else { return }
        ScreenshotPinController.shared.pin(image: image, scale: model.scale)
        model.markExported()
    }

    /// Copies the words selected on the canvas as plain text.
    func copySelectedText() {
        let text = model.selectedText
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        QuickToolHUD.show(icon: "text.viewfinder", message: L10n.shared.s.ocrCopied)
    }

    /// Shows the detected code's content in the shared result panel; the
    /// editor stays open behind it so the capture can still be worked on.
    func showQRResult() {
        guard let reading = model.qrReading else { return }
        QRResultController.shared.show(reading: reading)
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = strings.discardTitle
        alert.informativeText = strings.discardMessage
        alert.addButton(withTitle: strings.discardConfirm)
        alert.addButton(withTitle: strings.cancel)
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        window?.delegate = nil
        window = nil
        ScreenshotService.shared.editorDidClose(self)
    }
}
