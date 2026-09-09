// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct AnnotationColorSwatch: View {
    var color: AnnotationColor
    var selected = false

    var body: some View {
        Canvas { context, size in
            for row in 0..<Int(ceil(size.height / 6)) {
                for column in 0..<Int(ceil(size.width / 6)) {
                    context.fill(Path(CGRect(x: column * 6, y: row * 6, width: 6, height: 6)),
                                 with: .color((row + column).isMultiple(of: 2) ? .white : .gray))
                }
            }
        }
        .overlay(Color(red: color.red, green: color.green, blue: color.blue).opacity(color.alpha))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
        .padding(3)
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.primary : .clear, lineWidth: 2))
        .accessibilityHidden(true)
    }
}

final class AnnotationPaletteState: ObservableObject {
    @Published var color: AnnotationColor
    init(color: AnnotationColor) { self.color = color }
}

struct AnnotationColorPaletteView: View {
    @ObservedObject var state: AnnotationPaletteState
    var title: String
    var allowsAlpha: Bool
    var suggestedColors: [AnnotationColor]
    var select: (AnnotationColor) -> Void
    var sample: () -> Void
    var done: () -> Void
    @ObservedObject private var localization = L10n.shared
    @State private var family: AnnotationColor
    @State private var hex: String
    @State private var invalidHex = false

    init(state: AnnotationPaletteState, title: String, allowsAlpha: Bool,
         suggestedColors: [AnnotationColor] = AnnotationColorPalette.colors,
         select: @escaping (AnnotationColor) -> Void, sample: @escaping () -> Void, done: @escaping () -> Void) {
        self.state = state
        self.title = title
        self.allowsAlpha = allowsAlpha
        self.suggestedColors = suggestedColors
        self.select = select
        self.sample = sample
        self.done = done
        _family = State(initialValue: state.color)
        _hex = State(initialValue: AnnotationColorPalette.hex(state.color))
    }

    private func text(_ field: AnnotationPickerStrings.Field) -> String {
        AnnotationPickerStrings.text(field, localization.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            Text(text(.colors)).font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: 5), spacing: 8) {
                ForEach(Array(suggestedColors.enumerated()), id: \.offset) { _, color in
                    if allowsAlpha || color.alpha == 1 {
                        swatch(color) { family = color; choose(color) }
                    }
                }
            }
            Text(text(.shades)).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(AnnotationColorPalette.shades(of: family).enumerated()), id: \.offset) { _, shade in
                    swatch(shade) { choose(shade) }
                }
            }
            Text(text(.hex)).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text("#").foregroundStyle(.secondary)
                TextField(allowsAlpha ? "RRGGBB / RRGGBBAA" : "RRGGBB", text: $hex)
                    .font(.body.monospaced()).textFieldStyle(.plain)
                    .accessibilityLabel(text(.hex))
                    .onSubmit { _ = commitHex() }
                Divider().frame(height: 20)
                Button(action: sample) { Image(systemName: "eyedropper").font(.title3) }
                    .buttonStyle(.plain).help(text(.sample)).accessibilityLabel(text(.sample))
            }
            .padding(10).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            if invalidHex {
                Text(text(.invalidHex)).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if allowsAlpha {
                HStack {
                    Text(AnnotationSessionStrings.opacity(localization.language)).font(.caption)
                    Slider(value: Binding(get: { state.color.alpha }, set: { alpha in
                        var color = state.color
                        color.alpha = alpha
                        family.alpha = alpha
                        choose(color)
                    }), in: 0...1)
                    .accessibilityLabel(AnnotationSessionStrings.opacity(localization.language))
                }
            }
            HStack {
                Spacer()
                Button(FeatureStrings.screenshot(localization.language).done) {
                    if commitHex() { done() }
                }
            }
        }
        .padding(16).frame(width: 284).background(.regularMaterial)
        .onChange(of: state.color) { _, color in hex = AnnotationColorPalette.hex(color); invalidHex = false }
    }

    private func choose(_ color: AnnotationColor) {
        invalidHex = false
        hex = AnnotationColorPalette.hex(color)
        select(color)
    }

    private func swatch(_ color: AnnotationColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AnnotationColorSwatch(color: color,
                                  selected: AnnotationColorPalette.hex(color) == AnnotationColorPalette.hex(state.color))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .help(color.alpha == 0 ? text(.transparent) : "#\(AnnotationColorPalette.hex(color))")
        .accessibilityLabel(color.alpha == 0 ? text(.transparent) : "#\(AnnotationColorPalette.hex(color))")
        .accessibilityAddTraits(color == state.color ? .isSelected : [])
    }

    private func commitHex() -> Bool {
        if hex == AnnotationColorPalette.hex(state.color) { return true }
        guard let color = AnnotationColorPalette.parse(hex, alpha: state.color.alpha, allowsAlpha: allowsAlpha) else {
            invalidHex = true
            NSSound.beep()
            return false
        }
        family = color
        choose(color)
        return true
    }
}

struct AnnotationColorControl: NSViewRepresentable {
    @Binding var color: AnnotationColor
    var editingChanged: (Bool) -> Void
    var allowsAlpha = true
    var title = ""
    var suggestedColors: [AnnotationColor] = AnnotationColorPalette.colors

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.toggle(_:)))
        button.isBordered = false
        button.imagePosition = .imageOnly
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.control = self
        button.isEnabled = context.environment.isEnabled
        let color = color.clamped()
        button.image = NSImage(size: CGSize(width: 36, height: 36), flipped: false) { bounds in
            let rect = bounds.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha).setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            let luminance = 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
            let ink: NSColor = color.alpha < 0.5 ? .labelColor : luminance > 0.5 ? .black : .white
            NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [ink]))?
                .draw(in: CGRect(x: 23, y: 7, width: 8, height: 6))
            return true
        }
        let label = title.isEmpty ? FeatureStrings.screenshot(L10n.shared.language).colorLabel : title
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue("#\(AnnotationColorPalette.hex(color))")
        button.toolTip = label
        context.coordinator.synchronize()
    }

    func makeCoordinator() -> Coordinator { Coordinator(control: self) }
    static func dismantleNSView(_ nsView: NSButton, coordinator: Coordinator) { coordinator.close(restoreFocus: false) }

    final class Coordinator: NSObject, NSPopoverDelegate {
        private static weak var active: Coordinator?
        var control: AnnotationColorControl
        private weak var owner: NSWindow?
        private var popover: NSPopover?
        private var state: AnnotationPaletteState?
        private var observers: [NSObjectProtocol] = []
        private var sampler: NSColorSampler?
        private var sessionID = UUID()

        init(control: AnnotationColorControl) { self.control = control }
        static func close(owner: NSWindow?) {
            if let active, active.owner === owner { active.close(restoreFocus: false) }
        }
        static func closeCurrent() { active?.close(restoreFocus: false) }

        func synchronize() {
            guard let state, state.color != control.color else { return }
            DispatchQueue.main.async { [weak self, weak state] in
                guard let self, Self.active === self else { return }
                state?.color = self.control.color
            }
        }

        @objc func toggle(_ button: NSButton) {
            if Self.active === self { close(); return }
            guard let owner = button.window, owner.screen != nil else { NSSound.beep(); return }
            Self.active?.close(restoreFocus: false)
            self.owner = owner
            Self.active = self
            sessionID = UUID()
            control.editingChanged(true)
            let state = AnnotationPaletteState(color: control.color)
            self.state = state
            let popover = NSPopover()
            self.popover = popover
            popover.behavior = .transient
            popover.animates = false
            popover.delegate = self
            let title = control.title.isEmpty ? FeatureStrings.screenshot(L10n.shared.language).colorLabel : control.title
            popover.contentViewController = NSHostingController(rootView: AnnotationColorPaletteView(
                state: state, title: title, allowsAlpha: control.allowsAlpha, suggestedColors: control.suggestedColors,
                select: { [weak self] in self?.select($0) },
                sample: { [weak self] in self?.sample() },
                done: { [weak self] in self?.close() }))
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: owner, queue: .main) { [weak self] _ in
                    self?.close(restoreFocus: false)
                })
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: owner, queue: .main) { [weak self] _ in
                        self?.close(restoreFocus: false)
                    })
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        }

        func popoverDidShow(_ notification: Notification) {
            guard let window = popover?.contentViewController?.view.window, let owner,
                  let screen = owner.screen else { close(); NSSound.beep(); return }
            window.level = NSWindow.Level(rawValue: owner.level.rawValue + 1)
            let origin = CGPoint(x: min(max(window.frame.minX, screen.visibleFrame.minX),
                                       max(screen.visibleFrame.minX, screen.visibleFrame.maxX - window.frame.width)),
                                 y: min(max(window.frame.minY, screen.visibleFrame.minY),
                                       max(screen.visibleFrame.minY, screen.visibleFrame.maxY - window.frame.height)))
            window.setFrameOrigin(origin)
            window.makeKey()
        }

        func popoverDidClose(_ notification: Notification) {
            if sampler == nil { close() }
        }

        private func select(_ value: AnnotationColor) {
            guard Self.active === self else { return }
            var color = value.clamped()
            if !control.allowsAlpha { color.alpha = 1 }
            state?.color = color
            control.color = color
        }

        private func sample() {
            guard sampler == nil else { return }
            let sampler = NSColorSampler()
            self.sampler = sampler
            let session = sessionID
            popover?.performClose(nil)
            sampler.show { [weak self] color in
                DispatchQueue.main.async {
                    guard let self, Self.active === self, self.sessionID == session else { return }
                    if self.owner?.isVisible == true, let color {
                        if let rgb = color.usingColorSpace(.sRGB) {
                            self.select(AnnotationColor(red: rgb.redComponent, green: rgb.greenComponent,
                                                        blue: rgb.blueComponent, alpha: self.control.color.alpha))
                        } else { NSSound.beep() }
                    }
                    self.close()
                }
            }
        }

        func close(restoreFocus: Bool = true) {
            guard Self.active === self else { return }
            Self.active = nil
            sessionID = UUID()
            let owner = owner
            self.owner = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            popover?.delegate = nil
            popover?.close()
            popover = nil
            sampler = nil
            state = nil
            control.editingChanged(false)
            if restoreFocus, owner?.isVisible == true { owner?.makeKey() }
        }
    }
}
