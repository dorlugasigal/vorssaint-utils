// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum AnnotationPickerStrings {
    enum Field: Int, CaseIterable {
        case colors, shades, hex, sample, stroke, heads, route, invalidHex, transparent
        case width, roughness, transform, eraserSize
    }

    static func text(_ field: Field, _ language: AppLanguage) -> String {
        field.rawValue < 9 ? labels(language)[field.rawValue] : layoutLabels(language)[field.rawValue - 9]
    }

    private static func layoutLabels(_ language: AppLanguage) -> [String] {
        switch language {
        case .enUS: return ["Width", "Roughness", "Transform", "Eraser size"]
        case .ptBR: return ["Espessura", "Irregularidade", "Transformar", "Tamanho da borracha"]
        case .tr: return ["Kalınlık", "Pürüzlülük", "Dönüştür", "Silgi boyutu"]
        case .ru: return ["Толщина", "Неровность", "Преобразование", "Размер ластика"]
        case .es: return ["Grosor", "Irregularidad", "Transformar", "Tamaño del borrador"]
        case .de: return ["Breite", "Unregelmäßigkeit", "Transformieren", "Radierergröße"]
        case .fr: return ["Épaisseur", "Irrégularité", "Transformer", "Taille de la gomme"]
        case .it: return ["Spessore", "Irregolarità", "Trasforma", "Dimensione gomma"]
        case .ja: return ["太さ", "ラフさ", "変形", "消しゴムのサイズ"]
        case .ko: return ["두께", "거칠기", "변형", "지우개 크기"]
        case .zhHans: return ["宽度", "粗糙度", "变换", "橡皮擦大小"]
        case .zhTW, .zhHK: return ["寬度", "粗糙度", "變換", "橡皮擦大小"]
        }
    }

    static func labels(_ language: AppLanguage) -> [String] {
        switch language {
        case .enUS: return ["Colors", "Shades", "Hex code", "Pick a color from the screen", "Stroke color", "Arrowheads", "Arrow type", "Enter a valid hex color; transparency must be allowed.", "Transparent"]
        case .ptBR: return ["Cores", "Tons", "Código hexadecimal", "Escolher uma cor da tela", "Cor do traço", "Pontas de seta", "Tipo de seta", "Digite uma cor hexadecimal válida; a transparência deve ser permitida.", "Transparente"]
        case .tr: return ["Renkler", "Tonlar", "Hex kodu", "Ekrandan renk seç", "Çizgi rengi", "Ok uçları", "Ok türü", "Geçerli bir hex renk girin; saydamlığa izin verilmelidir.", "Saydam"]
        case .ru: return ["Цвета", "Оттенки", "HEX-код", "Выбрать цвет с экрана", "Цвет линии", "Наконечники", "Тип стрелки", "Введите допустимый HEX-цвет; прозрачность должна быть разрешена.", "Прозрачный"]
        case .es: return ["Colores", "Tonos", "Código hexadecimal", "Elegir un color de la pantalla", "Color del trazo", "Puntas de flecha", "Tipo de flecha", "Introduce un color hexadecimal válido; la transparencia debe estar permitida.", "Transparente"]
        case .de: return ["Farben", "Farbtöne", "Hex-Code", "Farbe vom Bildschirm wählen", "Linienfarbe", "Pfeilspitzen", "Pfeiltyp", "Gültige Hex-Farbe eingeben; Transparenz muss erlaubt sein.", "Transparent"]
        case .fr: return ["Couleurs", "Nuances", "Code hexadécimal", "Choisir une couleur à l’écran", "Couleur du trait", "Pointes de flèche", "Type de flèche", "Saisissez une couleur hexadécimale valide ; la transparence doit être autorisée.", "Transparent"]
        case .it: return ["Colori", "Tonalità", "Codice esadecimale", "Scegli un colore dallo schermo", "Colore del tratto", "Punte delle frecce", "Tipo di freccia", "Inserisci un colore esadecimale valido; la trasparenza deve essere consentita.", "Trasparente"]
        case .ja: return ["色", "濃淡", "16進数コード", "画面から色を選択", "線の色", "矢じり", "矢印の種類", "有効な16進数の色を入力してください。透明度の使用が許可されている必要があります。", "透明"]
        case .ko: return ["색상", "음영", "16진수 코드", "화면에서 색상 선택", "선 색상", "화살촉", "화살표 유형", "유효한 16진수 색상을 입력하세요. 투명도가 허용되어야 합니다.", "투명"]
        case .zhHans: return ["颜色", "色调", "十六进制代码", "从屏幕取色", "描边颜色", "箭头端点", "箭头类型", "请输入有效的十六进制颜色；必须允许透明度。", "透明"]
        case .zhTW, .zhHK: return ["顏色", "色調", "十六進位代碼", "從螢幕取色", "描邊顏色", "箭頭端點", "箭頭類型", "請輸入有效的十六進位顏色；必須允許透明度。", "透明"]
        }
    }
}
