#if canImport(Shared)
import SwiftUI
import Shared

struct FocusTimerView: View {
    let taskUID: String
    let habitUID: String
    let taskTitle: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var model = FocusTimerPresentationModel.shared
    @State private var countdownMinutes = 25
    @State private var mode = 0
    @State private var enteredTimer = false
    @State private var showDiscardConfirmation = false
    @State private var editingSession: FocusSession?
    @State private var deletingSession: FocusSession?
    @State private var adjustedSeconds = ""
    @State private var recordRequest: FocusHabitRecordRequest?
    @State private var amount = ""

    init(taskUID: String = "", taskTitle: String = "", habitUID: String = "") {
        self.taskUID = taskUID
        self.taskTitle = taskTitle
        self.habitUID = habitUID
    }

    private var timer: FocusTimerSnapshot? { model.state?.timer }
    private var busy: Bool { model.state?.isBusy == true || model.state?.isLoading == true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let warning = FocusTimerFormatting.warningMessage(model.state?.warning) {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                            .accessibilityIdentifier("focus.warning")
                    }
                    if !enteredTimer && timer == nil {
                        FocusSetupContent(model: model, mode: $mode, minutes: $countdownMinutes, busy: busy)
                    } else {
                        if let timer { activeContent(timer) } else { resultContent }
                        summaryContent
                        historySection
                    }
                    if let feedback = FocusTimerFormatting.outcomeMessage(model.state?.lastOutcome) {
                        Text(feedback).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("返回清单") { dismiss() }
                        .accessibilityIdentifier("focus.done")
                        .font(.subheadline).padding(.vertical, 8)
                }.padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(enteredTimer ? "专注" : "开始专注")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await model.connect(selectedTaskUID: taskUID.isEmpty ? nil : taskUID,
                                selectedHabitUID: habitUID.isEmpty ? nil : habitUID)
            if timer != nil || taskUID.isEmpty && habitUID.isEmpty { enteredTimer = true }
        }
        .onReceive(model.$state) { state in if state?.timer != nil { enteredTimer = true } }
        .confirmationDialog("放弃本轮计时？", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("放弃且不保存", role: .destructive) { model.discard() }
            Button("取消", role: .cancel) {}
        } message: { Text("本轮投入时间不会保存。") }
        .alert("提示", isPresented: Binding(get: { recordRequest == nil && model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("确定", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .alert("更正记录时长", isPresented: Binding(get: { editingSession != nil }, set: { if !$0 { editingSession = nil } })) {
            TextField("实际时长（秒）", text: $adjustedSeconds).keyboardType(.numberPad)
            Button("更正") {
                guard let session = editingSession, let seconds = Int64(adjustedSeconds) else {
                    model.message = "请输入整数秒数"; editingSession = nil; return
                }
                model.adjustSessionDuration(sessionUID: session.uid, durationSeconds: seconds)
                editingSession = nil
            }
            Button("取消", role: .cancel) { editingSession = nil }
        } message: { Text("不能超过 24 小时或开始与结束的真实跨度；不改变原打卡结果。") }
        .confirmationDialog("删除这条专注记录？",
            isPresented: Binding(get: { deletingSession != nil }, set: { if !$0 { deletingSession = nil } }),
            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let deletingSession { model.deleteSession(sessionUID: deletingSession.uid) }
                deletingSession = nil
            }
            Button("取消", role: .cancel) { deletingSession = nil }
        } message: { Text("仅删除时间记录，不撤销任务完成或习惯打卡。") }
        .sheet(item: $recordRequest) { request in
            NavigationStack {
                Form {
                    if let feedback = FocusTimerFormatting.outcomeMessage(model.state?.lastOutcome) {
                        Section { Text(feedback).font(.footnote).foregroundStyle(.secondary) }
                    }
                    Section(request.context.name) {
                        LabeledContent("打卡归属", value: request.context.occurredOn)
                        if metadataChanged(request) {
                            Text("习惯设置已变化，请取消后重新确认。").foregroundStyle(.secondary)
                        }
                        if request.context.trackingMode == .quantity {
                            TextField("本次实际完成数量", text: $amount).keyboardType(.numberPad)
                                .accessibilityIdentifier("focus.habit.amount")
                            if let unit = request.context.unit { Text(unit).foregroundStyle(.secondary) }
                        } else {
                            Text("确认本次完成；不会撤销已有打卡。")
                        }
                    }
                    Section {
                        Button("取消") { recordRequest = nil }.disabled(busy)
                        Button("确认") {
                            model.finishAndRecordHabit(sessionUID: request.sessionUID,
                                amount: request.context.trackingMode == .quantity ? FocusTimerFormatting.validAmount(amount) : nil,
                                updatedAt: request.context.habitUpdatedAt)
                        }
                        .disabled(busy || metadataChanged(request) || request.context.trackingMode == .quantity && FocusTimerFormatting.validAmount(amount) == nil)
                        .accessibilityIdentifier("focus.habit.confirm")
                    }
                }
                .navigationTitle("结束并打卡")
                .navigationBarTitleDisplayMode(.inline)
            }
            .interactiveDismissDisabled(busy)
            .onReceive(model.$state) { state in
                if state?.lastCompletedSession?.uid == request.sessionUID,
                   state?.lastCompletedSession?.habitRecordedAmount != nil { recordRequest = nil }
            }
            .alert("未完成打卡", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                Button("确定", role: .cancel) { model.message = nil }
            } message: { Text(model.message ?? "") }
            .presentationDetents([.medium, .large])
        }
    }

    private func activeContent(_ timer: FocusTimerSnapshot) -> some View {
        VStack(spacing: 24) {
            Text(timer.taskTitle).font(.headline).multilineTextAlignment(.center).lineLimit(2)
            if let date = timer.habitOccurredOn { Text("打卡归属 \(date)").font(.caption).foregroundStyle(.secondary) }
            FocusTimerDial(timer: timer)
            HStack(alignment: .center, spacing: 16) {
                FocusRoundAction(symbol: "stop.fill", title: "结束", enabled: !busy && timer.canFinish,
                                 identifier: "focus.finish") { model.finish() }
                FocusRoundAction(symbol: timer.canPause ? "pause.fill" : "play.fill",
                                 title: timer.canPause ? "暂停" : "继续", primary: true,
                                 enabled: !busy && (timer.canPause || timer.canResume),
                                 identifier: timer.canPause ? "focus.pause" : "focus.resume") {
                    timer.canPause ? model.pause() : model.resume()
                }
                FocusRoundAction(symbol: "checkmark", title: timer.target?.kind == .habit ? "打卡" : "完成任务",
                                 enabled: !busy && (timer.canFinishAndRecord || timer.canFinishAndComplete),
                                 identifier: timer.target?.kind == .habit ? "focus.finish.record" : "focus.finish.complete") {
                    if timer.target?.kind == .habit {
                        if let context = timer.habitRecordContext { requestRecord(sessionUID: timer.sessionUid, context: context) }
                    } else { model.finishAndCompleteTask() }
                }
            }
            Button("放弃本轮", role: .destructive) { showDiscardConfirmation = true }
                .font(.footnote).disabled(busy)
        }.padding(.vertical, 16)
    }

    private var resultContent: some View {
        VStack(spacing: 16) {
            Text(model.state?.isLoading == true ? "加载中" : "本轮已结束").font(.headline)
            if let completed = model.state?.lastCompletedSession, model.canPresentCompletedSession(completed.uid) {
                Text(FocusTimerFormatting.duration(completed.durationSeconds)).font(.largeTitle.weight(.semibold)).monospacedDigit()
                if completed.boundTarget.kind == .task {
                    if model.state?.canCompleteLastTask == true {
                        Button("完成任务") { model.completeSavedTask(completed.uid) }
                            .accessibilityIdentifier("focus.result.complete").disabled(busy)
                    } else if model.state?.lastCompletedTaskState == .completed || model.state?.lastCompletedTaskState == .archived {
                        Label("任务已完成", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if completed.boundTarget.kind == .habit, completed.habitRecordedAmount == nil,
                   let context = model.state?.habitRecordContext, context.canRecord {
                    Button("为本轮打卡") { requestRecord(sessionUID: completed.uid, context: context) }
                        .accessibilityIdentifier("focus.result.record").disabled(busy)
                }
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 36)
            .accessibilityElement(children: .contain).accessibilityIdentifier("focus.result")
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.selectedTitle.isEmpty ? taskTitle : model.selectedTitle).font(.headline).lineLimit(2)
            HStack {
                metric("今日", seconds: model.state?.selectedTaskTodayDurationSeconds ?? 0)
                Spacer()
                metric("累计", seconds: model.state?.selectedTaskTotalDurationSeconds ?? 0)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private func metric(_ title: String, seconds: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(FocusTimerFormatting.duration(seconds)).font(.headline).monospacedDigit()
        }
    }

    private var historySection: some View {
        let sessions = model.state?.selectedTarget == nil
            ? model.state?.recentSessions ?? [] : model.state?.selectedTaskRecentSessions ?? []
        return VStack(alignment: .leading, spacing: 16) {
            Text("最近记录").font(.headline)
            if sessions.isEmpty { Text("还没有专注记录").foregroundStyle(.secondary) }
            ForEach(Array(sessions.prefix(5)), id: \.uid) { session in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label(session.targetTitleSnapshot, systemImage: session.boundTarget.kind == .habit ? "leaf" : "checklist")
                            .font(.subheadline).lineLimit(2)
                        Spacer()
                        Text(FocusTimerFormatting.duration(session.durationSeconds)).monospacedDigit()
                    }
                    Text(FocusTimerFormatting.historyDate(session.startedAt))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("focus.history." + session.uid)
                .contextMenu {
                    Button("更正时长") { adjustedSeconds = String(session.durationSeconds); editingSession = session }
                    Button("删除记录", role: .destructive) { deletingSession = session }
                }
                .swipeActions {
                    Button("删除", role: .destructive) { deletingSession = session }
                    Button("更正") { adjustedSeconds = String(session.durationSeconds); editingSession = session }.tint(.blue)
                }
            }
        }.disabled(busy)
    }

    private func metadataChanged(_ request: FocusHabitRecordRequest) -> Bool {
        guard let current = model.state?.habitRecordContext, current.habitUid == request.context.habitUid else { return true }
        return current.habitUpdatedAt != request.context.habitUpdatedAt || !current.canRecord
    }

    private func requestRecord(sessionUID: String, context: FocusHabitRecordContext) {
        amount = ""
        recordRequest = FocusHabitRecordRequest(sessionUID: sessionUID, context: context)
    }
}

private struct FocusHabitRecordRequest: Identifiable {
    let sessionUID: String
    let context: FocusHabitRecordContext
    var id: String { sessionUID }
}
#endif
