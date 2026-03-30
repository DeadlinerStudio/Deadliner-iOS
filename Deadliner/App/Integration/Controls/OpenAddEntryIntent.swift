//
//  OpenAddEntryIntent.swift
//  Deadliner
//
//  Created by Codex on 2026/3/30.
//

import AppIntents
import Foundation

struct OpenAddEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "打开快速添加"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.top.aritxonly.deadliner.group")
        defaults?.set("tasks", forKey: "widget.pending_add_entry_type")
        return .result()
    }
}
