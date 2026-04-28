//
//  DeadlinerWidgetControl.swift
//  DeadlinerWidget
//
//  Created by Aritx 音唯 on 2026/3/6.
//

import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

private enum WidgetModelContainerFactory {
    static func makeSafe() -> ModelContainer? {
        let schema = Schema([
            DDLItemEntity.self,
            SubTaskEntity.self,
            HabitEntity.self,
            HabitRecordEntity.self,
            SyncStateEntity.self
        ])

        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedModelContainer.appGroupId
        ) {
            let sqliteURL = groupURL.appendingPathComponent("default.store")
            let config = ModelConfiguration(
                "DeadlinerModel",
                schema: schema,
                url: sqliteURL,
                cloudKitDatabase: .none
            )
            return try? ModelContainer(for: schema, configurations: [config])
        }

        let fallbackConfig = ModelConfiguration(
            "DeadlinerModel",
            schema: schema,
            cloudKitDatabase: .none
        )
        return try? ModelContainer(for: schema, configurations: [fallbackConfig])
    }
}

struct DeadlinerWidgetControl: ControlWidget {
    static let kind: String = "com.aritxonly.Deadliner.DeadlinerWidget"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenAddEntryIntent()) {
                Label("快速添加", systemImage: "calendar.badge.plus")
            }
        }
        .displayName("快速添加")
        .description("点击后直接打开 Deadliner 的添加页。")
    }
}

struct DeadlinerLifiAIControl: ControlWidget {
    static let kind: String = "com.aritxonly.Deadliner.DeadlinerLifiAIControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenLifiAIIntent()) {
                Label {
                    Text("Lifi AI")
                } icon: {
                    Image("lifi.logo.v1")
                }
            }
        }
        .displayName("Lifi AI")
        .description("点击后直接展开 Deadliner 的 Lifi AI。")
    }
}

struct DeadlinerTaskStatusControl: ControlWidget {
    static let kind: String = "com.aritxonly.Deadliner.DeadlinerTaskStatusControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: TaskStatusControlValueProvider()) { value in
            ControlWidgetToggle(
                isOn: value.isUrgent,
                action: OpenTaskStatusActionIntent(
                    value: value.isUrgent,
                    launchTarget: value.launchTarget
                )
            ) {
                Label("任务状态", systemImage: value.isUrgent ? "xmark.seal.fill" : "checkmark.seal.fill")
            } valueLabel: { isOn in
                Text(isOn ? "紧急 \(value.urgentCount)/\(max(1, value.remainingCount))" : "正常 \(value.remainingCount)")
            }
            .tint(value.isUrgent ? .red : .green)
        }
        .displayName("任务状态")
        .description("点击进入主页；若存在紧急任务则直接进入紧急任务详情。")
        .promptsForUserConfiguration()
    }
}

struct DeadlinerInspirationControl: ControlWidget {
    static let kind: String = "com.aritxonly.Deadliner.DeadlinerInspirationControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenInspirationIntent()) {
                Label("灵感", systemImage: "pencil.and.outline")
            }
        }
        .displayName("灵感")
        .description("点击后直接打开 Deadliner 的灵感页。")
    }
}

private struct TaskStatusControlValue {
    let remainingCount: Int
    let urgentCount: Int
    let launchTarget: TaskStatusLaunchTarget

    var isUrgent: Bool { urgentCount > 0 }
}

private struct TaskStatusControlValueProvider: AppIntentControlValueProvider {
    func previewValue(configuration: TaskStatusControlConfigurationIntent) -> TaskStatusControlValue {
        TaskStatusControlValue(
            remainingCount: 5,
            urgentCount: 2,
            launchTarget: configuration.launchTarget ?? .urgentFirst
        )
    }

    func currentValue(configuration: TaskStatusControlConfigurationIntent) async throws -> TaskStatusControlValue {
        do {
            return try await MainActor.run {
                guard let container = WidgetModelContainerFactory.makeSafe() else {
                    return TaskStatusControlValue(
                        remainingCount: 0,
                        urgentCount: 0,
                        launchTarget: configuration.launchTarget ?? .urgentFirst
                    )
                }
                let context = ModelContext(container)
                let fd = FetchDescriptor<DDLItemEntity>()
                let allEntities = try context.fetch(fd)

                let taskTypeRaw = "task"
                let validTasks = allEntities.filter { entity in
                    entity.isTombstoned == false && entity.typeRaw == taskTypeRaw
                }

                let visibleTasks = validTasks.filter { entity in
                    let state = entity.resolvedState()
                    return !state.isArchivedLike && !state.isAbandonedLike
                }
                let remainingTasks = visibleTasks.filter { !$0.isCompleted }
                let now = Date()
                let tomorrow = now.addingTimeInterval(24 * 3600)
                let urgent = remainingTasks.filter { item in
                    guard let date = DeadlineDateParser.safeParseOptional(item.endTime) else { return false }
                    return date > now && date <= tomorrow
                }.count

                return TaskStatusControlValue(
                    remainingCount: remainingTasks.count,
                    urgentCount: urgent,
                    launchTarget: configuration.launchTarget ?? .urgentFirst
                )
            }
        } catch {
            return TaskStatusControlValue(
                remainingCount: 0,
                urgentCount: 0,
                launchTarget: configuration.launchTarget ?? .urgentFirst
            )
        }
    }
}
