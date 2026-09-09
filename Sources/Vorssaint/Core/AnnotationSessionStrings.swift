// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum AnnotationSessionStrings {
    static func moreOptions(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: return "More options"
        case .ptBR: return "Mais opções"
        case .tr: return "Diğer seçenekler"
        case .ru: return "Другие параметры"
        case .es: return "Más opciones"
        case .de: return "Weitere Optionen"
        case .fr: return "Plus d’options"
        case .it: return "Altre opzioni"
        case .ja: return "その他のオプション"
        case .ko: return "추가 옵션"
        case .zhHans: return "更多选项"
        case .zhTW, .zhHK: return "更多選項"
        }
    }

    static func customShapes(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: return "Custom shapes"
        case .ptBR: return "Formas personalizadas"
        case .tr: return "Özel şekiller"
        case .ru: return "Дополнительные фигуры"
        case .es: return "Formas personalizadas"
        case .de: return "Zusätzliche Formen"
        case .fr: return "Formes personnalisées"
        case .it: return "Forme personalizzate"
        case .ja: return "カスタム図形"
        case .ko: return "사용자 지정 도형"
        case .zhHans: return "自定义形状"
        case .zhTW, .zhHK: return "自訂形狀"
        }
    }

    static func negativeAxes(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: return "Include negative axes"
        case .ptBR: return "Incluir eixos negativos"
        case .tr: return "Negatif eksenleri ekle"
        case .ru: return "Отрицательные полуоси"
        case .es: return "Incluir ejes negativos"
        case .de: return "Negative Achsen anzeigen"
        case .fr: return "Inclure les axes négatifs"
        case .it: return "Includi assi negativi"
        case .ja: return "負の座標軸を含める"
        case .ko: return "음의 좌표축 포함"
        case .zhHans: return "包含负坐标轴"
        case .zhTW, .zhHK: return "包含負座標軸"
        }
    }

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
