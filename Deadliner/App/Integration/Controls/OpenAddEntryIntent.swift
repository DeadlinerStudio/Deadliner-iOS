//
//  OpenAddEntryIntent.swift
//  Deadliner
//
//  Created by Codex on 2026/3/30.
//

import AppIntents
import Foundation
import SwiftData

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
    static let title: LocalizedStringResource = "打开灵感"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.top.aritxonly.deadliner.group")
        defaults?.set("open_inspiration", forKey: "widget.pending_add_entry_type")
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
            defaults?.removeObject(forKey: "widget.pending_task_detail_id")
            return .result()
        }

        if let urgentTaskId = await findMostUrgentTaskId() {
            defaults?.set("open_home_or_urgent", forKey: "widget.pending_add_entry_type")
            defaults?.set(urgentTaskId, forKey: "widget.pending_task_detail_id")
        } else {
            defaults?.set("open_home", forKey: "widget.pending_add_entry_type")
            defaults?.removeObject(forKey: "widget.pending_task_detail_id")
        }
        return .result()
    }

    @MainActor
    private func findMostUrgentTaskId() async -> Int64? {
        let container = SharedModelContainer.shared
        let context = ModelContext(container)
        let fd = FetchDescriptor<DDLItemEntity>()
        let allEntities = (try? context.fetch(fd)) ?? []

        let now = Date()
        let tomorrow = now.addingTimeInterval(24 * 3600)
        let taskTypeRaw = "task"

        let candidates = allEntities.filter { entity in
            guard entity.isTombstoned == false, entity.typeRaw == taskTypeRaw, entity.isCompleted == false else { return false }
            let state = entity.resolvedState()
            guard !state.isArchivedLike && !state.isAbandonedLike else { return false }
            guard let endDate = DeadlineDateParser.safeParseOptional(entity.endTime) else { return false }
            return endDate > now && endDate <= tomorrow
        }

        let urgent = candidates.min { lhs, rhs in
            lhs.endTime < rhs.endTime
        }
        return urgent?.legacyId
    }
}
