// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AnnotationColorPalette {
    static let colors: [AnnotationColor] = [
        AnnotationColor(red: 0, green: 0, blue: 0, alpha: 0),
        rgb(0x17191C), rgb(0x495057), rgb(0xFFFFFF), rgb(0x846358),
        rgb(0x0891A2), rgb(0x2874C6), rgb(0x7950B8), rgb(0xAE4FAD), rgb(0xDC4964),
        rgb(0x34914B), rgb(0x079B80), rgb(0xD3AC22), rgb(0xEA8A19), rgb(0xDC4A38)
    ]

    private static func rgb(_ value: UInt32) -> AnnotationColor {
        AnnotationColor(red: Double((value >> 16) & 255) / 255,
                        green: Double((value >> 8) & 255) / 255,
                        blue: Double(value & 255) / 255)
    }

    static func hex(_ color: AnnotationColor) -> String {
        let color = color.clamped()
        let rgb = String(format: "%02X%02X%02X", Int((color.red * 255).rounded()),
                         Int((color.green * 255).rounded()), Int((color.blue * 255).rounded()))
        return color.alpha == 1 ? rgb : rgb + String(format: "%02X", Int((color.alpha * 255).rounded()))
    }

    static func parse(_ text: String, alpha: Double = 1, allowsAlpha: Bool = true) -> AnnotationColor? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard [3, 4, 6, 8].contains(text.count),
              text.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        else { return nil }
        if text.count < 5 { text = text.map { "\($0)\($0)" }.joined() }
        guard let value = UInt32(text, radix: 16) else { return nil }
        var result = rgb(text.count == 8 ? value >> 8 : value)
        result.alpha = text.count == 8 ? Double(value & 255) / 255 : alpha
        guard allowsAlpha || result.alpha == 1 else { return nil }
        return result.clamped()
    }

    static func shades(of color: AnnotationColor) -> [AnnotationColor] {
        let color = color.clamped()
        let maximum = max(color.red, color.green, color.blue)
        let minimum = min(color.red, color.green, color.blue)
        let amounts: [Double] = maximum < 0.15 ? [0, 0.2, 0.4, 0.6, 0.8]
            : minimum > 0.85 ? [-0.8, -0.6, -0.4, -0.2, 0] : [-0.65, -0.32, 0, 0.28, 0.55]
        return amounts.map { amount in
            func mix(_ component: Double) -> Double {
                amount < 0 ? component * (1 + amount) : component + (1 - component) * amount
            }
            return AnnotationColor(red: mix(color.red), green: mix(color.green), blue: mix(color.blue),
                                   alpha: color.alpha)
        }
    }
}
