// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum AnnotationSessionStrings {
    static func instructions(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: return "Draw captures pointer input; Interact passes clicks to the desktop. Close clears the session. Shift-click selects multiple objects. Return finishes a path; Command-Return finishes multiline text."
        case .ptBR: return "Desenhar captura o ponteiro; Interagir permite clicar na área de trabalho. Fechar limpa a sessão. Shift-clique seleciona vários objetos. Return conclui um caminho; Command-Return conclui o texto."
        case .tr: return "Çiz modu işaretçi girdisini yakalar; Etkileşim tıklamaları masaüstüne iletir. Kapat oturumu temizler. Shift-tıklama birden çok nesne seçer. Return yolu, Command-Return metni tamamlar."
        case .ru: return "Рисование перехватывает указатель; взаимодействие передаёт щелчки рабочему столу. Закрытие очищает сеанс. Shift-щелчок выбирает несколько объектов. Return завершает линию, Command-Return — текст."
        case .es: return "Dibujar captura el puntero; Interactuar permite hacer clic en el escritorio. Cerrar borra la sesión. Mayús-clic selecciona varios objetos. Return termina un trazado; Comando-Return termina el texto."
        case .de: return "Zeichnen erfasst den Zeiger; Interagieren leitet Klicks an den Schreibtisch weiter. Schließen leert die Sitzung. Umschalt-Klick wählt mehrere Objekte. Return beendet einen Pfad, Befehl-Return den Text."
        case .fr: return "Dessiner capture le pointeur ; Interagir transmet les clics au bureau. Fermer efface la session. Maj-clic sélectionne plusieurs objets. Retour termine un tracé ; Commande-Retour termine le texte."
        case .it: return "Disegna acquisisce il puntatore; Interagisci inoltra i clic alla scrivania. Chiudi cancella la sessione. Maiuscole-clic seleziona più oggetti. Invio termina un tracciato; Comando-Invio termina il testo."
        case .ja: return "描画ではポインタ入力を受け取り、操作ではデスクトップにクリックを通します。閉じるとセッションを消去します。Shiftクリックで複数選択、Returnでパスを確定、Command-Returnで複数行テキストを確定します。"
        case .ko: return "그리기는 포인터 입력을 받고, 상호 작용은 클릭을 데스크탑으로 전달합니다. 닫으면 세션이 지워집니다. Shift-클릭으로 여러 개를 선택합니다. Return은 경로를, Command-Return은 여러 줄 텍스트를 완료합니다."
        case .zhHans: return "绘制模式接收指针输入，交互模式将点击传递到桌面。关闭会清除会话。Shift-点击可多选；Return 完成路径，Command-Return 完成多行文本。"
        case .zhTW, .zhHK: return "繪製模式接收指標輸入，互動模式將點擊傳遞至桌面。關閉會清除工作階段。Shift-點擊可多選；Return 完成路徑，Command-Return 完成多行文字。"
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
