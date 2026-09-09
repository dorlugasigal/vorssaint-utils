// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum AnnotationUIMetrics {
    static let toolbarWidth: CGFloat = 648
    static let toolSide: CGFloat = 44
    static let tileSide: CGFloat = 36
    static let iconSize: CGFloat = 20
    static let chromeHeight: CGFloat = 220
}

struct AnnotationInspectorSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct AnnotationInspectorViewport<Content: View>: NSViewRepresentable {
    var maximumHeight: CGFloat
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> Viewport {
        Viewport(rootView: content())
    }

    func updateNSView(_ view: Viewport, context: Context) {
        view.host.rootView = content()
        view.invalidateIntrinsicContentSize()
        view.needsLayout = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Viewport, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? AnnotationUIMetrics.toolbarWidth - 24)
        let natural = nsView.host.sizeThatFits(in: CGSize(width: width, height: 100_000))
        let height = min(ceil(natural.height), maximumHeight)
        return CGSize(width: width, height: height)
    }

    final class Viewport: NSScrollView {
        let host: NSHostingController<Content>
        override var mouseDownCanMoveWindow: Bool { window?.isMovableByWindowBackground == true }

        init(rootView: Content) {
            host = NSHostingController(rootView: rootView)
            super.init(frame: .zero)
            drawsBackground = false
            borderType = .noBorder
            hasVerticalScroller = true
            autohidesScrollers = true
            host.sizingOptions = []
            documentView = host.view
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            let width = max(1, contentSize.width)
            let measured = host.sizeThatFits(in: CGSize(width: width, height: 100_000))
            let size = CGSize(width: width, height: ceil(measured.height))
            if host.view.frame.size != size { host.view.setFrameSize(size) }
        }

    }
}
