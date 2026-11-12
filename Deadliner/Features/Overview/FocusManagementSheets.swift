import SwiftUI
import Shared

struct FocusManagementTargetSheet: View {
    @ObservedObject var model: OverviewViewModel
    let onSelect: (FocusStartTargetOption) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = model.managementError { OverviewFailureView(message: error, retry: model.reloadFocusManagement) }
                    if model.managementLoading && model.focusManagement == nil { ProgressView() }
                    FocusTargetChooser(options: (model.focusManagement?.startTargets ?? []).map {
                        FocusPickerOption(uid: $0.target.uid, title: $0.title, habit: $0.target.kind == .habit)
                    }, selectedUID: "", selectedHabit: false, busy: model.managementLoading) { selected in
                        if let option = model.focusManagement?.startTargets.first(where: { $0.target.uid == selected.uid && ($0.target.kind == .habit) == selected.habit }) { onSelect(option) }
                    }
                }.padding(20)
            }.navigationTitle("选择专注目标").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.presentationDetents([.large])
    }
}

struct FocusManagementTargetHistory: View {
    @ObservedObject var model: OverviewViewModel
    let target: FocusTargetRef
    @Environment(\.dismiss) private var dismiss
    @State private var limit: Int32 = 50
    @State private var selected: String?
    var body: some View {
        NavigationStack {
            List {
                if let error = model.managementError { OverviewFailureView(message: error, retry: model.reloadFocusManagement) }
                if let data = model.focusManagement { FocusManagementHistory(data: data, target: target, limit: $limit) { selected = $0 } }
            }.navigationTitle(model.focusManagement?.allTime.targets.first { $0.target == target }?.title ?? "目标专注历史")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }.sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let selected { FocusManagementDetailSheet(model: model, uid: selected) }
        }
    }
}

struct FocusManagementDetailSheet: View {
    @ObservedObject var model: OverviewViewModel
    let uid: String
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @State private var busy = false
    @State private var error: String?
    private var record: FocusManagementRecord? { model.focusManagement?.records.first { $0.session.uid == uid } }
    var body: some View {
        NavigationStack {
            Form {
                if let record {
                    let session = record.session
                    Section(record.title) {
                        Text(FocusTimerFormatting.clock(session.durationSeconds)).font(.largeTitle).monospacedDigit()
                        LabeledContent("目标状态", value: focusManagementStatus(record.targetStatus))
                        if record.title != session.targetTitleSnapshot { LabeledContent("计时当时名称", value: session.targetTitleSnapshot) }
                        LabeledContent("开始", value: date(session.startedAt))
                        LabeledContent("结束", value: date(session.endedAt))
                        LabeledContent("计时方式", value: session.mode == .countdown ? "倒计时" : "正计时")
                        if let day = session.habitOccurredOn { LabeledContent("习惯日期", value: day) }
                        if let count = session.habitRecordedAmount { LabeledContent("当时打卡数量", value: String(count.intValue)) }
                        LabeledContent("结束原因", value: reason(session.completionKind))
                    }
                    Section {
                        Button("更正时长") { editing = true }.disabled(busy || record.maximumAdjustmentSeconds < 1)
                        Button("删除记录", role: .destructive) { deleting = true }.disabled(busy)
                    }
                } else { ContentUnavailableView("记录已被删除或不可用", systemImage: "timer") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if busy { ProgressView() }
            }.navigationTitle("专注记录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.disabled(busy) } }
        }.interactiveDismissDisabled(busy)
            .sheet(isPresented: $editing) { FocusManagementAdjustmentSheet(model: model, uid: uid) }
            .confirmationDialog("删除这条专注记录？", isPresented: $deleting, titleVisibility: .visible) {
                Button("确认删除", role: .destructive) {
                    busy = true; error = nil
                    model.mutateFocusSession(uid: uid, seconds: nil) { message in
                        busy = false
                        if let message { error = message } else { dismiss() }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text((record?.title ?? "") + " · " + (record?.localStartedDate ?? "") + " · " + FocusTimerFormatting.duration(record?.session.durationSeconds ?? 0) + "\n已完成的任务和习惯打卡不会撤销。")
            }
    }
    private func date(_ raw: String) -> String {
        DeadlineDateParser.safeParseOptional(raw)?.formatted(date: .abbreviated, time: .standard) ?? raw
    }
    private func reason(_ kind: FocusCompletionKind) -> String {
        switch kind {
        case .countdownElapsed: "倒计时到点"
        case .focusAndTaskCompleted: "结束并完成任务"
        case .focusAndHabitRecorded: "结束并打卡"
        case .focusAndTaskChanged, .taskBecameInactive, .habitBecameInactive: "目标状态变更"
        default: "仅保存专注"
        }
    }
}

private struct FocusManagementAdjustmentSheet: View {
    @ObservedObject var model: OverviewViewModel
    let uid: String
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = ""
    @State private var seconds = ""
    @State private var busy = false
    @State private var error: String?
    private var record: FocusManagementRecord? { model.focusManagement?.records.first { $0.session.uid == uid } }
    private var duration: Int64? {
        guard !minutes.isEmpty, !seconds.isEmpty, minutes.allSatisfy(\.isNumber), seconds.allSatisfy(\.isNumber),
              let m = Int64(minutes), let s = Int64(seconds), (0...59).contains(s),
              let maximum = record?.maximumAdjustmentSeconds, m <= maximum / 60 else { return nil }
        let result = m * 60 + s
        return (1...max(1, maximum)).contains(result) && result <= maximum ? result : nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(record?.title ?? "专注记录") {
                    TextField("分钟", text: $minutes).keyboardType(.numberPad)
                    TextField("秒（0–59）", text: $seconds).keyboardType(.numberPad)
                    Text("只允许调低，可输入 1–\(record?.maximumAdjustmentSeconds ?? 0) 秒").font(.caption).foregroundStyle(.secondary)
                }.disabled(busy)
                if let error { Text(error).foregroundStyle(.red) }
                Button("保存更正") {
                    guard let duration, !busy else { return }
                    busy = true; error = nil
                    model.mutateFocusSession(uid: uid, seconds: duration) { message in
                        busy = false
                        if let message { error = message } else { dismiss() }
                    }
                }.disabled(duration == nil || busy)
                if busy { ProgressView() }
            }.navigationTitle("更正专注时长").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }
        }.interactiveDismissDisabled(busy).onAppear {
            if minutes.isEmpty { minutes = String((record?.session.durationSeconds ?? 0) / 60); seconds = String((record?.session.durationSeconds ?? 0) % 60) }
        }
    }
}
