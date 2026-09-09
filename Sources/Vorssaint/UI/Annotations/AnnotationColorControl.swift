// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

private enum AnnotationColorCheckerboard {
    static func draw(in context: CGContext, rect: CGRect) {
        for row in 0..<Int(ceil(rect.height / 6)) {
            for column in 0..<Int(ceil(rect.width / 6)) {
                context.setFillColor(CGColor(gray: (row + column).isMultiple(of: 2) ? 1 : 0.7, alpha: 1))
                context.fill(CGRect(x: rect.minX + CGFloat(column * 6), y: rect.minY + CGFloat(row * 6), width: 6, height: 6))
            }
        }
    }
}

struct AnnotationColorSwatch: View {
    var color: AnnotationColor
    var selected = false

    var body: some View {
        Canvas { context, size in
            context.withCGContext {
                AnnotationColorCheckerboard.draw(in: $0, rect: CGRect(origin: .zero, size: size))
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
    @Published var opacity: CGFloat
    init(color: AnnotationColor, opacity: CGFloat = 1) {
        self.color = color
        self.opacity = opacity
    }
}

struct AnnotationColorPaletteView: View {
    @ObservedObject var state: AnnotationPaletteState
    var title: String
    var allowsAlpha: Bool
    var isFill: Bool
    var suggestedColors: [AnnotationColor]
    var select: (AnnotationColor) -> Void
    var opacityChanged: (CGFloat) -> Void
    var sample: () -> Void
    var done: () -> Void
    @ObservedObject private var localization = L10n.shared
    @State private var family: AnnotationColor
    @State private var hex: String
    @State private var invalidHex = false

    init(state: AnnotationPaletteState, title: String, allowsAlpha: Bool, isFill: Bool = false,
         suggestedColors: [AnnotationColor] = AnnotationColorPalette.colors,
         select: @escaping (AnnotationColor) -> Void, opacityChanged: @escaping (CGFloat) -> Void,
         sample: @escaping () -> Void, done: @escaping () -> Void) {
        self.state = state
        self.title = title
        self.allowsAlpha = allowsAlpha
        self.isFill = isFill
        self.suggestedColors = suggestedColors
        self.select = select
        self.opacityChanged = opacityChanged
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
                    Slider(value: Binding(get: { state.opacity }, set: opacityChanged), in: 0...1)
                    .accessibilityLabel(AnnotationSessionStrings.opacity(localization.language))
                    Text(Double(state.opacity).formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit()).frame(width: 36)
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
        let alpha = AnnotationColorPalette.inputAlpha(for: state.color, isFill: isFill)
        guard let color = AnnotationColorPalette.parse(hex, alpha: alpha, allowsAlpha: allowsAlpha) else {
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
    @Binding var opacity: CGFloat
    var editingChanged: (Bool) -> Void
    var allowsAlpha = true
    var isFill = false
    var title = ""
    var suggestedColors: [AnnotationColor] = AnnotationColorPalette.colors
    var side: CGFloat = 36

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.toggle(_:)))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.control = self
        button.isEnabled = context.environment.isEnabled
        let color = color.clamped()
        button.image = NSImage(size: CGSize(width: side, height: side), flipped: false) { bounds in
            let rect = bounds.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            if color.alpha < 1, let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                path.addClip()
                AnnotationColorCheckerboard.draw(in: context, rect: rect)
                context.restoreGState()
            }
            NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha).setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            let luminance = 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
            let ink: NSColor = color.alpha < 0.5 || luminance > 0.5 ? .black : .white
            NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [ink]))?
                .draw(in: CGRect(x: bounds.maxX - 13, y: 5, width: 8, height: 6))
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
            guard let state, state.color != control.color || state.opacity != control.opacity else { return }
            DispatchQueue.main.async { [weak self, weak state] in
                guard let self, Self.active === self else { return }
                state?.color = self.control.color
                state?.opacity = self.control.opacity
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
            let state = AnnotationPaletteState(color: control.color, opacity: control.opacity)
            self.state = state
            let popover = NSPopover()
            self.popover = popover
            popover.behavior = .transient
            popover.animates = false
            popover.delegate = self
            let title = control.title.isEmpty ? FeatureStrings.screenshot(L10n.shared.language).colorLabel : control.title
            popover.contentViewController = NSHostingController(rootView: AnnotationColorPaletteView(
                state: state, title: title, allowsAlpha: control.allowsAlpha, isFill: control.isFill,
                suggestedColors: control.suggestedColors,
                select: { [weak self] in self?.select($0) },
                opacityChanged: { [weak self] in self?.setOpacity($0) },
                sample: { [weak self] in self?.sample() },
                done: { [weak self] in self?.close() }))
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: owner, queue: .main) { [weak self] _ in
                    self?.close(restoreFocus: false)
                })
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

        private func setOpacity(_ value: CGFloat) {
            guard Self.active === self, control.allowsAlpha else { return }
            state?.opacity = value
            control.opacity = value
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
                                                        blue: rgb.blueComponent,
                                                        alpha: AnnotationColorPalette.inputAlpha(for: self.control.color,
                                                                                                 isFill: self.control.isFill)))
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
