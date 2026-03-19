//
//  AIFunctionView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/22.
//

import SwiftUI

// MARK: - 对话流模型（稳定 id）
struct DisplayItem: Identifiable {
    enum Kind {
        case userQuery(String)
        case aiChat(String)
        case aiThinking(String)
        case aiTask(AITask)
        case aiHabit(AIHabit)
        case aiMemory(String)
        case aiToolRequest(AIToolRequest)
        case aiToolResult(AIToolResult)
    }

    let id: UUID
    let kind: Kind

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .aiToolRequest(let r): self.id = UUID(uuidString: r.id) ?? UUID()
        case .aiToolResult(let r): self.id = UUID(uuidString: r.id) ?? UUID()
        default: self.id = UUID()
        }
    }
}

struct AIFunctionView: View {
    let userTier: UserTier

    // 状态控制
    @State private var inputText: String = ""
    @State private var isParsing = false
    @State private var isExpanded = false

    @State private var displayItems: [DisplayItem] = []

    @State private var errorMessage: String?
    @State private var showErrorMessage = false
    
    @State private var sessionSummary: String = ""
    @StateObject private var memoryBank = MemoryBank.shared
    
    @State private var pendingTaskToCreate: AITask?
    @State private var showCreateTaskDialog: Bool = false

    @State private var pendingHabitToCreate: AIHabit?
    @State private var showCreateHabitDialog: Bool = false
    
    @State private var pendingToolRequest: AIToolRequest?
    @State private var toolOriginalUserText: String = ""
    @State private var submittedToolRequestIDs: Set<String> = []
    @State private var pendingMemoryNoticeTask: Task<Void, Never>?

    @State private var addedTaskKeys: Set<String> = []      // 用于把卡片变“已添加”
    @State private var addedHabitKeys: Set<String> = []

    @State private var repoBusy: Bool = false               // 防连点
    
    @State private var showMemoryManageSheet: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if isExpanded || !displayItems.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 16) {
                                    memoryHintView

                                    ForEach(displayItems) { item in
                                        renderItem(item)
                                            .id(item.id)
                                            .transition(.asymmetric(
                                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity
                                            ))
                                    }

                                    if isParsing {
                                        HStack(spacing: 12) {
                                            ProgressView().tint(.purple)
                                            Text("Deadliner Claw 正在思考...")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                        }
                                        .padding(.leading)
                                        .id("loading_indicator")
                                    }
                                }
                                .padding()
                            }
                            .onChange(of: displayItems.count) { _ in
                                guard let lastId = displayItems.last?.id else { return }
                                withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                            }
                            .onChange(of: isParsing) { parsing in
                                if parsing {
                                    withAnimation { proxy.scrollTo("loading_indicator", anchor: .bottom) }
                                }
                            }
                        }
                    } else {
                        initialGuideView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                inputSection
            }
            .navigationTitle(isExpanded ? "Deadliner Claw" : "")
            .navigationBarTitleDisplayMode(.inline)
        }
        // 根据是否展开自动调整 Sheet 高度
        .presentationDetents(isExpanded ? [.large] : [.medium, .large])
        .alert("出错了", isPresented: $showErrorMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .confirmationDialog(
            "确认创建任务？",
            isPresented: $showCreateTaskDialog,
            titleVisibility: .visible
        ) {
            Button("创建任务", role: .none) {
                guard let t = pendingTaskToCreate else { return }
                Task { await createTaskFromProposal(t) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let t = pendingTaskToCreate {
                Text(makeTaskConfirmMessage(t))
            }
        }
        .confirmationDialog(
            "确认开启习惯？",
            isPresented: $showCreateHabitDialog,
            titleVisibility: .visible
        ) {
            Button("开启习惯", role: .none) {
                guard let h = pendingHabitToCreate else { return }
                Task { await createHabitFromProposal(h) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let h = pendingHabitToCreate {
                Text("习惯：\(h.name)\n频率：\(h.period) / \(h.timesPerPeriod) 次")
            }
        }
        .sheet(isPresented: $showMemoryManageSheet) {
            MemoryManageSheet()
        }
        .task {
            await DeadlinerCoreBridge.shared.initializeIfNeeded()
            DeadlinerCoreBridge.shared.setEventHandler { event in
                handleCoreEvent(event)
            }
        }
        .onDisappear {
            DeadlinerCoreBridge.shared.clearEventHandler()
        }
    }
}

// MARK: - UI 渲染组件
extension AIFunctionView {

    @ViewBuilder
    private func renderItem(_ item: DisplayItem) -> some View {
        switch item.kind {
        case .userQuery(let text):
            userBubble(text: text)
        case .aiChat(let text):
            chatBubble(text: text)
        case .aiThinking(let text):
            thinkingBubble(text: text)
        case .aiTask(let task):
            proposalCard(task: task)
        case .aiHabit(let habit):
            habitCard(habit: habit)
        case .aiMemory(let content):
            memoryCapturedBubble(content: content)
        case .aiToolRequest(let req):
            toolRequestCard(req)
        case .aiToolResult(let res):
            toolResultBubble(res)
        }
    }

    private func userBubble(text: String) -> some View {
        HStack {
            Spacer()
            Text(text)
                .padding(12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(16, corners: [.topLeft, .topRight, .bottomLeft])
        }
    }

    private func chatBubble(text: String) -> some View {
        HStack {
            Text(text)
                .padding(12)
                .background(Color(uiColor: .secondarySystemFill))
                .foregroundColor(.primary)
                .cornerRadius(16, corners: [.topLeft, .topRight, .bottomRight])
            Spacer()
        }
    }

    private func thinkingBubble(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundColor(.blue)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.06))
        .cornerRadius(10)
    }

    private func memoryCapturedBubble(content: String) -> some View {
        HStack {
            Image(systemName: "brain.head.profile.fill")
                .foregroundColor(.purple)
                .font(.caption)
            Text("记住了：\(content)")
                .font(.caption)
                .italic()
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(10)
    }

    private func proposalCard(task: AITask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill").foregroundColor(.blue)
                Text("识别到任务").font(.caption.bold()).foregroundColor(.secondary)
            }
            Text(task.name).font(.headline)
            if let due = task.dueTime, !due.isEmpty {
                Text(due).font(.subheadline).foregroundColor(.blue)
            }
            
            let taskKey = makeTaskKey(task)

            Button(action: {
                pendingTaskToCreate = task
                showCreateTaskDialog = true
            }) {
                Text(addedTaskKeys.contains(taskKey) ? "已添加" : "确认添加")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(addedTaskKeys.contains(taskKey) ? Color.gray.opacity(0.4) : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(addedTaskKeys.contains(taskKey) || repoBusy)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }

    private func habitCard(habit: AIHabit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(.purple)
                Text("识别到习惯").font(.caption.bold()).foregroundColor(.secondary)
            }
            Text(habit.name).font(.headline)
            Text("\(habit.period) / \(habit.timesPerPeriod)次")
                .font(.subheadline)
                .foregroundColor(.purple)

            let habitKey = makeHabitKey(habit)

            Button(action: {
                pendingHabitToCreate = habit
                showCreateHabitDialog = true
            }) {
                Text(addedHabitKeys.contains(habitKey) ? "已开启" : "开启习惯")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(addedHabitKeys.contains(habitKey) ? Color.gray.opacity(0.4) : Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(addedHabitKeys.contains(habitKey) || repoBusy)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
    
    private func toolRequestCard(_ req: AIToolRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "tray.full.fill").foregroundColor(.orange)
                Text("需要读取任务列表").font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
            }

            if let r = req.reason, !r.isEmpty {
                Text(r)
                    .font(.callout)
                    .foregroundColor(.primary)
            } else {
                Text("为了回答你的问题，我需要查看你近期的任务。")
                    .font(.callout)
                    .foregroundColor(.primary)
            }

            // 查询范围摘要（先只展示，不做编辑 UI；编辑后面再加）
            let days = req.args.timeRangeDays ?? 7
            let status = req.args.status ?? "OPEN"
            let kws = (req.args.keywords ?? []).joined(separator: "、")
            Text("范围：未来 \(days) 天 · 状态：\(status)\(kws.isEmpty ? "" : " · 关键词：\(kws)")")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button(role: .cancel) {
                    withAnimation(.spring()) {
                        displayItems.append(DisplayItem(kind: .aiChat("好的，我不读取任务列表。你可以告诉我更具体的任务信息，我也能继续帮你。")))
                    }
                } label: {
                    Text("拒绝")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    pendingToolRequest = req
                    Task { await approveAndRunTool(req) }
                } label: {
                    Text("允许一次")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(repoBusy || submittedToolRequestIDs.contains(req.id))
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }

    private func toolResultBubble(_ res: AIToolResult) -> some View {
        let s = res.payload.summary
        return HStack {
            Image(systemName: "checklist")
                .foregroundColor(.orange)
                .font(.caption)

            Text("已读取任务：\(s.count) 条（逾期 \(s.overdue)，24h 内 \(s.dueSoon24h)）")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.06))
        .cornerRadius(10)
    }

    private var inputSection: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField("告诉 Deadliner Claw 你的计划...", text: $inputText, axis: .vertical)
                    .padding(8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                    .lineLimit(1...5)

                Button(action: {
                    print("[AIFunctionView] Send tapped. input=\(inputText)")
                    Task { await runSmartAgent() }
                }) {
                    Image(systemName: isParsing ? "ellipsis" : "arrow.up")
                        .fontWeight(.medium)
                        .padding(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
                .buttonStyle(.glassProminent)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            .padding(.top, 10)
        }
    }

    private var memoryHintView: some View {
        Button {
            showMemoryManageSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                Text("画像: \(memoryBank.userProfile.isEmpty ? "未建立" : "已建立") · 记忆 \(memoryBank.fragments.count) 条")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var initialGuideView: some View {
        ViewThatFits(in: .vertical) {
            initialGuideViewRegular
            initialGuideViewCompact
        }
    }
    
    private var initialGuideViewRegular: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 78, height: 78)

                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
                    )
            }

            Text("Deadliner Claw")
                .font(.title3.weight(.semibold))

            Text("一句话生成任务 / 习惯 / 记忆")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                quickRow("创建任务", "明天 19:00 交系统论作业", icon: "checklist") {
                    applyQuickPrompt("明天 19:00 交系统论作业")
                }
                quickRow("创建习惯", "每周 3 次 跑步 30 分钟", icon: "arrow.triangle.2.circlepath") {
                    applyQuickPrompt("每周 3 次 跑步 30 分钟")
                }
                quickRow("记住偏好", "以后任务时间用 24 小时制", icon: "brain.head.profile") {
                    applyQuickPrompt("记住：以后任务时间用 24 小时制输出")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
    
    private var initialGuideViewCompact: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 78, height: 78)

                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
                    )
            }

            Text("有什么我可以帮你的？")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 10) {
                quickChip("创建任务", icon: "checklist") {
                    applyQuickPrompt("明天 19:00 交系统论作业")
                }
                quickChip("创建习惯", icon: "arrow.triangle.2.circlepath") {
                    applyQuickPrompt("每周 3 次 跑步 30 分钟")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
    
    @MainActor
    private func applyQuickPrompt(_ text: String) {
        // 保持 medium：不要强制 isExpanded=true
        inputText = text
    }

    private func quickChip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func quickRow(_ title: String, _ subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 业务逻辑
extension AIFunctionView {

    @MainActor
    private func runSmartAgent() async {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        withAnimation(.spring()) {
            isExpanded = true
            isParsing = true
            displayItems.append(DisplayItem(kind: .userQuery(query)))
            inputText = ""
        }

        toolOriginalUserText = query
        await DeadlinerCoreBridge.shared.processInput(query)
    }
    
    @MainActor
    private func createTaskFromProposal(_ task: AITask) async {
        if repoBusy { return }
        repoBusy = true
        defer { repoBusy = false }

        do {
            let params = try makeDDLInsertParams(from: task)

            _ = try await TaskRepository.shared.insertDDL(params)

            let key = makeTaskKey(task)
            addedTaskKeys.insert(key)

            withAnimation(.spring()) {
                displayItems.append(DisplayItem(kind: .aiChat("已添加任务：\(task.name)")))
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorMessage = true
        }
    }

    @MainActor
    private func createHabitFromProposal(_ habit: AIHabit) async {
        if repoBusy { return }
        repoBusy = true
        defer { repoBusy = false }

        do {
            // 1. 先创建一个 DDLItem 作为载体 (类型为 .habit)
            let ddlParams = DDLInsertParams(
                name: habit.name,
                startTime: Date().toLocalISOString(),
                endTime: "", // 习惯通常没有明确截止时间
                isCompleted: false,
                completeTime: "",
                note: "",
                isArchived: false,
                isStared: false,
                type: .habit,
                calendarEventId: nil
            )
            
            let ddlId = try await TaskRepository.shared.insertDDL(ddlParams)
            
            // 2. 解析周期与目标类型
            let periodEnum = HabitPeriod(rawValue: habit.period.uppercased()) ?? .daily
            let goalTypeEnum = HabitGoalType(rawValue: habit.goalType.uppercased()) ?? .perPeriod
            
            // 3. 创建 Habit 本体
            _ = try await HabitRepository.shared.createHabitForDdl(
                ddlId: ddlId,
                name: habit.name,
                period: periodEnum,
                timesPerPeriod: habit.timesPerPeriod,
                goalType: goalTypeEnum,
                totalTarget: habit.totalTarget,
                description: ""
            )

            let key = makeHabitKey(habit)
            addedHabitKeys.insert(key)

            withAnimation(.spring()) {
                displayItems.append(DisplayItem(kind: .aiChat("已开启习惯：\(habit.name)")))
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorMessage = true
        }
    }
    
    private func makeTaskKey(_ task: AITask) -> String {
        // 你也可以换成 task.id（如果 AITask 有）
        let due = (task.dueTime?.isEmpty == false) ? task.dueTime! : "none"
        return "\(task.name)#\(due)"
    }

    private func makeHabitKey(_ habit: AIHabit) -> String {
        return "\(habit.name)#\(habit.period)#\(habit.timesPerPeriod)"
    }

    private func makeTaskConfirmMessage(_ task: AITask) -> String {
        let due = (task.dueTime?.isEmpty == false) ? task.dueTime! : "无"
        return "任务：\(task.name)\n截止：\(due)"
    }
    
    @MainActor
    private func approveAndRunTool(_ req: AIToolRequest) async {
        if repoBusy { return }
        if submittedToolRequestIDs.contains(req.id) { return }

        submittedToolRequestIDs.insert(req.id)
        repoBusy = true
        isParsing = true
        defer {
            repoBusy = false
        }

        do {
            guard ToolCallExecutor.shared.supports(req.tool) else {
                displayItems.append(DisplayItem(kind: .aiChat("暂不支持的工具：\(req.tool)")))
                isParsing = false
                return
            }

            // 1) 本地查询
            let payload = try await ToolCallExecutor.shared.execute(toolName: req.tool, args: req.args)

            let toolResult = AIToolResult(
                id: req.id,
                tool: ToolCallExecutor.shared.normalizeToolName(req.tool),
                appliedArgs: req.args,
                payload: payload
            )

            withAnimation(.spring()) {
                displayItems.append(DisplayItem(kind: .aiToolResult(toolResult)))
            }

            // 2) 二段回灌给 Rust Core，让它继续产出最终 chat + proposal
            let encoder = JSONEncoder()
            let payloadData = try encoder.encode(payload)
            guard let payloadJson = String(data: payloadData, encoding: .utf8) else {
                throw AIError.parsingFailed
            }
            print("[AIFunctionView] submitToolResult id=\(req.id) tool=\(req.tool) payloadJson=\(payloadJson)")
            await DeadlinerCoreBridge.shared.submitToolResult(id: req.id, resultJson: payloadJson)
        } catch {
            submittedToolRequestIDs.remove(req.id)
            isParsing = false
            errorMessage = error.localizedDescription
            showErrorMessage = true
        }
    }

    @MainActor
    private func handleCoreEvent(_ event: DeadlinerCoreBridgeEvent) {
        switch event {
        case .thinking(let agentName, let phase, let message):
            if phase != "memory" {
                isParsing = true
            }
            let thinkingText = collaborationMessage(for: agentName, phase: phase, fallbackMessage: message)
            if shouldAppendThinkingMessage(thinkingText) {
                withAnimation(.spring()) {
                    displayItems.append(DisplayItem(kind: .aiThinking(thinkingText)))
                }
            }
        case .textStream:
            break
        case .toolRequest(let req):
            isParsing = false
            let sanitizedReq = AIToolRequest(
                id: req.id,
                tool: req.tool,
                args: sanitizeReadTasksArgs(req.args, userQuery: toolOriginalUserText),
                reason: req.reason
            )

            withAnimation(.spring()) {
                displayItems.append(DisplayItem(kind: .aiThinking(toolCollaborationMessage(for: sanitizedReq.tool))))
                displayItems.append(DisplayItem(kind: .aiToolRequest(sanitizedReq)))
            }
        case .finish(let payload):
            isParsing = false
            pendingMemoryNoticeTask?.cancel()
            pendingMemoryNoticeTask = nil

            if let s = payload.sessionSummary, !s.isEmpty {
                sessionSummary = String(s.prefix(600))
            }

            withAnimation(.spring()) {
                for task in payload.tasks {
                    displayItems.append(DisplayItem(kind: .aiTask(task)))
                }
                for habit in payload.habits {
                    displayItems.append(DisplayItem(kind: .aiHabit(habit)))
                }
                if let chat = payload.chatResponse, !chat.isEmpty {
                    displayItems.append(DisplayItem(kind: .aiChat(chat)))
                }
            }
        case .memoryCommitted(let payload):
            isParsing = false
            pendingMemoryNoticeTask?.cancel()
            pendingMemoryNoticeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.spring()) {
                    for notice in payload.notices {
                        displayItems.append(DisplayItem(kind: .aiMemory(notice)))
                    }
                }
            }
        case .error(let message):
            isParsing = false
            pendingMemoryNoticeTask?.cancel()
            pendingMemoryNoticeTask = nil
            errorMessage = message
            showErrorMessage = true
        }
    }
    
    private func sanitizeReadTasksArgs(_ args: ReadTasksArgs, userQuery: String) -> ReadTasksArgs {
        let days = max(1, min(args.timeRangeDays ?? 7, 30))
        let limit = max(1, min(args.limit ?? 20, 50))

        let status = (args.status ?? "OPEN").uppercased()
        let sort = (args.sort ?? "DUE_ASC").uppercased()

        // 1) 先把 AI 的 keywords 清洗
        var kws = (args.keywords ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if kws.count > 3 { kws = Array(kws.prefix(3)) }
        kws = kws.map { String($0.prefix(12)) }

        let q = userQuery.lowercased()
        kws = kws.filter { k in
            let kk = k.lowercased()
            // 简单包含判断足够用（后续你要更强可以做分词）
            return q.contains(kk)
        }

        if isGenericTaskListQuery(userQuery) && !userExplicitlyProvidedTopic(userQuery) {
            kws = []
        }

        return ReadTasksArgs(
            timeRangeDays: days,
            status: status,
            keywords: kws,
            limit: limit,
            sort: sort
        )
    }

    private func collaborationMessage(for agentName: String, phase: String, fallbackMessage: String?) -> String {
        if let fallbackMessage, !fallbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallbackMessage
        }

        switch agentName {
        case "Supervisor":
            switch phase {
            case "routing":
                return "总控代理正在分析请求并分派子任务"
            case "memory":
                return "总控代理正在整理本轮记忆更新"
            default:
                return "总控代理正在协调整体流程"
            }
        case "TaskAgent":
            switch phase {
            case "routing":
                return "任务代理已接手，准备分析时间与待办"
            case "tool_wait":
                return "任务代理正在等待本地任务工具结果"
            default:
                return "任务代理正在整理待办与时间信息"
            }
        case "HabitAgent":
            switch phase {
            case "routing":
                return "习惯代理已接手，准备分析周期性行为"
            case "tool_wait":
                return "习惯代理正在等待工具结果"
            default:
                return "习惯代理正在分析周期性行为"
            }
        case "ChatAgent":
            switch phase {
            case "routing":
                return "聊天代理已接手，准备组织回复"
            case "memory":
                return "聊天代理正在整理回复相关记忆"
            default:
                return "聊天代理正在组织回复与记忆"
            }
        default:
            return "\(agentName) 正在\(phase)阶段协作处理中"
        }
    }

    private func toolCollaborationMessage(for toolName: String) -> String {
        switch toolName {
        case "readTasks", "read_tasks":
            return "任务代理请求读取本地任务列表"
        default:
            return "\(toolName) 工具正在参与协作"
        }
    }

    private func shouldAppendThinkingMessage(_ message: String) -> Bool {
        guard let last = displayItems.last?.kind else { return true }
        switch last {
        case .aiThinking(let previous):
            return previous != message
        default:
            return true
        }
    }
    
    private func isGenericTaskListQuery(_ q: String) -> Bool {
        let s = q.lowercased()
        // 典型泛查询词
        let patterns = ["这周", "本周", "最近", "有哪些任务", "有什么任务", "任务列表", "to do", "todo", "待办", "待办事项", "deadline", "ddl"]
        return patterns.contains { s.contains($0.lowercased()) }
    }

    /// 用户是否显式给了主题：例如“系统论的任务”“关于 BOE 的任务”“BOE 相关任务”
    /// 这里先做最小启发式：包含“关于/相关/的任务/的ddl/的待办/项目”等信号
    private func userExplicitlyProvidedTopic(_ q: String) -> Bool {
        let s = q.lowercased()
        let signals = ["关于", "相关", "的任务", "的ddl", "的待办", "项目", "course", "project"]
        return signals.contains { s.contains($0.lowercased()) }
    }

}

// MARK: - 辅助组件
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}
