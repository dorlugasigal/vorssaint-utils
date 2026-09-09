// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AnnotationToolChoice: Hashable {
    case tool(AnnotationTool)
    case shape(AnnotationStyle.Shape)

    var tool: AnnotationTool {
        switch self {
        case .tool(let tool): return tool
        case .shape: return .rectangle
        }
    }
}

enum AnnotationToolShortcuts {
    enum BoardKey { case white, black }

    static func boardKey(characters: String?, controlOnly: Bool, isTyping: Bool = false) -> BoardKey? {
        guard controlOnly, !isTyping else { return nil }
        switch characters?.lowercased() {
        case "w": return .white
        case "k": return .black
        default: return nil
        }
    }

    struct Entry {
        let choice: AnnotationToolChoice
        let keys: [String]
    }

    static let entries: [Entry] = [
        Entry(choice: .tool(.select), keys: ["1", "V"]),
        Entry(choice: .shape(.standard), keys: ["2"]),
        Entry(choice: .shape(.diamond), keys: ["3"]),
        Entry(choice: .tool(.ellipse), keys: ["4"]),
        Entry(choice: .tool(.arrow), keys: ["5", "A"]),
        Entry(choice: .tool(.line), keys: ["6", "L"]),
        Entry(choice: .tool(.pen), keys: ["7", "F"]),
        Entry(choice: .tool(.text), keys: ["8", "T"]),
        Entry(choice: .tool(.highlighter), keys: ["9", "H"]),
        Entry(choice: .tool(.eraser), keys: ["0", "Shift-E"]),
        Entry(choice: .tool(.redact), keys: []),
        Entry(choice: .shape(.database), keys: ["D"]),
        Entry(choice: .shape(.queue), keys: ["Q"]),
        Entry(choice: .shape(.person), keys: ["U"]),
        Entry(choice: .shape(.grid), keys: ["G"]),
        Entry(choice: .shape(.axes), keys: ["X"])
    ]

    static func hint(for choice: AnnotationToolChoice) -> String? {
        entries.first { $0.choice == choice }?.keys.first
    }

    static var primaryEntries: [Entry] {
        entries.filter {
            if case .shape(let shape) = $0.choice { return !shape.isDiagram }
            return $0.choice.tool != .redact
        }
    }

    static func resolve(keyCode: Int, characters: String?, shift: Bool,
                        hasApplicationModifier: Bool, isTyping: Bool = false) -> AnnotationToolChoice? {
        guard !hasApplicationModifier, !isTyping else { return nil }
        let numberRow: [Int: String] = [
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0"
        ]
        let key = numberRow[keyCode] ?? characters?.uppercased()
        guard let key else { return nil }
        let normalized = key == "E" && shift ? "Shift-E" : key
        return entries.first { $0.keys.contains(normalized) }?.choice
    }
}
