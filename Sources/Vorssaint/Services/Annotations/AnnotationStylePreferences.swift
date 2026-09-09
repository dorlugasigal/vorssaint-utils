// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AnnotationStylePreferences {
    static func load(defaults: UserDefaults, key: String) -> [String: AnnotationStyle] {
        guard let value = defaults.string(forKey: key) else { return [:] }
        let decoded = Result { try JSONDecoder().decode([String: AnnotationStyle].self, from: Data(value.utf8)) }
        switch decoded {
        case .success(let styles): return styles.mapValues { $0.sanitized() }
        case .failure(let error):
            NSLog("Invalid annotation style preferences for %@: %@", key, String(describing: error))
            return [:]
        }
    }

    static func save(_ styles: [String: AnnotationStyle], defaults: UserDefaults, key: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = Result { try encoder.encode(styles.mapValues { $0.sanitized() }) }
        switch encoded {
        case .success(let data): defaults.set(String(decoding: data, as: UTF8.self), forKey: key)
        case .failure(let error):
            NSLog("Unable to save annotation style preferences for %@: %@", key, String(describing: error))
        }
    }
}
