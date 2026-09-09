# Shared annotations

The transparent screen annotation host extends RuanMD's PR 1518 foundation.
The shared model, geometry, rendering and history are extracted from Vorssaint's
screenshot editor. Screenshot image effects and export remain in that host.

Monitor-anchored color panel placement adapts `DrawingColorPanelPlacement` from
Microsoft ZoomIt for Mac, including the local multi-monitor fixes in the
`feat/native-drawing-toolbar` source worktree. No ZoomIt assets, branding,
application shell or capture services are included.

`AnnotationLinear` adapts ZoomIt's arrowhead catalog and size metrics.
`AnnotationRoughness` adapts its seeded generator and Artist/Cartoonist profile
metrics to the shared CGContext path pass. Endpoints remain pinned, and the
default Architect style preserves Vorssaint's original screenshot geometry.
Rough geometry is intentionally native to the shared path model rather than
copying ZoomIt's zoom-dependent rendering and controller machinery.

`SmartDrawRecognizer.swift` retains the MIT-licensed fitting, outlier rejection,
confidence/stability policy and bounded recognition budget from ZoomIt.
Only its candidate model is adapted to shared Vorssaint elements. Work is
cancellable and generation-checked; unsupported strokes remain freehand.

The destination contribution is GPL-3.0-or-later. The following permission
notice applies to the attributed ZoomIt-derived portions:

MIT License

Copyright (c) 2026 Microsoft Corporation.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
