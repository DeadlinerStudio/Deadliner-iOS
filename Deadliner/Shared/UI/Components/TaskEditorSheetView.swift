//
//  TaskEditorSheetView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/1.
//

import SwiftUI

// UI 可编辑字段集合（避免 DDLItem 直接塞进 init 导致 @State 初始化麻烦）
struct TaskDraft: Equatable {
    var name: String
    var note: String
    var startTime: Date
    var endTime: Date
    var isStarred: Bool

    static func empty() -> TaskDraft {
        .init(
            name: "",
            note: "",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            isStarred: false
        )
    }

    static func fromDDL(_ item: DDLItem) -> TaskDraft {
        .init(
            name: item.name,
            note: item.note,
            startTime: DeadlineDateParser.safeParseOptional(item.startTime) ?? Date(),
            endTime: DeadlineDateParser.safeParseOptional(item.endTime) ?? Date().addingTimeInterval(3600),
            isStarred: item.isStared
        )
    }
}

enum TaskSheetMode: Equatable {
    case add
    case edit(original: DDLItem)
}

struct TaskEditorSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("settings.ai.enabled") private var aiEnabled: Bool = true

    let repository: TaskRepository
    let mode: TaskSheetMode
    var onDone: (() -> Void)? = nil

    // ===== UI States（保持与你现在完全一致）=====
    @State private var name: String
    @State private var note: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var isStarred: Bool

    @State private var aiInputText: String = ""
    @State private var isAILoading: Bool = false
    @State private var isSaving: Bool = false

    @State private var alertMessage: String?
    @State private var showAlert: Bool = false

    init(
        repository: TaskRepository,
        mode: TaskSheetMode,
        initialDraft: TaskDraft = .empty(),
        onDone: (() -> Void)? = nil
    ) {
        self.repository = repository
        self.mode = mode
        self.onDone = onDone

        _name = State(initialValue: initialDraft.name)
        _note = State(initialValue: initialDraft.note)
        _startTime = State(initialValue: initialDraft.startTime)
        _endTime = State(initialValue: initialDraft.endTime)
        _isStarred = State(initialValue: initialDraft.isStarred)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    if aiEnabled {
                        Section("AI 快速添加") {
                            HStack(spacing: 8) {
                                TextField("询问 AI 以快速添加任务...", text: $aiInputText, axis: .vertical)
                                    .lineLimit(1...3)

                                Button("解析") {
                                    Task { await onAITriggered() }
                                }
                                .disabled(isAILoading || aiInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }

                    Section("基础信息") {
                        TextField("任务名称", text: $name)
                        TextField("备注（可选）", text: $note, axis: .vertical)
                            .lineLimit(2...5)

                        Toggle("星标", isOn: $isStarred)
                    }

                    Section("时间") {
                        DatePicker("开始时间", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("截止时间", selection: $endTime, displayedComponents: [.date, .hourAndMinute])
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
                        onDone?()
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
        case .add: return "创建新任务"
        case .edit: return "编辑任务"
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
            let tasks = try await AIService.shared.extractTasks(text: text)
            guard let firstTask = tasks.first else {
                showToast("未能从文本中识别出任务内容哦")
                return
            }

            let isEdit = {
                if case .edit = mode { return true }
                return false
            }()

            if !isEdit || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = firstTask.name
            }
            if let noteStr = firstTask.note, !noteStr.isEmpty {
                if !isEdit || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    note = noteStr
                }
            }

            if let dueString = firstTask.dueTime,
               let parsedDate = DeadlineDateParser.parseAIGeneratedDate(dueString, debugLog: true) {

                endTime = parsedDate
                if startTime >= parsedDate {
                    startTime = parsedDate.addingTimeInterval(-3600)
                }
            } else {
                print("❌ [AI 调试] dueTime 为空或解析失败：'\(firstTask.dueTime ?? "nil")'")
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { showToast("请输入任务名称"); return }

        if endTime < startTime {
            showToast("截止时间不能早于开始时间")
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            switch mode {
            case .add:
                let params = DDLInsertParams(
                    name: trimmed,
                    startTime: startTime.toLocalISOString(),
                    endTime: endTime.toLocalISOString(),
                    isCompleted: false,
                    completeTime: "",
                    note: note,
                    isArchived: false,
                    isStared: isStarred,
                    type: .task,
                    calendarEventId: nil
                )

                let ddlId = try await repository.insertDDL(params)
                if let newItem = try await repository.getDDLById(ddlId) {
                    NotificationManager.shared.scheduleTaskNotification(for: newItem)
                }
                
                showToast("创建成功")
                onDone?()
                dismiss()

            case .edit(let original):
                var updated = original
                updated.name = trimmed
                updated.note = note
                updated.startTime = startTime.toLocalISOString()
                updated.endTime = endTime.toLocalISOString()
                updated.isStared = isStarred

                try await repository.updateDDL(updated)
                NotificationManager.shared.scheduleTaskNotification(for: updated)
                
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
