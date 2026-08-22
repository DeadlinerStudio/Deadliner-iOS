//
//  HabitEditorSheetView.swift
//  Deadliner
//
//  Created by Gemini CLI on 2026/3/7.
//

import SwiftUI
#if canImport(Shared)
import Shared
#endif

struct HabitDraft: Equatable {
    var name: String
    var description: String
    var period: HabitPeriod
    var weekdaysMask: Int = 127
    var goalType: HabitGoalType
    var timesPerPeriod: String
    var totalTarget: String
    var categoryUID: String?

    static func empty() -> HabitDraft {
        .init(
            name: "",
            description: "",
            period: .daily,
            weekdaysMask: HabitWeekdaySelection.allDaysMask,
            goalType: .perPeriod,
            timesPerPeriod: "1",
            totalTarget: "100",
            categoryUID: nil
        )
    }

    static func fromHabit(_ h: Habit) -> HabitDraft {
        .init(
            name: h.name,
            description: h.description ?? "",
            period: h.period,
            weekdaysMask: h.weekdaysMask,
            goalType: h.goalType,
            timesPerPeriod: String(h.timesPerPeriod),
            totalTarget: String(h.totalTarget ?? 100),
            categoryUID: h.categoryUID
        )
    }
}

enum HabitSheetMode: Equatable {
    case add
    case edit(original: Habit)
}

struct HabitEditorSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeStore: ThemeStore
    
    @AppStorage("userTier") private var userTier: UserTier = .free
    @AppStorage("settings.ai.enabled") private var aiEnabled: Bool = true
    
    let habitRepository: any KMPHabitUIStore = PersistenceStores.habits
    let mode: HabitSheetMode
    var onDone: (() -> Void)? = nil
    var onSaved: (() -> Void)? = nil
    var principalToolbarContent: AnyView? = nil
    var embedsInParentNavigationStack: Bool = false
    var saveTrigger: Int = 0
    var onSaveEnabledChange: ((Bool) -> Void)? = nil
    var initialAIInput: String? = nil
    var autoRunAIOnAppear: Bool = false
    
    // ===== UI States =====
    @State private var name: String
    @State private var description: String
    @State private var period: HabitPeriod
    @State private var weekdaysMask: Int
    @State private var goalType: HabitGoalType
    @State private var timesPerPeriod: String
    @State private var totalTarget: String
    @State private var selectedCategoryUID: String?
    @State private var categories: [TaskCategory] = []
    @State private var showCategoryPicker = false
    
    @State private var isReminderEnabled: Bool
    @State private var reminderTime: Date
    
    @State private var aiInputText: String = ""
    @State private var isAILoading: Bool = false
    @State private var isSaving: Bool = false
    
    @State private var alertMessage: String?
    @State private var showAlert: Bool = false
    @State private var showPaywall: Bool = false
    
    init(
        mode: HabitSheetMode,
        initialDraft: HabitDraft = .empty(),
        onDone: (() -> Void)? = nil,
        onSaved: (() -> Void)? = nil,
        principalToolbarContent: AnyView? = nil,
        embedsInParentNavigationStack: Bool = false,
        saveTrigger: Int = 0,
        onSaveEnabledChange: ((Bool) -> Void)? = nil,
        initialAIInput: String? = nil,
        autoRunAIOnAppear: Bool = false
    ) {
        self.mode = mode
        self.onDone = onDone
        self.onSaved = onSaved
        self.principalToolbarContent = principalToolbarContent
        self.embedsInParentNavigationStack = embedsInParentNavigationStack
        self.saveTrigger = saveTrigger
        self.onSaveEnabledChange = onSaveEnabledChange
        self.initialAIInput = initialAIInput
        self.autoRunAIOnAppear = autoRunAIOnAppear
        
        _name = State(initialValue: initialDraft.name)
        _description = State(initialValue: initialDraft.description)
        _period = State(initialValue: initialDraft.period)
        _weekdaysMask = State(initialValue: initialDraft.weekdaysMask)
        _goalType = State(initialValue: initialDraft.goalType)
        _timesPerPeriod = State(initialValue: initialDraft.timesPerPeriod)
        _totalTarget = State(initialValue: initialDraft.totalTarget)
        _selectedCategoryUID = State(initialValue: initialDraft.categoryUID)
        
        let initialAlarmTime: String? = {
            if case .edit(let h) = mode { return h.alarmTime }
            return nil
        }()
        
        if let alarm = initialAlarmTime, !alarm.isEmpty,
           let date = Self.parseAlarmTime(alarm) {
            _isReminderEnabled = State(initialValue: true)
            _reminderTime = State(initialValue: date)
        } else {
            _isReminderEnabled = State(initialValue: false)
            _reminderTime = State(initialValue: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date())
        }

        _aiInputText = State(initialValue: initialAIInput ?? "")
    }
    
    private static func parseAlarmTime(_ alarm: String) -> Date? {
        let parts = alarm.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]) else { return nil }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())
    }
    
    var body: some View {
        Group {
            if embedsInParentNavigationStack {
                editorContent
            } else {
                NavigationStack {
                    editorContent
                }
            }
        }
        .deadlinerScrollEdgeEffect()
    }

    private var editorContent: some View {
        ZStack {
            Form {
                if aiEnabled {
                    Section("AI 快速添加") {
                        HStack(spacing: 8) {
                            TextField("例如：每天背20个单词...", text: $aiInputText, axis: .vertical)
                                .lineLimit(1...3)
                            
                            Button {
                                if userTier == .free {
                                    showPaywall = true
                                } else {
                                    _Concurrency.Task { await onAITriggered() }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("解析")
                                    if userTier == .free {
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            .disabled(isAILoading || aiInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        }
                    }
                }
                
                Section("基础信息") {
                    TextField("要做什么？", text: $name)
                    TextField("备注（可选）", text: $description, axis: .vertical)
                        .lineLimit(2...5)

                    Button {
                        showCategoryPicker = true
                    } label: {
                        HStack {
                            Text("分类")
                            Spacer()
                            categorySelectionLabel
                        }
                    }
                    .foregroundStyle(.primary)
                }
                
                Section("类型 / 周期") {
                    Picker("周期", selection: Binding(
                        get: { period },
                        set: { newValue in
                            if newValue == .ebbinghaus && userTier == .free {
                                showPaywall = true
                            } else {
                                period = newValue
                            }
                        }
                    )) {
                        Text("每日").tag(HabitPeriod.daily)
                        Text("每周").tag(HabitPeriod.weekly)
                        Text("每月").tag(HabitPeriod.monthly)
                        
                        Text("艾宾浩斯 \(userTier == .free ? Image(systemName: "crown.fill") : Image(systemName: ""))")
                            .tag(HabitPeriod.ebbinghaus)
                    }
                    .pickerStyle(.segmented)
                }

                if period != .ebbinghaus {
                    Section("执行日") {
                        HabitWeekdaySelection(mask: $weekdaysMask)
                    }
                }
                
                if period != .ebbinghaus {
                    Section("目标设置") {
                        HStack {
                            Text("每次/频次")
                            Spacer()
                            TextField("1", text: $timesPerPeriod)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        
                        Picker("目标类型", selection: $goalType) {
                            Text("坚持").tag(HabitGoalType.perPeriod)
                            Text("定量").tag(HabitGoalType.total)
                        }
                        .pickerStyle(.segmented)
                        
                        if goalType == .total {
                            HStack {
                                Text("总目标数量")
                                Spacer()
                                TextField("例如：100", text: $totalTarget)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                            }
                        }
                    }
                } else {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(.primary)
                                .font(.title3)
                            
                            Text("记忆曲线：根据艾宾浩斯遗忘曲线自动规划复习时间。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section("提醒") {
                    Toggle("按执行日提醒", isOn: $isReminderEnabled)
                    
                    if isReminderEnabled {
                        DatePicker("提醒时间", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                }
            }
            .disabled(isAILoading || isSaving)
            
            if isAILoading || isSaving {
                Color.black.opacity(0.12).ignoresSafeArea()
                ProgressView().controlSize(.large)
            }
        }
        .navigationTitle(embedsInParentNavigationStack ? "" : navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .optionalTint(themeStore.switchTint)
        .toolbar {
            if let principalToolbarContent {
                ToolbarItem(placement: .principal) {
                    principalToolbarContent
                }
            }

            if !embedsInParentNavigationStack {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: { Image(systemName: "xmark") }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        _Concurrency.Task { await save() }
                    } label: { Image(systemName: "checkmark") }
                    .disabled(!isSaveEnabled)
                    .buttonStyle(.glassProminent)
                    .tint(themeStore.accentColor)
                }
            }
        }
        .alert("提示", isPresented: $showAlert, actions: {
            Button("确定", role: .cancel) {}
        }, message: {
            Text(alertMessage ?? "")
        })
        .sheet(isPresented: $showPaywall) {
            ProPaywallView()
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(selectedUID: $selectedCategoryUID) {
                _Concurrency.Task { await loadCategories() }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: saveTrigger) { oldValue, newValue in
            guard embedsInParentNavigationStack, newValue != oldValue else { return }
            _Concurrency.Task { await save() }
        }
        .onAppear {
            onSaveEnabledChange?(isSaveEnabled)
            guard autoRunAIOnAppear else { return }
            guard !isAILoading else { return }
            guard !aiInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            _Concurrency.Task { await onAITriggered() }
        }
        .task {
            await loadCategories()
        }
        .onChange(of: name) { _, _ in
            onSaveEnabledChange?(isSaveEnabled)
        }
        .onChange(of: isSaving) { _, _ in
            onSaveEnabledChange?(isSaveEnabled)
        }
        .onChange(of: isAILoading) { _, _ in
            onSaveEnabledChange?(isSaveEnabled)
        }
    }
    
    private var navigationTitle: String {
        switch mode {
        case .add: return "创建新习惯"
        case .edit: return "编辑习惯"
        }
    }

    private var isSaveEnabled: Bool {
        !isSaving && !isAILoading && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var categorySelectionLabel: some View {
        Group {
            if let selectedCategoryUID,
               let category = categories.first(where: { $0.uid == selectedCategoryUID }) {
                CategoryBadgeView(badge: CategoryBadgeModel(category: category), showsTitle: true)
            } else {
                Label("不分类", systemImage: "tag.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - AI
    @MainActor
    private func onAITriggered() async {
        let text = aiInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { showToast("请输入内容后再尝试"); return }
        
        isAILoading = true
        defer { isAILoading = false }
        
        do {
            let habits = try await KMPLifiCoreBridge.shared.extractHabits(text)
            guard let firstHabit = habits.first else {
                showToast("未能从文本中识别出习惯内容哦")
                return
            }
            
            name = firstHabit.name
            period = HabitPeriod(rawValue: firstHabit.period.uppercased()) ?? .daily
            weekdaysMask = firstHabit.weekdaysMask ?? HabitWeekdaySelection.allDaysMask
            timesPerPeriod = String(firstHabit.timesPerPeriod)
            goalType = HabitGoalType(rawValue: firstHabit.goalType.uppercased()) ?? .perPeriod
            if let total = firstHabit.totalTarget {
                totalTarget = String(total)
            }

            if let alarmTime = firstHabit.alarmTime,
               let parsedTime = Self.parseAlarmTime(alarmTime) {
                isReminderEnabled = true
                reminderTime = parsedTime
            }
            
            showToast("✨ AI 解析完成")
            aiInputText = ""
            
        } catch {
            showToast("抱歉，AI 解析失败：\(error.localizedDescription)")
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = text
            }
        }
    }
    
    // MARK: - Save
    @MainActor
    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { showToast("请输入习惯名称"); return }
        
        isSaving = true
        defer { isSaving = false }
        
        let alarmStr: String? = {
            if isReminderEnabled {
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                return f.string(from: reminderTime)
            }
            return nil
        }()
        
        do {
            switch mode {
            case .add:
                _ = try await habitRepository.createHabitWithCarrier(
                    name: trimmedName,
                    period: period,
                    weekdaysMask: weekdaysMask,
                    timesPerPeriod: Int(timesPerPeriod) ?? 1,
                    goalType: goalType,
                    totalTarget: goalType == .total ? (Int(totalTarget) ?? 100) : nil,
                    description: description,
                    color: nil,
                    iconKey: nil,
                    categoryUID: selectedCategoryUID,
                    sortOrder: 0,
                    alarmTime: alarmStr
                )
                
                showToast("创建成功")
                onSaved?()
                onDone?()
                dismiss()
                
            case .edit(let original):
                var updatedHabit = original
                updatedHabit.name = trimmedName
                updatedHabit.description = description
                updatedHabit.period = period
                updatedHabit.weekdaysMask = weekdaysMask
                updatedHabit.timesPerPeriod = Int(timesPerPeriod) ?? 1
                updatedHabit.goalType = goalType
                updatedHabit.totalTarget = goalType == .total ? (Int(totalTarget) ?? 100) : nil
                updatedHabit.alarmTime = alarmStr
                updatedHabit.categoryUID = selectedCategoryUID
                
                try await habitRepository.updateHabit(updatedHabit)
                
                showToast("保存成功")
                onSaved?()
                onDone?()
                dismiss()
            }
        } catch {
            showToast("保存失败：\(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func showToast(_ msg: String) {
        alertMessage = msg
        showAlert = true
    }

    @MainActor
    private func loadCategories() async {
        do {
            categories = try await PersistenceStores.categories.allCategories()
        } catch {
            print("HabitEditorSheetView category reload failed: \(error)")
            // Keep existing category cache on transient failures.
        }
    }
}

private struct HabitWeekdaySelection: View {
    static let allDaysMask = 0b1111111
    private static let workdaysMask = 0b0011111
    private static let weekendMask = 0b1100000

    @Binding var mask: Int

    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("常用", selection: presetSelection) {
                Text("每天").tag(Self.allDaysMask)
                Text("工作日").tag(Self.workdaysMask)
                Text("周末").tag(Self.weekendMask)
                Text("自定义").tag(0)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                ForEach(weekdays.indices, id: \.self) { index in
                    let selected = contains(index)
                    Button {
                        toggle(index)
                    } label: {
                        Text(weekdays[index])
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? Color.accentColor : Color.secondary.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("周\(weekdays[index])")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            Text("提醒与打卡只会在选中的日期生效")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var presetSelection: Binding<Int> {
        Binding(
            get: {
                switch mask {
                case Self.allDaysMask, Self.workdaysMask, Self.weekendMask: mask
                default: 0
                }
            },
            set: { selected in
                guard selected != 0 else { return }
                mask = selected
            }
        )
    }

    private func contains(_ index: Int) -> Bool {
        mask & (1 << index) != 0
    }

    private func toggle(_ index: Int) {
        let updated = mask ^ (1 << index)
        guard updated != 0 else { return }
        mask = updated
    }
}
