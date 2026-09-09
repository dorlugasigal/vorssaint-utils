// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum AnnotationSessionStrings {
    static func mode(_ drawing: Bool, _ language: AppLanguage) -> String {
        let labels: (String, String)
        switch language {
        case .enUS: labels = ("Draw", "Interact")
        case .ptBR: labels = ("Desenhar", "Interagir")
        case .tr: labels = ("Çiz", "Etkileşim")
        case .ru: labels = ("Рисовать", "Взаимодействовать")
        case .es: labels = ("Dibujar", "Interactuar")
        case .de: labels = ("Zeichnen", "Interagieren")
        case .fr: labels = ("Dessiner", "Interagir")
        case .it: labels = ("Disegna", "Interagisci")
        case .ja: labels = ("描画", "操作")
        case .ko: labels = ("그리기", "상호 작용")
        case .zhHans: labels = ("绘制", "交互")
        case .zhTW, .zhHK: labels = ("繪製", "互動")
        }
        return drawing ? labels.0 : labels.1
    }
}
