// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum AnnotationInputStrings {
    static func labels(_ language: AppLanguage) -> [String] {
        switch language {
        case .enUS: return ["Pressure", "Constant", "Tablet", "Simulated", "Smoothing"]
        case .ptBR: return ["Pressão", "Constante", "Mesa digitalizadora", "Simulada", "Suavização"]
        case .tr: return ["Basınç", "Sabit", "Tablet", "Simüle", "Yumuşatma"]
        case .ru: return ["Нажим", "Постоянный", "Планшет", "Имитация", "Сглаживание"]
        case .es: return ["Presión", "Constante", "Tableta", "Simulada", "Suavizado"]
        case .de: return ["Druck", "Konstant", "Grafiktablett", "Simuliert", "Glättung"]
        case .fr: return ["Pression", "Constante", "Tablette", "Simulée", "Lissage"]
        case .it: return ["Pressione", "Costante", "Tavoletta", "Simulata", "Levigatura"]
        case .ja: return ["筆圧", "一定", "タブレット", "シミュレーション", "平滑化"]
        case .ko: return ["필압", "일정", "태블릿", "시뮬레이션", "매끄럽게"]
        case .zhHans: return ["压力", "恒定", "数位板", "模拟", "平滑"]
        case .zhTW, .zhHK: return ["壓力", "固定", "繪圖板", "模擬", "平滑"]
        }
    }
}
