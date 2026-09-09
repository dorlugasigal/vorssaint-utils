// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

enum AnnotationCommandStrings {
    static func title(_ action: AnnotationSelectionAction, _ language: AppLanguage) -> String {
        labels(language)[action.rawValue]
    }

    static func labels(_ language: AppLanguage) -> [String] {
        switch language {
        case .enUS:
            return ["Select all", "Duplicate", "Delete", "Group", "Ungroup", "Lock", "Unlock",
                    "Bring forward", "Send backward", "Bring to front", "Send to back",
                    "Rotate left", "Rotate right", "Enlarge", "Shrink"]
        case .ptBR:
            return ["Selecionar tudo", "Duplicar", "Excluir", "Agrupar", "Desagrupar", "Bloquear", "Desbloquear",
                    "Avançar", "Recuar", "Trazer para frente", "Enviar para trás",
                    "Girar à esquerda", "Girar à direita", "Ampliar", "Reduzir"]
        case .tr:
            return ["Tümünü seç", "Çoğalt", "Sil", "Grupla", "Grubu çöz", "Kilitle", "Kilidi aç",
                    "Öne getir", "Arkaya gönder", "En öne getir", "En arkaya gönder",
                    "Sola döndür", "Sağa döndür", "Büyüt", "Küçült"]
        case .ru:
            return ["Выбрать всё", "Дублировать", "Удалить", "Сгруппировать", "Разгруппировать", "Заблокировать", "Разблокировать",
                    "Переместить вперёд", "Переместить назад", "На передний план", "На задний план",
                    "Повернуть влево", "Повернуть вправо", "Увеличить", "Уменьшить"]
        case .es:
            return ["Seleccionar todo", "Duplicar", "Eliminar", "Agrupar", "Desagrupar", "Bloquear", "Desbloquear",
                    "Adelantar", "Retroceder", "Traer al frente", "Enviar al fondo",
                    "Girar a la izquierda", "Girar a la derecha", "Ampliar", "Reducir"]
        case .de:
            return ["Alles auswählen", "Duplizieren", "Löschen", "Gruppieren", "Gruppierung aufheben", "Sperren", "Entsperren",
                    "Nach vorne", "Nach hinten", "In den Vordergrund", "In den Hintergrund",
                    "Nach links drehen", "Nach rechts drehen", "Vergrößern", "Verkleinern"]
        case .fr:
            return ["Tout sélectionner", "Dupliquer", "Supprimer", "Grouper", "Dissocier", "Verrouiller", "Déverrouiller",
                    "Avancer", "Reculer", "Mettre au premier plan", "Mettre à l’arrière-plan",
                    "Tourner à gauche", "Tourner à droite", "Agrandir", "Réduire"]
        case .it:
            return ["Seleziona tutto", "Duplica", "Elimina", "Raggruppa", "Separa", "Blocca", "Sblocca",
                    "Porta avanti", "Porta indietro", "Porta in primo piano", "Porta in secondo piano",
                    "Ruota a sinistra", "Ruota a destra", "Ingrandisci", "Riduci"]
        case .ja:
            return ["すべて選択", "複製", "削除", "グループ化", "グループ解除", "ロック", "ロック解除",
                    "前へ移動", "後ろへ移動", "最前面へ移動", "最背面へ移動",
                    "左に回転", "右に回転", "拡大", "縮小"]
        case .ko:
            return ["모두 선택", "복제", "삭제", "그룹화", "그룹 해제", "잠금", "잠금 해제",
                    "앞으로 이동", "뒤로 이동", "맨 앞으로 이동", "맨 뒤로 이동",
                    "왼쪽으로 회전", "오른쪽으로 회전", "확대", "축소"]
        case .zhHans:
            return ["全选", "复制", "删除", "组合", "取消组合", "锁定", "解锁",
                    "上移一层", "下移一层", "置于顶层", "置于底层", "向左旋转", "向右旋转", "放大", "缩小"]
        case .zhTW, .zhHK:
            return ["全選", "複製", "刪除", "群組", "取消群組", "鎖定", "解鎖",
                    "上移一層", "下移一層", "移至最上層", "移至最下層", "向左旋轉", "向右旋轉", "放大", "縮小"]
        }
    }
}
