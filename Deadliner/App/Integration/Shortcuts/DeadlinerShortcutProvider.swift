//
//  DeadlinerShortcutProvider.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/28.
//

import AppIntents

struct DeadlinerShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DeadlinerImportMixedResultIntent(),
            phrases: [
                "用 \(.applicationName) 导入 JSON",
                "导入到 \(.applicationName)",
                "把 JSON 导入到 \(.applicationName)",
                "\(.applicationName) 导入"
            ],
            shortTitle: "导入 JSON",
            systemImageName: "tray.and.arrow.down"
        )

        AppShortcut(
            intent: CreateInspirationIntent(),
            phrases: [
                "用 \(.applicationName) 记录灵感",
                "在 \(.applicationName) 创建灵感",
                "把想法存到 \(.applicationName)"
            ],
            shortTitle: "创建灵感",
            systemImageName: "pencil.and.outline"
        )
    }
}
