// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum AnnotationTextStrings {
    static func labels(_ language: AppLanguage) -> [String] {
        switch language {
        case .enUS: return ["Font", "System", "Serif", "Monospace", "Handwriting", "Size", "Bold", "Alignment", "Left", "Center", "Right"]
        case .ptBR: return ["Fonte", "Sistema", "Serifada", "Monoespaçada", "Manuscrita", "Tamanho", "Negrito", "Alinhamento", "Esquerda", "Centro", "Direita"]
        case .tr: return ["Yazı tipi", "Sistem", "Serif", "Eş aralıklı", "El yazısı", "Boyut", "Kalın", "Hizalama", "Sol", "Orta", "Sağ"]
        case .ru: return ["Шрифт", "Системный", "С засечками", "Моноширинный", "Рукописный", "Размер", "Жирный", "Выравнивание", "Слева", "По центру", "Справа"]
        case .es: return ["Fuente", "Sistema", "Serifa", "Monoespaciada", "Manuscrita", "Tamaño", "Negrita", "Alineación", "Izquierda", "Centro", "Derecha"]
        case .de: return ["Schrift", "System", "Serifen", "Monospace", "Handschrift", "Größe", "Fett", "Ausrichtung", "Links", "Mitte", "Rechts"]
        case .fr: return ["Police", "Système", "Sérif", "Chasse fixe", "Manuscrite", "Taille", "Gras", "Alignement", "Gauche", "Centre", "Droite"]
        case .it: return ["Carattere", "Sistema", "Serif", "Monospazio", "Manoscritto", "Dimensione", "Grassetto", "Allineamento", "Sinistra", "Centro", "Destra"]
        case .ja: return ["フォント", "システム", "セリフ", "等幅", "手書き", "サイズ", "太字", "配置", "左", "中央", "右"]
        case .ko: return ["글꼴", "시스템", "세리프", "고정폭", "손글씨", "크기", "굵게", "정렬", "왼쪽", "가운데", "오른쪽"]
        case .zhHans: return ["字体", "系统", "衬线", "等宽", "手写", "大小", "粗体", "对齐", "左", "居中", "右"]
        case .zhTW, .zhHK: return ["字體", "系統", "襯線", "等寬", "手寫", "大小", "粗體", "對齊", "左", "置中", "右"]
        }
    }
}
