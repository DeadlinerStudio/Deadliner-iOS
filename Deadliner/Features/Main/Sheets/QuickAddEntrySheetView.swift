import SwiftUI
import Shared

struct QuickAddEntrySheetView: View {
    let repository: any KMPTaskUIStore
    let initialKind: String
    var bottomBoundary: CGFloat? = nil
    var morphSource: QuickAddMorphSource? = nil
    @State private var morphProgress: CGFloat = 0
    @State private var closing = false
    var onDone: (() -> Void)?
    @AppStorage("settings.ai.enabled") private var aiEnabled = true
    @AppStorage("userTier") private var userTier: UserTier = .free
    @State private var recognitionBackend = QuickAddBackend.current
    @State private var recognitionLanguage = Locale.preferredLanguages.first ?? "zh"
    @State private var recognitionTimezone = TimeZone.current.identifier
    @State private var defaultStart = Date()
    @State private var input = ""
    @State private var draft = QuickAddDraft()
    @State private var expanded = false
    @State private var overrides = QuickAddOverrides()
    @State private var categoryUID: String?
    @State private var categories: [TaskCategory] = []
    @State private var showCategory = false
    @State private var attribute: QuickAddAttribute?
    private var effectiveDraft: QuickAddDraft { overrides.applying(to: draft) }
    private var displayedDraft: QuickAddDraft {
        var result = effectiveDraft
        if recognitionBackend == .kivo, result.source == "LOCAL", !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.needsAI = true
        }
        return result
    }
    private var busy: Bool { saving || recognizingAI }
    private var timelineValid: Bool {
        guard let start = overrides.startAt,
              let end = effectiveDraft.dueAt.flatMap(DeadlineDateParser.safeParseOptional) else { return true }
        return start < end
    }
    private var canSave: Bool {
        effectiveDraft.ready && effectiveDraft.recognitionState != "KIVO_PARTIAL"
            && (!effectiveDraft.needsAI || effectiveDraft.recognitionState == "READY_WITH_AI")
            && (!loading || effectiveDraft.source == "MANUAL") && !busy && !closing && timelineValid
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    @State private var loading = false
    @State private var saving = false
    @State private var message = ""
    @State private var modelReady = false
    @State private var recognizingAI = false
    @State private var modelStatus = QuickAddModelDownloadStatus()
    @FocusState private var inputFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            let placement = QuickAddPanelPlacement(
                size: geometry.size, bottomBoundary: bottomBoundary.map { $0 - origin.y },
                horizontalInset: FloatingComposerStyle.horizontalInset,
                dockClearance: FloatingComposerStyle.dockClearance)
            QuickAddGlassPanel(
                input: inputBinding, draft: displayedDraft, modelStatus: modelStatus,
                loading: loading && effectiveDraft.source != "MANUAL", saving: saving, recognizingAI: recognizingAI,
                message: !timelineValid ? "截止时间必须晚于开始时间" :
                    (effectiveDraft.source == "MANUAL" && message == draft.message ? "" : message), canSave: canSave,
                categoryName: categories.first { $0.uid == categoryUID }?.name,
                availableHeight: placement.region.height,
                backend: recognitionBackend, language: recognitionLanguage, startAt: overrides.startAt,
                onRemoveAttribute: removeAttribute,
                onRemoveCategory: { categoryUID = nil },
                categories: categories, selectedCategoryUID: categoryUID,
                onSelectCategory: { categoryUID = $0 },
                morphSource: morphSource,
                morphProgress: morphProgress,
                inputFocused: $inputFocused,
                onClose: finish,
                onExpand: { inputFocused = false; loading = false; expanded = true },
                onCategory: { inputFocused = false; showCategory = true },
                onAttribute: { inputFocused = false; attribute = $0 },
                onAI: { _Concurrency.Task { await recognizeWithAI() } },
                onSave: { _Concurrency.Task { await save() } },
                onRetry: { _Concurrency.Task { await prepareModel() } }
            )
            .frame(maxWidth: min(520, placement.region.width))
            .frame(width: placement.region.width, height: placement.region.height,
                   alignment: .bottomTrailing)
            .offset(x: placement.region.minX, y: placement.region.minY)
            .opacity(expanded ? 0 : 1)
            .allowsHitTesting(!expanded && !closing)
            .accessibilityHidden(expanded)
        }
        .background {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !busy, !expanded else { return }
                    finish()
                }
        }
        .sheet(isPresented: $expanded, onDismiss: finish) {
            fullEditor.presentationDetents([.large])
        }
        .sheet(isPresented: $showCategory) {
            CategoryPickerSheet(selectedUID: $categoryUID) {
                _Concurrency.Task { categories = (try? await PersistenceStores.categories.allCategories()) ?? categories }
            }
        }
        .sheet(item: $attribute) { selected in
            QuickAddAttributeSheet(attribute: selected, draft: effectiveDraft, overrides: $overrides)
        }
        .task {
            draft.kind = initialKind
            categories = (try? await PersistenceStores.categories.allCategories()) ?? []
            await prepareModel()
        }
        .task {
            if morphSource != nil {
                await _Concurrency.Task.yield()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.92)) { morphProgress = 1 }
            } else { morphProgress = 1 }
            // Let the glass surface reach its destination before the keyboard changes the layout.
            do { try await _Concurrency.Task.sleep(for: .milliseconds(500)) }
            catch { return }
            guard !expanded, !closing else { return }
            inputFocused = true
        }
        .task {
            while !_Concurrency.Task<Never, Never>.isCancelled {
                modelStatus = QuickAddModelService.shared.status()
                do { try await _Concurrency.Task.sleep(for: .milliseconds(250)) }
                catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            recognitionTimezone = TimeZone.current.identifier
        }
        .task(id: ModelRecognitionKey(text: input, ready: modelReady, timezone: recognitionTimezone)) { await recognize() }
    }

    @ViewBuilder private var fullEditor: some View {
        if effectiveDraft.kind == "HABIT" {
            HabitEditorSheetView(mode: .add, initialDraft: habitDraft,
                                 initialAIInput: input, initialReminderTime: effectiveDraft.reminderTime)
        } else {
            TaskEditorSheetView(repository: repository, mode: .add, initialDraft: taskDraft,
                                initialAIInput: input)
        }
    }

    private func finish() {
        guard !closing else { return }
        closing = true
        inputFocused = false
        guard morphSource != nil, !expanded else { onDone?(); return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.92), completionCriteria: .logicallyComplete) {
            morphProgress = 0
        } completion: { onDone?() }
    }
    private struct ModelRecognitionKey: Hashable { let text: String; let ready: Bool; let timezone: String }

    @MainActor private func prepareModel() async {
        modelReady = false
        let ready = await QuickAddModelService.shared.prepare(backend: recognitionBackend, language: recognitionLanguage)
        guard !_Concurrency.Task<Never, Never>.isCancelled, !closing, !expanded else { return }
        modelReady = ready
        modelStatus = QuickAddModelService.shared.status()
    }

    private func removeAttribute(_ attribute: QuickAddAttribute) {
        switch attribute {
        case .start: overrides.startAt = nil
        case .due: overrides.dueAt = nil; overrides.removesDue = true
        case .note: overrides.note = ""
        case .schedule: overrides.removesSchedule = true; overrides.period = nil
        case .reminder: overrides.reminderTime = nil; overrides.removesReminder = true
        }
    }
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
        let zone = TimeZone.current.identifier
        guard !expanded, !closing, !saving, !captured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { loading = false; return }
        if !modelReady { applyRuleFallback(captured) }
        if modelReady && draft.source != "AI" && !recognizingAI {
            draft = (try? QuickAddDraft.decode(QuickAddRecognitionPolicy().pending(text: captured, kind: initialKind).toJson())) ?? draft
            loading = true
            do {
                try await _Concurrency.Task.sleep(for: .milliseconds(100))
                let local = try await QuickAddModelService.shared.recognize(captured, kind: initialKind,
                    backend: recognitionBackend, language: recognitionLanguage, timezone: zone)
                guard !_Concurrency.Task<Never, Never>.isCancelled, input == captured, TimeZone.current.identifier == zone, !expanded, !closing, !saving else { return }
                guard !recognizingAI, draft.source != "AI" else { return }
                if let local { draft = local; message = local.message; loading = false }
                else { applyRuleFallback(captured) }
            } catch {
                guard !_Concurrency.Task<Never, Never>.isCancelled else { return }
                applyRuleFallback(captured)
            }
        }
        if !recognizingAI { loading = false }
    }
    @MainActor private func applyRuleFallback(_ text: String) {
        guard input == text, !expanded, !closing, !saving, !recognizingAI, draft.source != "AI" else { return }
        if let fallback = try? QuickAddDraft.decode(QuickAddRecognitionPolicy().fallbackJson(
            text: text, kind: initialKind, timezone: TimeZone.current.identifier)) {
            draft = fallback
            message = fallback.message
        }
    }
    @MainActor private func recognizeWithAI() async {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !expanded, !closing, !saving, !recognizingAI else { return }
        let captured = input
        let zone = TimeZone.current.identifier
        guard aiEnabled, userTier != .free else {
            loading = false
            message = aiEnabled ? "复杂表达需要 AI 权限，也可展开完整表单添加" : "AI 已关闭，请展开补充"
            return
        }
        recognizingAI = true
        loading = true
        defer { recognizingAI = false; if input == captured { loading = false } }
        do {
            let json = try await KMPLifiCoreBridge.shared.extractQuickAdd(captured, kind: effectiveDraft.kind)
            guard !_Concurrency.Task<Never, Never>.isCancelled, input == captured, TimeZone.current.identifier == zone, !expanded, !closing, !saving else { return }
            draft = try QuickAddDraft.decode(json)
            message = draft.message
            loading = false
        } catch is CancellationError { }
        catch {
            guard !_Concurrency.Task<Never, Never>.isCancelled, input == captured, TimeZone.current.identifier == zone, !expanded, !closing, !saving else { return }
            message = "AI 识别失败，请修改输入重试或展开补充"
            loading = false
        }
    }
    private var taskDraft: TaskDraft {
        var value = TaskDraft.empty()
        value.name = effectiveDraft.title.isEmpty ? input : effectiveDraft.title
        value.note = effectiveDraft.note
        value.categoryUID = categoryUID
        if let due = effectiveDraft.dueAt, let date = DeadlineDateParser.safeParseOptional(due) { value.endTime = date }
        value.startTime = overrides.startAt ?? min(defaultStart, value.endTime.addingTimeInterval(-60))
        return value
    }
    private var habitDraft: HabitDraft {
        var value = HabitDraft.empty()
        value.name = effectiveDraft.title.isEmpty ? input : effectiveDraft.title
        value.description = effectiveDraft.note
        value.categoryUID = categoryUID
        value.period = effectiveDraft.habitPeriod
        value.weekdaysMask = effectiveDraft.weekdaysMask
        value.goalType = effectiveDraft.period == "TOTAL" ? .total : .perPeriod
        value.timesPerPeriod = String(effectiveDraft.targetCount)
        value.totalTarget = String(effectiveDraft.targetCount)
        return value
    }
    @MainActor private func save() async {
        guard canSave else { return }
        let task = taskDraft
        saving = true
        defer { saving = false }
        do {
            if effectiveDraft.kind == "HABIT" {
                _ = try await PersistenceStores.habits.createHabitWithCarrier(
                    name: effectiveDraft.title, period: effectiveDraft.habitPeriod, weekdaysMask: effectiveDraft.weekdaysMask,
                    timesPerPeriod: effectiveDraft.targetCount, goalType: effectiveDraft.period == "TOTAL" ? .total : .perPeriod,
                    totalTarget: effectiveDraft.period == "TOTAL" ? effectiveDraft.targetCount : nil, description: effectiveDraft.note,
                    color: nil, iconKey: nil, categoryUID: categoryUID, sortOrder: 0, alarmTime: effectiveDraft.reminderTime)
            } else {
                _ = try await repository.createTask(TaskInsertParams(name: effectiveDraft.title,
                    startTime: task.startTime.toLocalISOString(),
                    endTime: effectiveDraft.dueAt.flatMap(DeadlineDateParser.safeParseOptional)?.toLocalISOString() ?? "", state: .active, completeTime: "",
                    note: effectiveDraft.note, isStared: false, subTasks: [], calendarEventId: nil, categoryUID: categoryUID))
            }
            finish()
        } catch { message = "保存失败：" + error.localizedDescription }
    }
}
