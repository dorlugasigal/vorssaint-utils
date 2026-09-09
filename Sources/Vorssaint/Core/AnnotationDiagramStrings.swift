// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum AnnotationDiagramStrings {
    static func title(_ shape: AnnotationStyle.Shape, _ language: AppLanguage) -> String {
        switch shape {
        case .standard: return FeatureStrings.screenshot(language).toolRect
        case .diamond: return AnnotationStyleStrings.diamond(language)
        default: return labels(language)[shape.rawValue - AnnotationStyle.Shape.database.rawValue]
        }
    }

    static func labels(_ language: AppLanguage) -> [String] {
        switch language {
        case .enUS: return ["Database", "Queue", "User", "Grid", "Axes", "Rows", "Columns", "Ticks"]
        case .ptBR: return ["Banco de dados", "Fila", "Usuário", "Grade", "Eixos", "Linhas", "Colunas", "Marcas"]
        case .tr: return ["Veritabanı", "Kuyruk", "Kullanıcı", "Izgara", "Eksenler", "Satırlar", "Sütunlar", "İşaretler"]
        case .ru: return ["База данных", "Очередь", "Пользователь", "Сетка", "Оси", "Строки", "Столбцы", "Деления"]
        case .es: return ["Base de datos", "Cola", "Usuario", "Cuadrícula", "Ejes", "Filas", "Columnas", "Marcas"]
        case .de: return ["Datenbank", "Warteschlange", "Benutzer", "Raster", "Achsen", "Zeilen", "Spalten", "Teilstriche"]
        case .fr: return ["Base de données", "File", "Utilisateur", "Grille", "Axes", "Lignes", "Colonnes", "Graduations"]
        case .it: return ["Database", "Coda", "Utente", "Griglia", "Assi", "Righe", "Colonne", "Tacche"]
        case .ja: return ["データベース", "キュー", "ユーザー", "グリッド", "座標軸", "行", "列", "目盛り"]
        case .ko: return ["데이터베이스", "대기열", "사용자", "격자", "좌표축", "행", "열", "눈금"]
        case .zhHans: return ["数据库", "队列", "用户", "网格", "坐标轴", "行", "列", "刻度"]
        case .zhTW, .zhHK: return ["資料庫", "佇列", "使用者", "網格", "座標軸", "行", "列", "刻度"]
        }
    }
}
