import SwiftUI
import Shared

struct QuickAddDraft: Decodable {
    var kind = "TASK"
    var title = ""
    var dueAt: String?
    var note = ""
    var period = "DAILY"
    var targetCount = 1
    var weekdaysMask = 127
    var reminderTime: String?
    var needsAI = false
    var ready = false
    var source = "LOCAL"
    var message = ""

    static func decode(_ json: String) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(json.utf8))
    }
    var habitPeriod: HabitPeriod {
        switch period {
        case "WEEKLY": return .weekly
        case "MONTHLY": return .monthly
        case "EBBINGHAUS": return .ebbinghaus
        case "ONCE": return .once
        default: return .daily
        }
    }
    var detail: String {
        if kind == "TASK" { return "截止：" + (dueAt ?? "未设置") }
        let days = ["一", "二", "三", "四", "五", "六", "日"].enumerated()
            .filter { weekdaysMask & (1 << $0.offset) != 0 }.map(\.element).joined(separator: "、")
        let window = period == "WEEKLY" ? "每周" : period == "MONTHLY" ? "每月" : period == "TOTAL" ? "累计" : "每个执行日"
        return window + " \(targetCount) 次 · 周" + days + (reminderTime.map { " · 提醒 " + $0 } ?? "")
    }
}

struct QuickAddEntrySheetView: View {
    let repository: any KMPTaskUIStore
    let initialKind: String
    var onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("settings.ai.enabled") private var aiEnabled = true
    @AppStorage("userTier") private var userTier: UserTier = .free
    @State private var input = ""
    @State private var draft = QuickAddDraft()
    @State private var expanded = false
    @State private var loading = false
    @State private var saving = false
    @State private var message = ""
    @State private var modelReady = false
    @State private var recognizingAI = false
    @State private var modelStatus = QuickAddModelDownloadStatus()
    @FocusState private var inputFocused: Bool

    var body: some View {
        if expanded {
            if draft.kind == "HABIT" {
                HabitEditorSheetView(mode: .add, initialDraft: habitDraft, onDone: onDone,
                                     initialAIInput: input, initialReminderTime: draft.reminderTime)
            } else {
                TaskEditorSheetView(repository: repository, mode: .add, initialDraft: taskDraft,
                                    onDone: onDone, initialAIInput: input)
            }
        } else {
            NavigationStack {
                Form {
                    Section {
                        TextField("例如：明天下午3点交报告 / 每天读书", text: inputBinding, axis: .vertical)
                            .lineLimit(1...4).focused($inputFocused).disabled(saving || recognizingAI)
                    }
                    Section {
                        Text(modelStatus.label).font(.footnote).foregroundStyle(.secondary)
                        if modelStatus.phase == "DOWNLOADING" { ProgressView(value: modelStatus.progress) }
                        if modelStatus.retryable {
                            Button("重试下载模型") {
                                _Concurrency.Task {
                                    modelReady = await QuickAddModelService.shared.prepare()
                                    await recognize()
                                }
                            }
                        }
                    }
                    if !draft.title.isEmpty {
                        Section("实时提案") {
                            Text(draft.source == "MODEL" ? "端侧模型识别" : draft.source == "AI" ? "AI 识别" : "规则识别")
                                .font(.caption).foregroundStyle(.secondary)
                            Label(draft.title, systemImage: draft.kind == "HABIT" ? "repeat" : "checklist")
                            Text(draft.detail).font(.subheadline).foregroundStyle(.secondary)
                            if !draft.note.isEmpty { Text(draft.note) }
                        }
                    }
                    if loading { ProgressView("正在识别…") }
                    if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
                    Section {
                        Button("使用 AI 识别") { _Concurrency.Task { await recognizeWithAI() } }
                            .disabled(input.isEmpty || saving || recognizingAI)
                        Button("添加") { _Concurrency.Task { await save() } }
                            .disabled(!draft.ready || loading || saving || recognizingAI)
                        Button("展开完整表单") { loading = false; expanded = true }
                            .disabled(saving)
                    }
                }
                .navigationTitle("快速添加").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { onDone?(); dismiss() }.disabled(saving)
                    }
                }
                .interactiveDismissDisabled(saving)
                .task {
                    inputFocused = true; draft.kind = initialKind
                    modelReady = await QuickAddModelService.shared.prepare()
                }
                .task {
                    while !_Concurrency.Task<Never, Never>.isCancelled {
                        modelStatus = QuickAddModelService.shared.status()
                        do { try await _Concurrency.Task.sleep(for: .milliseconds(250)) }
                        catch { return }
                    }
                }
                .task(id: ModelRecognitionKey(text: input, ready: modelReady)) { await recognize() }
            }
        }
    }
    private struct ModelRecognitionKey: Hashable { let text: String; let ready: Bool }
    private var inputBinding: Binding<String> {
        Binding(get: { input }, set: { value in
            input = value
            message = ""
            do {
                draft = try QuickAddDraft.decode(QuickAddRecognitionPolicy().fallbackJson(
                    text: value, kind: initialKind, timezone: TimeZone.current.identifier))
                if modelReady && !value.isEmpty {
                    draft = try QuickAddDraft.decode(QuickAddRecognitionPolicy().pending(text: value, kind: initialKind).toJson())
                }
                loading = modelReady && !value.isEmpty
            } catch { draft = QuickAddDraft(); message = "识别失败，请展开补充"; loading = false }
        })
    }
    @MainActor private func recognize() async {
        let captured = input
        guard !expanded, !saving, !captured.isEmpty else { return }
        if modelReady && draft.source != "AI" && !recognizingAI {
            draft = (try? QuickAddDraft.decode(QuickAddRecognitionPolicy().pending(text: captured, kind: initialKind).toJson())) ?? draft
            loading = true
            do {
                try await _Concurrency.Task.sleep(for: .milliseconds(100))
                let local = try await QuickAddModelService.shared.recognize(captured, kind: initialKind)
                guard !_Concurrency.Task<Never, Never>.isCancelled, input == captured, !expanded, !saving else { return }
                guard !recognizingAI, draft.source != "AI" else { return }
                if let local { draft = local; message = local.message; loading = false }
            } catch {
                guard !_Concurrency.Task<Never, Never>.isCancelled else { return }
                // Keep the immediate rule preview on model failure.
            }
        }
        if !recognizingAI { loading = false }
    }
    @MainActor private func recognizeWithAI() async {
        guard !input.isEmpty, !expanded, !saving, !recognizingAI else { return }
        let captured = input
        guard aiEnabled, userTier != .free else {
            loading = false
            message = aiEnabled ? "复杂表达需要 AI 权限，也可展开完整表单添加" : "AI 已关闭，请展开补充"
            return
        }
        recognizingAI = true
        loading = true
        defer { recognizingAI = false; if input == captured { loading = false } }
        do {
            let json = try await KMPLifiCoreBridge.shared.extractQuickAdd(captured, kind: draft.kind)
            guard !_Concurrency.Task<Never, Never>.isCancelled, input == captured, !expanded, !saving else { return }
            draft = try QuickAddDraft.decode(json)
            message = draft.message
            loading = false
        } catch is CancellationError { }
        catch {
            guard !_Concurrency.Task<Never, Never>.isCancelled, input == captured, !expanded, !saving else { return }
            message = "AI 识别失败，请修改输入重试或展开补充"
            loading = false
        }
    }
    private var taskDraft: TaskDraft {
        var value = TaskDraft.empty()
        value.name = draft.title.isEmpty ? input : draft.title
        value.note = draft.note
        if let due = draft.dueAt, let date = DeadlineDateParser.safeParseOptional(due) { value.endTime = date }
        value.startTime = min(value.startTime, value.endTime)
        return value
    }
    private var habitDraft: HabitDraft {
        var value = HabitDraft.empty()
        value.name = draft.title.isEmpty ? input : draft.title
        value.period = draft.habitPeriod
        value.weekdaysMask = draft.weekdaysMask
        value.goalType = draft.period == "TOTAL" ? .total : .perPeriod
        value.timesPerPeriod = String(draft.targetCount)
        value.totalTarget = String(draft.targetCount)
        return value
    }
    @MainActor private func save() async {
        guard draft.ready, !loading, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            if draft.kind == "HABIT" {
                _ = try await PersistenceStores.habits.createHabitWithCarrier(
                    name: draft.title, period: draft.habitPeriod, weekdaysMask: draft.weekdaysMask,
                    timesPerPeriod: draft.targetCount, goalType: draft.period == "TOTAL" ? .total : .perPeriod,
                    totalTarget: draft.period == "TOTAL" ? draft.targetCount : nil, description: draft.note,
                    color: nil, iconKey: nil, categoryUID: nil, sortOrder: 0, alarmTime: draft.reminderTime)
            } else {
                _ = try await repository.createTask(TaskInsertParams(name: draft.title,
                    startTime: "", endTime: draft.dueAt ?? "", state: .active, completeTime: "",
                    note: draft.note, isStared: false, subTasks: [], calendarEventId: nil))
            }
            onDone?()
            dismiss()
        } catch { message = "保存失败：" + error.localizedDescription }
    }
}
