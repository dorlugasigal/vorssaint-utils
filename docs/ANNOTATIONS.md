# Shared annotations

Screen annotation extends the live overlay from PR 1518. It uses the same
annotation elements, paths, paint pass and editing operations as the screenshot
editor. It does not capture or refresh screenshots of the desktop.

## Live drawing

Invoke the overlay on the display under the pointer. That display owns the
session until Close; moving the pointer to another display does not move marks.
Removing the display, changing its frame or changing its backing scale closes
the session instead of relocating annotations.

Draw captures canvas input. Interact leaves annotations visible and passes
canvas clicks to the desktop; the toolbar remains clickable. Escape cancels
an active operation first, then enters Interact. Close clears the session and
releases its panels, observers and transient state. Sleep, lock and Space
changes release drawing input.
Starting another capture or opening a screenshot editor also yields overlay
input without discarding completed live annotations.

| Key | Live tool/action |
| --- | --- |
| Control-2 | Open Draw; close from Draw; resume Draw from Interact |
| 1 / V | Select |
| 2 / 3 / 4 | Rectangle / Diamond / Ellipse |
| 5 / A, 6 / L | Arrow / Line |
| 7 / F, 8 / T | Pen / Text |
| 9 / H, 0 / Shift-E | Freehand Highlighter / Eraser |
| D / Q / U / G / X | Database / Queue / Person / Grid / Axes |
| Control-W / Control-K | Toggle white / black board |
| Command-Z / Command-Shift-Z | Undo / Redo |
| Shift-click | Add or remove objects from selection |
| Return | Finish a multi-click path |
| Command-Return | Commit native multiline text |
| Escape | Cancel editing, then return to Interact |

Drag empty canvas with Select to select enclosed objects. Completing a rectangle,
diamond, ellipse, custom diagram shape, arrow or line switches to Select and
selects the new object immediately. Pen, highlighter and screenshot-specific
capture tools remain active for repeated use. Choose a drawing tool again to
create another shape.

Move the toolbar using its drag handle, labels or empty background. Buttons,
sliders, text fields and other interactive controls keep their normal behavior.
Preferences are always open in compact labeled rows, with no More options
disclosure or separate card per property. The toolbar retains its 648-point
width and fits its height to the active tool; short screens scroll preferences
without hiding the tool and action rows. The inspector edits selected,
unlocked objects, or the current tool's defaults when nothing is selected.
Only Stroke and Fill pickers are shown where applicable; there is no duplicate
external palette. Their native popovers contain suggested colors, shades,
RGB/RGBA hex input, opacity and an eyedropper. Each picker session is one undo
transaction. Highlighter suggestions use the neon palette. Opacity is adjusted
inside the color pickers, not in the main preferences. The shared system color panel is
not modified.

The background button cycles transparent, white and black. Transparent
is the default for each new session.
Footer hints reflect Escape's current cancel/Interact action and the user's
configured activation shortcut for Draw or Close. Disabled or failed global
shortcut registrations are not advertised.
An explicit Draw/Interact segmented control shows the current mode.

## Rich editing

The inspector exposes diamond as a Rectangle variant, solid/hatch/crosshatch
fills, dashes, sharp/rounded edge buttons, custom RGBA, opacity, widths, font families,
font size, bold text, alignment, visual pressure choices and stroke character.
Width, stroke pattern and roughness have distinct labels. The smoothing
checkbox is removed; existing stroke-processing defaults remain compatible.
Fill styles appear only after choosing a nontransparent background color.
Selecting transparent removes the fill and hides those styles. Pressure offers
Constant and Simulated; the legacy Tablet value remains readable and saved
creation defaults migrate to Constant.
The stroke-character picker offers Architect (clean) and Cartoonist (rough).
The retired middle Artist preset remains decodable for existing styles;
saved creation defaults migrate to Architect. Redact is available in the
live toolbar's custom-shape menu and remains a separate screenshot tool.
It is always opaque, including when a mixed selection receives a translucent color.

Arrowheads, arrow type and head size are inline sections in the live toolbar.
Individual head selectors omit the duplicate legacy Default entry. Click to start an
arrow, click to add vertices, and finish with Return,
Done, double-click or the last-point finish handle. Drag/release creates a
quick path. Escape/Cancel discards construction. Drag midpoint handles to
insert vertices; double-click an interior vertex to remove it.
Selected vertices and cubic controls can be dragged. An arrow element remains
Arrow when both heads are None. Both ends support the full arrowhead catalog,
including outlined/filled forms and relationship cardinality markers.
The regular Line tool creates only a straight, two-endpoint segment: drag
and release, or click its start and end. It does not expose arrowheads, curved
routes or bend insertion. Older stored line styles remain readable; new
creation and style edits enforce the plain-line settings.

Nearby endpoint binding is enabled by default for new connectors.
Endpoints near a shape attach to its stable identity and follow translations,
resizes and rotations. Deleting a target detaches its connectors without
jumping their last visible endpoints. Duplicating a target and its connectors
remaps their bindings to the copies; copying a connector alone detaches its
external bindings.

The selection menu and canvas context menu provide duplicate/delete,
group/ungroup, lock/unlock and all four layer actions. Transform/enlargement
sliders are removed; direct handles and menu actions remain. Locked objects resist
direct editing. Screenshot pixelation regions remain axis-aligned.

Text uses the same native `NSTextView` bridge in both hosts. Return inserts a
newline; Command-Return commits. Escape cancels. Whitespace is retained, and
focus moving to an inspector does not commit the text. Text and style changes
during an edit share one undo transaction.
Switching drawing tools commits the current draft instead of discarding it.
Horizontal alignment applies to all paragraphs without changing the caret
selection; shape-label vertical centering is independent of left/center/right
alignment. Ordinary text keeps its top anchor while being edited.
Double-click empty canvas to start text at the pointer, or double-click a shape
to start centered text. Double-clicking a shape with text at its center reopens
that text. Text is a separate editable element, not a bound child of the shape.
Locked objects and active path-finishing/vertex-editing gestures keep their
existing behavior; Interact does not intercept desktop double-clicks.

Freehand strokes are not capped at 600 points. Input filtering preserves the
final endpoint and bounds pressure resampling work per event. Geometry caches
do not retain copies of the input arrays, and unchanged paths and arrowheads
are reused, including hatch geometry. Each geometry cache has bounded
retention; this is not a document or stroke-size limit.

Smart Draw is on by default, while an explicitly saved opt-out is respected.
It recognizes circles, ellipses, squares,
rectangles, diamonds and arrows using the source fitting and confidence policy.
Recognition runs on a serial background queue with bounded input, cancellation
and generation checks. Unsupported or insufficiently confident strokes remain
freehand. Recognition does not add a second undo step.
Late results cannot overwrite intervening lock/group/style changes.
Recognized connectors run the same endpoint-binding finalization as manually
created connectors.

## Screenshot compatibility

The screenshot editor keeps a single slim bottom bar. Added color, stroke,
edge, arrow, text and pressure preferences use compact buttons there, with
detailed choices in popovers. They do not add panels above the capture or
stacked preference rows below it. Capture dimensions, zoom, existing actions,
and screenshot-only tools remain in their original regions.

Existing screenshot tool raw values, order, numbered shortcuts, preset colors,
stroke widths, arrow silhouette and default smoothing are retained. The
freehand tool's Highlighter option is distinct from the existing rectangular
Highlight tool. Diamond and marker variants do not reorder the tool rail.

Crop, pixelate, redact, rectangular highlight, stickers, counters, OCR
selection, backdrops, import, save/copy/pin/share and canvas navigation remain
screenshot features. Screenshot pixels and annotation edits have one bounded
history, not competing image and annotation undo stacks. Crop translates
vertices and curve controls together and restores the original image on undo.

The screen overlay does not add live blur/pixelation, capture/export commands,
recording, zoom, webcam, OCR or panorama. Vorssaint's recorder excludes its own
application windows; the overlay is not a recorder compositing feature.
Screenshot capture continues to honor its existing own-window exclusion
preference. Do not assume third-party recording includes overlay redaction.

Existing live tool/RGB/width preference keys remain supported. Additional
per-tool style defaults use separate live and screenshot keys, with finite
value sanitization. Smart Draw preferences are likewise host-specific. No
annotation documents are persisted or synchronized.

## Implementation and coverage

Paths below are relative to `Sources/Vorssaint/` unless prefixed with `Tests/`.
`Tests/AnnotationTests.swift` is explicitly wired into `build.sh --test`.
`Support/AnnotationHostSelfTest.swift` is called by the existing `--selftest`
and uses isolated preference suites without opening application windows.

| Capability | Implementation owner | Automated coverage owner |
| --- | --- | --- |
| Display/session/input ownership | `Services/ScreenAnnotation/ScreenAnnotationService.swift` | Display geometry checks in `Tests/MetricsTests.swift`; live data-host selftest |
| Shared model, rendering and export | `Services/Annotations/AnnotationElement.swift`, `AnnotationRenderer.swift`; `Services/QuickTools/ScreenshotRenderer.swift` | Default screenshot pixel equivalence at 1x/2x in `Tests/AnnotationTests.swift`; host export selftest |
| Transactions, selection and direct arrow editing | `Services/Annotations/AnnotationDocument.swift`; both host services | `testEditing`; live and screenshot data-host selftests |
| Inspector, colors and scoped preferences | `UI/Annotations/AnnotationInspector.swift`, `AnnotationColorControl.swift`, `AnnotationInspectorLayout.swift`; shared style preferences and palette | Color/preference tests; all-tool light/dark native layout review |
| Groups, locks, layers and transforms | `Services/Annotations/AnnotationSelection.swift`; `UI/Annotations/AnnotationSelectionMenu.swift`; direct canvas handles | `testSelection`; locked-object host selftests |
| Shapes, fills, dashes and roundness | Shared geometry/renderer and inspector | `testShapeStyles`; default-renderer pixel regressions |
| Curves, points, heads and construction | `Services/Annotations/AnnotationLinear.swift` | `testLinear`; screenshot control-editing and construction selftests |
| Endpoint bindings | `Services/Annotations/AnnotationBindings.swift` | `testBindings` |
| Native text and typography | `UI/Annotations/AnnotationTextEditor.swift`; `Services/Annotations/AnnotationTextPlacement.swift`; shared renderer | `testText`, `testTextPlacement`; centered text/whitespace/undo host selftests |
| Pressure, smoothing and eraser sweeps | `Services/Annotations/AnnotationFreehand.swift`, `AnnotationPathSampling.swift` | `testFreehand`; long-marker and eraser host selftests |
| Deterministic rough geometry | `Services/Annotations/AnnotationRoughness.swift` | `testRoughness`, including scale and seed checks |
| Smart Draw | `Services/Annotations/SmartDrawRecognizer.swift`, `AnnotationSmartDraw.swift` | `testSmartDraw`, `testSmartDrawResults`, including late lock/group results and binding undo/redo |
| Localization/discovery | `Core/Annotation*Strings.swift`, `Core/FeatureStrings.swift`; settings directory | All-current-language catalog coverage and existing settings tests |
| Screenshot-only workflows | Existing screenshot services and UI | Existing screenshot suite plus crop/image-history/export host selftests |

The existing commands are `./build.sh --test`, `./build.sh` and
`./build/Vorssaint --selftest`. `--selftest-annotation-ui` exercises every tool
in both light and dark appearances, custom/disabled shortcut hints and a
constrained-height viewport without opening windows. The unit suite prints comparisons against the
uncached shared geometry for long strokes and a 200-element scene, and checks
that unchanged scene paths are not rebuilt.

### Native acceptance still requiring desktop interaction

Automated geometry and data-host checks are not proof of native focus, IME or
physical display behavior. Isolated previews have been exercised, but the full
manual matrix remains outstanding. Before claiming full interactive parity, exercise:

1. Draw/Interact/Close and toolbar reentry on displays to the left, right,
   above and below the primary display, including mixed scales and negative
   origins.
2. Disconnect/resize, lock/sleep, fullscreen Spaces and feature disable with
   a drag, text editor, color picker or recognition request active.
3. Native text selection, IME composition, multiline input, keyboard routing,
   stroke/fill picker switching and focus restoration at monitor edges.
4. Hardware tablet pressure and end-to-end input latency/memory on long
   strokes and large scenes; the automated timings measure geometry work,
   not interactive latency or whole-application memory.
5. Capture/import, annotate, crop/undo, copy/save/pin/share and recorder
   coexistence under each existing window-exclusion setting.

Source attribution and the retained MIT notice are in
[ANNOTATION-PROVENANCE.md](ANNOTATION-PROVENANCE.md).
