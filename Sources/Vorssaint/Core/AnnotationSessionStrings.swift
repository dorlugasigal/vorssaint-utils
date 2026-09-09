// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum AnnotationSessionStrings {
    static func opacity(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: return "Opacity"
        case .ptBR: return "Opacidade"
        case .tr: return "Opaklık"
        case .ru: return "Непрозрачность"
        case .es: return "Opacidad"
        case .de: return "Deckkraft"
        case .fr: return "Opacité"
        case .it: return "Opacità"
        case .ja: return "不透明度"
        case .ko: return "불투명도"
        case .zhHans: return "不透明度"
        case .zhTW, .zhHK: return "不透明度"
        }
    }
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
