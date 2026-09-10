//
//  OpenAddEntryIntent.swift
//  Deadliner
//
//  Created by Codex on 2026/3/30.
//

import AppIntents
import Foundation

enum TaskStatusLaunchTarget: String, AppEnum {
    case home
    case urgentFirst

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "任务状态跳转"
    static let caseDisplayRepresentations: [TaskStatusLaunchTarget: DisplayRepresentation] = [
        .home: "始终打开首页",
        .urgentFirst: "优先打开紧急任务"
    ]
}

struct TaskStatusControlConfigurationIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "任务状态磁贴配置"
    static let isDiscoverable = false

    @Parameter(title: "点击后跳转")
    var launchTarget: TaskStatusLaunchTarget?

    static var parameterSummary: some ParameterSummary {
        Summary("点击后：\(\.$launchTarget)")
    }

    init() {
        self.launchTarget = .urgentFirst
    }
}

struct OpenAddEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "打开快速添加"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.top.aritxonly.deadliner.group")
        defaults?.set("open_add_tasks", forKey: "widget.pending_add_entry_type")
        return .result()
    }
}

struct OpenLifiAIIntent: AppIntent {
    static let title: LocalizedStringResource = "打开 Lifi AI"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.top.aritxonly.deadliner.group")
        defaults?.set("open_ai", forKey: "widget.pending_add_entry_type")
        return .result()
    }
}

struct OpenInspirationIntent: AppIntent {
    static let title: LocalizedStringResource = "快速记录灵感"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.top.aritxonly.deadliner.group")
        defaults?.set("open_inspiration_composer", forKey: "widget.pending_add_entry_type")
        return .result()
    }
}

struct OpenTaskStatusActionIntent: SetValueIntent {
    static let title: LocalizedStringResource = "任务状态操作"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "紧急状态")
    var value: Bool

    @Parameter(title: "跳转方式")
    var launchTarget: TaskStatusLaunchTarget

    init() {
        self.value = false
        self.launchTarget = .urgentFirst
    }

    init(value: Bool = false, launchTarget: TaskStatusLaunchTarget = .urgentFirst) {
        self.value = value
        self.launchTarget = launchTarget
    }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.top.aritxonly.deadliner.group")

        guard launchTarget == .urgentFirst else {
            defaults?.set("open_home", forKey: "widget.pending_add_entry_type")
            defaults?.removeObject(forKey: "widget.pending_task_detail_uid")
            return .result()
        }

        // App Intents run in a separate extension process. Do not open a second
        // Kotlin/Native driver here: its unchecked exception boundary would crash
        // the extension instead of returning an Intent failure.
        defaults?.set("open_home", forKey: "widget.pending_add_entry_type")
        defaults?.removeObject(forKey: "widget.pending_task_detail_uid")
        return .result()
    }
}
