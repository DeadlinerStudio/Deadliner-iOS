//
//  DeadlinerWidgetControl.swift
//  DeadlinerWidget
//
//  Created by Aritx 音唯 on 2026/3/6.
//

import AppIntents
import SwiftUI
import WidgetKit

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
        .description("点击后快速记录一条灵感。")
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
        let snapshot = KMPWidgetSnapshotReader.load()
        return TaskStatusControlValue(
            remainingCount: snapshot.remaining,
            urgentCount: snapshot.urgent,
            launchTarget: configuration.launchTarget ?? .urgentFirst
        )
    }
}
