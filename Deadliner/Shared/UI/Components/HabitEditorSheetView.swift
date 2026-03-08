//
//  HabitEditorSheetView.swift
//  Deadliner
//
//  Created by Gemini CLI on 2026/3/7.
//

import SwiftUI

struct HabitDraft: Equatable {
    var name: String
    var description: String
    var period: HabitPeriod
    var goalType: HabitGoalType
    var timesPerPeriod: String
    var totalTarget: String

    static func empty() -> HabitDraft {
        .init(
            name: "",
            description: "",
            period: .daily,
            goalType: .perPeriod,
            timesPerPeriod: "1",
            totalTarget: "100"
        )
    }

    static func fromHabit(_ h: Habit) -> HabitDraft {
        .init(
            name: h.name,
            description: h.description ?? "",
            period: h.period,
            goalType: h.goalType,
            timesPerPeriod: String(h.timesPerPeriod),
            totalTarget: String(h.totalTarget ?? 100)
        )
    }
}

enum HabitSheetMode: Equatable {
    case add
    case edit(original: Habit)
}

struct HabitEditorSheetView: View {
    @Environment(\.dismiss) private var dismiss
    
    let taskRepository: TaskRepository = .shared
    let habitRepository: HabitRepository = .shared
    let mode: HabitSheetMode
    var onDone: (() -> Void)? = nil
    
    // ===== UI States =====
    @State private var name: String
    @State private var description: String
    @State private var period: HabitPeriod
    @State private var goalType: HabitGoalType
    @State private var timesPerPeriod: String
    @State private var totalTarget: String
    
    @State private var aiInputText: String = ""
    @State private var isAILoading: Bool = false
    @State private var isSaving: Bool = false
    
    @State private var alertMessage: String?
    @State private var showAlert: Bool = false
    
    init(
        mode: HabitSheetMode,
        initialDraft: HabitDraft = .empty(),
        onDone: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onDone = onDone
        
        _name = State(initialValue: initialDraft.name)
        _description = State(initialValue: initialDraft.description)
        _period = State(initialValue: initialDraft.period)
        _goalType = State(initialValue: initialDraft.goalType)
        _timesPerPeriod = State(initialValue: initialDraft.timesPerPeriod)
        _totalTarget = State(initialValue: initialDraft.totalTarget)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section("AI 快速添加") {
                        HStack(spacing: 8) {
                            TextField("例如：每天背20个单词...", text: $aiInputText, axis: .vertical)
                                .lineLimit(1...3)
                            
                            Button("解析") {
                                Task { await onAITriggered() }
                            }
                            .disabled(isAILoading || aiInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    
                    Section("基础信息") {
                        TextField("要做什么？", text: $name)
                        TextField("备注（可选）", text: $description, axis: .vertical)
                            .lineLimit(2...5)
                    }
                    
                    Section("类型 / 周期") {
                        Picker("周期", selection: $period) {
                            Text("每日").tag(HabitPeriod.daily)
                            Text("每周").tag(HabitPeriod.weekly)
                            Text("每月").tag(HabitPeriod.monthly)
                            Text("艾宾浩斯").tag(HabitPeriod.ebbinghaus)
                        }
                        .pickerStyle(.segmented)
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
                }
                .disabled(isAILoading || isSaving)
                
                if isAILoading || isSaving {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView().controlSize(.large)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: { Image(systemName: "xmark") }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: { Image(systemName: "checkmark") }
                    .disabled(isSaving || isAILoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.glassProminent)
                }
            }
            .alert("提示", isPresented: $showAlert, actions: {
                Button("确定", role: .cancel) {}
            }, message: {
                Text(alertMessage ?? "")
            })
        }
    }
    
    private var navigationTitle: String {
        switch mode {
        case .add: return "创建新习惯"
        case .edit: return "编辑习惯"
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
            let habits = try await AIService.shared.extractHabits(text: text)
            guard let firstHabit = habits.first else {
                showToast("未能从文本中识别出习惯内容哦")
                return
            }
            
            name = firstHabit.name
            
            // 解析周期
            if let p = HabitPeriod(rawValue: firstHabit.period.uppercased()) {
                period = p
            } else if firstHabit.period.contains("艾宾浩斯") {
                period = .ebbinghaus
            }
            
            timesPerPeriod = String(firstHabit.timesPerPeriod)
            
            // 解析目标类型
            if let g = HabitGoalType(rawValue: firstHabit.goalType.uppercased()) {
                goalType = g
            }
            
            if let total = firstHabit.totalTarget {
                totalTarget = String(total)
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
        
        do {
            switch mode {
            case .add:
                // 1. 先创建一个 DDLItem 作为载体
                let ddlParams = DDLInsertParams(
                    name: trimmedName,
                    startTime: Date().toLocalISOString(),
                    endTime: "", // 习惯通常没有明确截止时间
                    isCompleted: false,
                    completeTime: "",
                    note: description,
                    isArchived: false,
                    isStared: false,
                    type: .habit,
                    calendarEventId: nil
                )
                
                let ddlId = try await taskRepository.insertDDL(ddlParams)
                
                // 2. 创建 Habit 本体
                _ = try await habitRepository.createHabitForDdl(
                    ddlId: ddlId,
                    name: trimmedName,
                    period: period,
                    timesPerPeriod: Int(timesPerPeriod) ?? 1,
                    goalType: goalType,
                    totalTarget: goalType == .total ? (Int(totalTarget) ?? 100) : nil,
                    description: description
                )
                
                showToast("创建成功")
                onDone?()
                dismiss()
                
            case .edit(let original):
                // 1. 更新 Habit
                var updatedHabit = original
                updatedHabit.name = trimmedName
                updatedHabit.description = description
                updatedHabit.period = period
                updatedHabit.timesPerPeriod = Int(timesPerPeriod) ?? 1
                updatedHabit.goalType = goalType
                updatedHabit.totalTarget = goalType == .total ? (Int(totalTarget) ?? 100) : nil
                
                try await habitRepository.updateHabit(updatedHabit)
                
                // 2. 更新关联的 DDLItem
                // 习惯的显示和管理主要依赖于其载体 DDLItem 的元数据，因此我们也要同步更新 DDLItem 的 name 和 note
                let allDDLs = try await taskRepository.getAllDDLs()
                if let originalDDL = allDDLs.first(where: { $0.id == original.ddlId }) {
                    var updatedDDL = originalDDL
                    updatedDDL.name = trimmedName
                    updatedDDL.note = description
                    try await taskRepository.updateDDL(updatedDDL)
                }
                
                showToast("保存成功")
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
}
