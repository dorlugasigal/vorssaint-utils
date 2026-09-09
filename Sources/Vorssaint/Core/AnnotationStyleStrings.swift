// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum AnnotationStyleStrings {
    static func characters(_ language: AppLanguage) -> [String] {
        switch language {
        case .enUS: return ["Stroke style", "Architect", "Artist", "Cartoonist"]
        case .ptBR: return ["Estilo do traço", "Arquiteto", "Artista", "Cartunista"]
        case .tr: return ["Çizgi stili", "Mimar", "Sanatçı", "Karikatürist"]
        case .ru: return ["Стиль штриха", "Архитектор", "Художник", "Мультипликатор"]
        case .es: return ["Estilo de trazo", "Arquitecto", "Artista", "Dibujante"]
        case .de: return ["Zeichenstil", "Architekt", "Künstler", "Cartoonist"]
        case .fr: return ["Style du trait", "Architecte", "Artiste", "Dessinateur"]
        case .it: return ["Stile del tratto", "Architetto", "Artista", "Fumettista"]
        case .ja: return ["線のスタイル", "建築家", "画家", "漫画家"]
        case .ko: return ["획 스타일", "건축가", "예술가", "만화가"]
        case .zhHans: return ["笔画风格", "建筑师", "艺术家", "漫画家"]
        case .zhTW, .zhHK: return ["筆畫風格", "建築師", "藝術家", "漫畫家"]
        }
    }

    static func pattern(_ language: AppLanguage) -> String { labels(language)[0] }
    static func patternName(_ pattern: AnnotationStyle.Pattern, _ language: AppLanguage) -> String {
        labels(language)[1 + pattern.rawValue]
    }
    static func fill(_ language: AppLanguage) -> String { labels(language)[4] }
    static func fillName(_ fill: AnnotationStyle.Fill, _ language: AppLanguage) -> String {
        labels(language)[5 + fill.rawValue]
    }
    static func diamond(_ language: AppLanguage) -> String { labels(language)[9] }
    static func roundness(_ language: AppLanguage) -> String { labels(language)[10] }

    static func labels(_ language: AppLanguage) -> [String] {
        switch language {
        case .enUS:
            return ["Pattern", "Solid", "Dashed", "Dotted", "Fill", "None", "Solid", "Hatch", "Crosshatch", "Diamond", "Roundness"]
        case .ptBR:
            return ["Padrão", "Contínuo", "Tracejado", "Pontilhado", "Preenchimento", "Nenhum", "Sólido", "Hachura", "Hachura cruzada", "Losango", "Arredondamento"]
        case .tr:
            return ["Desen", "Düz", "Kesikli", "Noktalı", "Dolgu", "Yok", "Düz", "Tarama", "Çapraz tarama", "Eşkenar dörtgen", "Yuvarlaklık"]
        case .ru:
            return ["Стиль линии", "Сплошная", "Штриховая", "Пунктирная", "Заливка", "Нет", "Сплошная", "Штриховка", "Перекрёстная штриховка", "Ромб", "Скругление"]
        case .es:
            return ["Patrón", "Continua", "Discontinua", "Punteada", "Relleno", "Ninguno", "Sólido", "Rayado", "Rayado cruzado", "Rombo", "Redondez"]
        case .de:
            return ["Muster", "Durchgezogen", "Gestrichelt", "Gepunktet", "Füllung", "Keine", "Einfarbig", "Schraffur", "Kreuzschraffur", "Raute", "Rundung"]
        case .fr:
            return ["Motif", "Continu", "Tirets", "Pointillés", "Remplissage", "Aucun", "Uni", "Hachures", "Hachures croisées", "Losange", "Arrondi"]
        case .it:
            return ["Motivo", "Continua", "Tratteggiata", "Punteggiata", "Riempimento", "Nessuno", "Pieno", "Tratteggio", "Tratteggio incrociato", "Rombo", "Arrotondamento"]
        case .ja:
            return ["線種", "実線", "破線", "点線", "塗りつぶし", "なし", "単色", "斜線", "交差線", "ひし形", "角の丸み"]
        case .ko:
            return ["선 패턴", "실선", "파선", "점선", "채우기", "없음", "단색", "빗금", "교차 빗금", "마름모", "모서리 둥글기"]
        case .zhHans:
            return ["线型", "实线", "虚线", "点线", "填充", "无", "纯色", "斜线", "交叉线", "菱形", "圆角"]
        case .zhTW, .zhHK:
            return ["線型", "實線", "虛線", "點線", "填滿", "無", "純色", "斜線", "交叉線", "菱形", "圓角"]
        }
    }
}
