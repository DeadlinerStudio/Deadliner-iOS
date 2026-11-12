import SwiftUI

extension AIFunctionView {
    @MainActor
    func handleVoiceTap() async {
        do {
            if speechInput.isRecording {
                try await speechInput.stopRecording()
            } else {
                try await speechInput.startRecording(initialText: inputText)
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorMessage = true
        }
    }
}

// MARK: - 业务逻辑
extension AIFunctionView {

    @MainActor
    func runSmartAgent() async {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isParsing, pendingToolRequest == nil else { return }
        AILog.log("[Lifi] input submitted")
        isInputFocused = false

        withAnimation(.spring()) {
            isExpanded = true
            isParsing = true
            displayItems.append(DisplayItem(kind: .userQuery(query)))
            inputText = ""
        }

        toolOriginalUserText = query
        await KMPLifiCoreBridge.shared.processInput(query)
    }

    @MainActor
    func createTaskFromProposal(_ task: AITask) async {
        if repoBusy { return }
        repoBusy = true
        defer { repoBusy = false }

        do {
            let params = try makeTaskInsertParams(from: task)

            let insertedId = try await PersistenceStores.tasks.createTask(params)

            let key = makeTaskKey(task)
            addedTaskKeys.insert(key)
            createdTaskIDsByKey[key] = insertedId

            withAnimation(.spring()) {
                displayItems.append(DisplayItem(kind: .aiChat("已添加任务：\(task.name)")))
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorMessage = true
        }
    }

    @MainActor
    func createHabitFromProposal(_ habit: AIHabit) async {
        if repoBusy { return }
        repoBusy = true
        defer { repoBusy = false }

        do {
            let periodEnum = HabitPeriod(rawValue: habit.period.uppercased()) ?? .daily
            let goalTypeEnum = HabitGoalType(rawValue: habit.goalType.uppercased()) ?? .perPeriod
            let habitID = try await PersistenceStores.habits.createHabitWithCarrier(
                name: habit.name,
                period: periodEnum,
                weekdaysMask: 127,
                timesPerPeriod: habit.timesPerPeriod,
                goalType: goalTypeEnum,
                totalTarget: habit.totalTarget,
                description: "",
                color: nil,
                iconKey: nil,
                categoryUID: nil,
                sortOrder: 0,
                alarmTime: nil
            ).habitUID

            let key = makeHabitKey(habit)
            addedHabitKeys.insert(key)
            createdHabitDdlIDsByKey[key] = habitID

            withAnimation(.spring()) {
                displayItems.append(DisplayItem(kind: .aiChat("已开启习惯：\(habit.name)")))
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorMessage = true
        }
    }

    func makeTaskKey(_ task: AITask) -> String {
        // 你也可以换成 task.id（如果 AITask 有）
        let due = (task.dueTime?.isEmpty == false) ? task.dueTime! : "none"
        return "\(task.name)#\(due)"
    }

    func makeHabitKey(_ habit: AIHabit) -> String {
        let goal = habit.goalType.uppercased()
        let total = habit.totalTarget.map(String.init) ?? "none"
        return "\(habit.name)#\(habit.period)#\(habit.timesPerPeriod)#\(goal)#\(total)"
    }

    @MainActor
    func undoTaskFromProposal(_ task: AITask) async {
        if repoBusy { return }
        let key = makeTaskKey(task)
        guard let taskId = createdTaskIDsByKey[key] else { return }

        repoBusy = true
        defer { repoBusy = false }

        do {
            try await PersistenceStores.tasks.deleteTask(id: taskId)
            addedTaskKeys.remove(key)
            createdTaskIDsByKey.removeValue(forKey: key)
            withAnimation(.spring()) {
                displayItems.append(DisplayItem(kind: .aiChat("已撤回任务：\(task.name)")))
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorMessage = true
        }
    }

    @MainActor
    func undoHabitFromProposal(_ habit: AIHabit) async {
        if repoBusy { return }
        let key = makeHabitKey(habit)
        guard let ddlId = createdHabitDdlIDsByKey[key] else { return }

        repoBusy = true
        defer { repoBusy = false }

        do {
            try await PersistenceStores.habits.deleteHabit(carrierID: ddlId)
            addedHabitKeys.remove(key)
            createdHabitDdlIDsByKey.removeValue(forKey: key)
            withAnimation(.spring()) {
                displayItems.append(DisplayItem(kind: .aiChat("已撤回习惯：\(habit.name)")))
            }
        } catch {
            errorMessage = error.localizedDescription
            showErrorMessage = true
        }
    }

    @MainActor
    func stopActiveLifiRun() async {
        pendingReadTasksApprovalRequest = nil
        showReadTasksApprovalDialog = false
        pendingToolRequest = nil
        await KMPLifiCoreBridge.shared.cancelRun()
        isParsing = false
    }

    @MainActor
    func approveAndRunTool(_ req: AIToolRequest) async {
        if repoBusy { return }
        if submittedToolRequestIDs.contains(req.id) { return }

        submittedToolRequestIDs.insert(req.id)
        repoBusy = true
        isParsing = true
        defer {
            repoBusy = false
            if let next = pendingToolRequest, next.id != req.id, !submittedToolRequestIDs.contains(next.id) {
                Task { await approveAndRunTool(next) }
            }
        }

        guard ToolCallExecutor.shared.supports(req.tool) else {
            displayItems.append(DisplayItem(kind: .aiChat("暂不支持的工具：\(req.tool)")))
            isParsing = false
            return
        }

        // 1) 本地执行 ToolCallAdapter
        let execution = await KMPLifiCoreBridge.shared.executeToolRequest(req)
        AILog.log("[ToolResult] tool=\(execution.normalizedToolName)")
        lastSubmittedToolName = execution.normalizedToolName

        let toolResult = AIToolResult(
            id: req.id,
            tool: execution.normalizedToolName,
            requestArgsJson: req.argsJson,
            resultJson: execution.resultJson,
            displayMessage: execution.displayMessage
        )

        withAnimation(.spring()) {
            displayItems.append(DisplayItem(kind: .aiToolResult(toolResult)))

        }

        // 2) 回灌给 KMP LiFi，让其继续下一阶段
        AILog.log("[Lifi] submitToolResult")
        await KMPLifiCoreBridge.shared.submitToolResult(
            id: req.id,
            tool: execution.normalizedToolName,
            resultJson: execution.resultJson
        )
    }

    @MainActor
    func autoCreateHabitsFromProposals(_ proposals: [AIHabit]) async {
        guard !proposals.isEmpty else { return }
        var successCount = 0
        for proposal in proposals {
            let key = makeHabitKey(proposal)
            do {
                let periodEnum = HabitPeriod(rawValue: proposal.period.uppercased()) ?? .daily
                let goalTypeEnum = HabitGoalType(rawValue: proposal.goalType.uppercased()) ?? .perPeriod
                let habitID = try await PersistenceStores.habits.createHabitWithCarrier(
                    name: proposal.name,
                    period: periodEnum,
                    weekdaysMask: 127,
                    timesPerPeriod: proposal.timesPerPeriod,
                    goalType: goalTypeEnum,
                    totalTarget: proposal.totalTarget,
                    description: "",
                    color: nil,
                    iconKey: nil,
                    categoryUID: nil,
                    sortOrder: 0,
                    alarmTime: nil
                ).habitUID
                addedHabitKeys.insert(key)
                createdHabitDdlIDsByKey[key] = habitID
                successCount += 1
            } catch {
                continue
            }
        }
        if successCount > 0 {
            withAnimation(.spring()) {
                displayItems.append(DisplayItem(kind: .aiChat("已静默添加 \(successCount) 条习惯。若有误可点“撤回”。")))
            }
        }
    }

    @MainActor
    func handleCoreEvent(_ event: KMPLifiCoreEvent) {
        switch event {
        case .thinking(let agentName, let phase, let message):
            if let message, !message.isEmpty {
                AILog.log("[Thinking] agent=\(agentName) phase=\(phase) message=\(message)")
            } else {
                AILog.log("[Thinking] agent=\(agentName) phase=\(phase)")
            }
            if phase != "memory" {
                isParsing = true
            }
            let thinkingText = AIToolPresentation.collaborationMessage(for: agentName, phase: phase, fallbackMessage: message)
            if !hideThinkingProcess && shouldAppendThinkingMessage(thinkingText) {
                withAnimation(.spring()) {
                    displayItems.append(DisplayItem(kind: .aiThinking(thinkingText)))
                }
            }
        case .textStream:
            break
        case .toolRequest(let req):
            AILog.log("[ToolRequest] tool=\(req.tool)")
            isParsing = false
            let normalizedTool = ToolCallExecutor.shared.normalizeToolName(req.tool)
            let sanitizedReq: AIToolRequest
            if normalizedTool == "read_tasks", let readArgs = req.readTasksArgs {
                let sanitized = sanitizeReadTasksArgs(readArgs, userQuery: toolOriginalUserText)
                sanitizedReq = AIToolRequest(
                    id: req.id,
                    tool: normalizedTool,
                    argsJson: encodeReadTasksArgsJson(sanitized),
                    reason: req.reason,
                    executionMode: req.executionMode
                )
            } else {
                sanitizedReq = AIToolRequest(
                    id: req.id,
                    tool: normalizedTool,
                    argsJson: req.argsJson,
                    reason: req.reason,
                    executionMode: req.executionMode
                )
            }

            if AIToolPresentation.shouldAutoApproveToolRequest(sanitizedReq) || (silentTaskAdd && normalizedTool == "create_task") {
                if !hideThinkingProcess {
                    withAnimation(.spring()) {
                        displayItems.append(DisplayItem(kind: .aiThinking(AIToolPresentation.toolCollaborationMessage(for: sanitizedReq.tool))))
                    }
                }
                pendingToolRequest = sanitizedReq
                Task { await approveAndRunTool(sanitizedReq) }
                return
            }

            if normalizedTool == "read_tasks", (autoApproveReadTasks || sessionAutoApproveReadTasks) {
                if !hideThinkingProcess {
                    withAnimation(.spring()) {
                        displayItems.append(DisplayItem(kind: .aiThinking(AIToolPresentation.toolCollaborationMessage(for: sanitizedReq.tool))))
                    }
                }
                pendingToolRequest = sanitizedReq
                Task { await approveAndRunTool(sanitizedReq) }
                return
            }

            if normalizedTool == "read_tasks", !autoApproveReadTasks && !sessionAutoApproveReadTasks {
                readTasksPromptCount += 1
                if readTasksPromptCount >= 3 {
                    displayItems.append(DisplayItem(kind: .aiChat("你最近频繁用到“读取任务列表”，可以去设置 > Lifi AI 打开“自动确认读取任务列表”，减少重复点击。")))
                    readTasksPromptCount = 0
                }
            }

            pendingToolRequest = sanitizedReq
            withAnimation(.spring()) {
                if !hideThinkingProcess {
                    displayItems.append(DisplayItem(kind: .aiThinking(AIToolPresentation.toolCollaborationMessage(for: sanitizedReq.tool))))
                }
                displayItems.append(DisplayItem(kind: .aiToolRequest(sanitizedReq)))
            }
        case .finish(let payload):
            pendingToolRequest = nil
            AILog.log("[Finish] intent=\(payload.primaryIntent)")
            isParsing = false
            pendingMemoryNoticeTask?.cancel()
            pendingMemoryNoticeTask = nil

            if let s = payload.sessionSummary, !s.isEmpty {
                sessionSummary = String(s.prefix(600))
            }

            let suppressProposalCardsForReadOnlyTool = {
                guard let tool = lastSubmittedToolName else { return false }
                let normalized = ToolCallExecutor.shared.normalizeToolName(tool)
                return normalized == "read_tasks"
                    || normalized == "read_habits"
                    || normalized == "create_task"
                    || normalized == "create_habit"
            }()
            lastSubmittedToolName = nil

            withAnimation(.spring()) {
                if !suppressProposalCardsForReadOnlyTool {
                    for task in payload.tasks {
                        displayItems.append(DisplayItem(kind: .aiTask(task)))
                    }
                    for habit in payload.habits {
                        displayItems.append(DisplayItem(kind: .aiHabit(habit)))
                    }
                }
                if let chat = payload.chatResponse, !chat.isEmpty {
                    displayItems.append(DisplayItem(kind: .aiChat(chat)))
                }
            }
        case .memoryCommitted(let payload):
            AILog.log("[MemoryCommitted] added=\(payload.addedMemories.count) profileUpdated=\(payload.profileUpdated) revision=\(payload.newRevision)")
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
            pendingToolRequest = nil
            AILog.log("[Error] \(message)")
            isParsing = false
            pendingMemoryNoticeTask?.cancel()
            pendingMemoryNoticeTask = nil
            lastSubmittedToolName = nil
            errorMessage = message
            showErrorMessage = true
        }
    }

    func sanitizeReadTasksArgs(_ args: ReadTasksArgs, userQuery: String) -> ReadTasksArgs {
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

    func shouldAppendThinkingMessage(_ message: String) -> Bool {
        guard let last = displayItems.last?.kind else { return true }
        switch last {
        case .aiThinking(let previous):
            return previous != message
        default:
            return true
        }
    }

    func isGenericTaskListQuery(_ q: String) -> Bool {
        let s = q.lowercased()
        // 典型泛查询词
        let patterns = ["这周", "本周", "最近", "有哪些任务", "有什么任务", "任务列表", "to do", "todo", "待办", "待办事项", "deadline", "ddl"]
        return patterns.contains { s.contains($0.lowercased()) }
    }

    /// 用户是否显式给了主题：例如“系统论的任务”“关于 BOE 的任务”“BOE 相关任务”
    /// 这里先做最小启发式：包含“关于/相关/的任务/的ddl/的待办/项目”等信号
    func userExplicitlyProvidedTopic(_ q: String) -> Bool {
        let s = q.lowercased()
        let signals = ["关于", "相关", "的任务", "的ddl", "的待办", "项目", "course", "project"]
        return signals.contains { s.contains($0.lowercased()) }
    }

    func encodeReadTasksArgsJson(_ args: ReadTasksArgs) -> String {
        guard let data = try? JSONEncoder().encode(args),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    @MainActor
    func autoCreateTasksFromProposals(_ proposals: [AITask]) async {
        guard !proposals.isEmpty else { return }
        var successCount = 0
        for proposal in proposals {
            let key = makeTaskKey(proposal)
            do {
                let params = try makeTaskInsertParams(from: proposal)
                let insertedId = try await PersistenceStores.tasks.createTask(params)
                addedTaskKeys.insert(key)
                createdTaskIDsByKey[key] = insertedId
                successCount += 1
            } catch {
                continue
            }
        }
        if successCount > 0 {
            withAnimation(.spring()) {
                displayItems.append(DisplayItem(kind: .aiChat("已静默添加 \(successCount) 条任务。若有误可点“撤回任务”。")))
            }
        }
    }

    @MainActor
    func prepareFeedbackAndShare() async {
        if isPreparingFeedback { return }
        isPreparingFeedback = true
        defer { isPreparingFeedback = false }

        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "unknown"
        let build = (info?["CFBundleVersion"] as? String) ?? "unknown"

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let context = AIFeedbackService.Context(
            appVersion: version,
            buildNumber: build,
            timestamp: iso.string(from: Date()),
            timezone: TimeZone.current.identifier,
            locale: Locale.current.identifier,
            lastCoreEventSummary: KMPLifiCoreBridge.shared.lastEventSummary ?? "(none)",
            sessionSummary: sessionSummary.isEmpty ? "(empty)" : sessionSummary,
            memoryFragmentsCount: memoryBank.fragments.count,
            memoryProfile: memoryBank.userProfile,
            transcriptLines: makeFeedbackTranscriptLines(maxItems: 120),
            coreLastFinishJson: KMPLifiCoreBridge.shared.getLastFinishJson(),
            coreLastMemorySyncJson: KMPLifiCoreBridge.shared.getLastMemorySyncJson()
        )

        let items = await AIFeedbackService.makeShareItems(context: context)
        feedbackShareItems = items
        showFeedbackShareSheet = true
    }

    func makeFeedbackTranscriptLines(maxItems: Int) -> [String] {
        let recent = Array(displayItems.suffix(maxItems))
        return recent.map { item in
            switch item.kind {
            case .userQuery(let text):
                return "[User] \(text)"
            case .aiChat(let text):
                return "[AI] \(text)"
            case .aiThinking(let text):
                return "[Thinking] \(text)"
            case .aiTask(let task):
                let due = (task.dueTime?.isEmpty == false) ? task.dueTime! : "N/A"
                return "[TaskCard] name=\(task.name) due=\(due)"
            case .aiHabit(let habit):
                return "[HabitCard] name=\(habit.name) period=\(habit.period) times=\(habit.timesPerPeriod)"
            case .aiMemory(let text):
                return "[Memory] \(text)"
            case .aiToolRequest(let req):
                return "[ToolRequest] tool=\(req.tool) mode=\(req.executionMode ?? "N/A") args=\(req.argsJson)"
            case .aiToolResult(let result):
                return "[ToolResult] tool=\(result.tool) result=\(result.resultJson)"
            }
        }
    }

}
