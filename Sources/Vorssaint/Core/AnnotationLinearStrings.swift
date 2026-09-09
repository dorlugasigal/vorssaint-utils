// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum AnnotationLinearStrings {
    static func head(_ head: AnnotationArrowhead, _ language: AppLanguage) -> String {
        labels(language)[head.rawValue]
    }
    static func labels(_ language: AppLanguage) -> [String] {
        switch language {
        case .enUS:
            return ["Default", "None", "Open arrow", "Filled triangle", "Triangle", "Filled circle", "Circle",
                    "Bar / one", "Filled diamond", "Diamond", "Crow-foot / many", "One or many", "Zero or one", "Zero or many",
                    "Curved", "Multi-click", "Start", "End", "Head size", "Insert point", "Remove point"]
        case .ptBR:
            return ["Padrão", "Nenhum", "Seta aberta", "Triângulo preenchido", "Triângulo", "Círculo preenchido", "Círculo",
                    "Barra / um", "Losango preenchido", "Losango", "Pé de galinha / muitos", "Um ou muitos", "Zero ou um", "Zero ou muitos",
                    "Curva", "Vários cliques", "Início", "Fim", "Tamanho da ponta", "Inserir ponto", "Remover ponto"]
        case .tr:
            return ["Varsayılan", "Yok", "Açık ok", "Dolu üçgen", "Üçgen", "Dolu daire", "Daire",
                    "Çubuk / bir", "Dolu eşkenar dörtgen", "Eşkenar dörtgen", "Kaz ayağı / çok", "Bir veya çok", "Sıfır veya bir", "Sıfır veya çok",
                    "Eğri", "Çoklu tıklama", "Başlangıç", "Bitiş", "Uç boyutu", "Nokta ekle", "Noktayı kaldır"]
        case .ru:
            return ["По умолчанию", "Нет", "Открытая стрелка", "Заполненный треугольник", "Треугольник", "Заполненный круг", "Круг",
                    "Черта / один", "Заполненный ромб", "Ромб", "Воронья лапка / много", "Один или много", "Ноль или один", "Ноль или много",
                    "Кривая", "Несколько щелчков", "Начало", "Конец", "Размер наконечника", "Добавить точку", "Удалить точку"]
        case .es:
            return ["Predeterminado", "Ninguno", "Flecha abierta", "Triángulo relleno", "Triángulo", "Círculo relleno", "Círculo",
                    "Barra / uno", "Rombo relleno", "Rombo", "Pata de cuervo / muchos", "Uno o muchos", "Cero o uno", "Cero o muchos",
                    "Curva", "Varios clics", "Inicio", "Fin", "Tamaño de punta", "Insertar punto", "Eliminar punto"]
        case .de:
            return ["Standard", "Keine", "Offener Pfeil", "Gefülltes Dreieck", "Dreieck", "Gefüllter Kreis", "Kreis",
                    "Strich / eins", "Gefüllte Raute", "Raute", "Krähenfuß / viele", "Eins oder viele", "Null oder eins", "Null oder viele",
                    "Gebogen", "Mehrfachklick", "Anfang", "Ende", "Spitzengröße", "Punkt einfügen", "Punkt entfernen"]
        case .fr:
            return ["Par défaut", "Aucune", "Flèche ouverte", "Triangle plein", "Triangle", "Cercle plein", "Cercle",
                    "Barre / un", "Losange plein", "Losange", "Patte d’oie / plusieurs", "Un ou plusieurs", "Zéro ou un", "Zéro ou plusieurs",
                    "Courbe", "Clics multiples", "Début", "Fin", "Taille de pointe", "Insérer un point", "Supprimer un point"]
        case .it:
            return ["Predefinito", "Nessuno", "Freccia aperta", "Triangolo pieno", "Triangolo", "Cerchio pieno", "Cerchio",
                    "Barra / uno", "Rombo pieno", "Rombo", "Zampa di corvo / molti", "Uno o molti", "Zero o uno", "Zero o molti",
                    "Curva", "Clic multipli", "Inizio", "Fine", "Dimensione punta", "Inserisci punto", "Rimuovi punto"]
        case .ja:
            return ["デフォルト", "なし", "開いた矢印", "塗りつぶし三角", "三角", "塗りつぶし円", "円",
                    "棒 / 1", "塗りつぶしひし形", "ひし形", "鳥の足 / 多", "1以上", "0または1", "0以上",
                    "曲線", "複数クリック", "始点", "終点", "矢じりサイズ", "点を挿入", "点を削除"]
        case .ko:
            return ["기본값", "없음", "열린 화살표", "채운 삼각형", "삼각형", "채운 원", "원",
                    "막대 / 하나", "채운 마름모", "마름모", "까마귀 발 / 다수", "하나 이상", "없거나 하나", "없거나 다수",
                    "곡선", "여러 번 클릭", "시작", "끝", "화살촉 크기", "점 삽입", "점 제거"]
        case .zhHans:
            return ["默认", "无", "开放箭头", "实心三角", "三角", "实心圆", "圆",
                    "竖线 / 一", "实心菱形", "菱形", "乌鸦脚 / 多", "一或多", "零或一", "零或多",
                    "曲线", "多次点击", "起点", "终点", "箭头大小", "插入点", "删除点"]
        case .zhTW, .zhHK:
            return ["預設", "無", "開放箭頭", "實心三角", "三角", "實心圓", "圓",
                    "豎線 / 一", "實心菱形", "菱形", "烏鴉腳 / 多", "一或多", "零或一", "零或多",
                    "曲線", "多次點擊", "起點", "終點", "箭頭大小", "插入點", "刪除點"]
        }
    }
}
