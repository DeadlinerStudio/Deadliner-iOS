//
//  KMPLifiCoreBridge.swift
//  Deadliner
//
//  Direct SwiftUI bridge for the KMP LiFi runtime.
//

#if canImport(Shared)
import Foundation
import Observation
import Shared

enum KMPLifiCoreEvent {
    case thinking(agentName: String, phase: String, message: String?)
    case textStream(chunk: String)
    case toolRequest(AIToolRequest)
    case finish(DeadlinerCoreFinishPayload)
    case memoryCommitted(DeadlinerCoreMemoryCommitPayload)
    case error(String)
}

struct DeadlinerCoreFinishPayload {
    let primaryIntent: String
    let tasks: [AITask]
    let habits: [AIHabit]
    let retrievedTasks: [AITask]
    let retrievedHabits: [AIHabit]
    let chatResponse: String?
    let sessionSummary: String?
    let memorySyncJson: String?
}

struct DeadlinerCoreMemoryCommitPayload {
    let addedMemories: [String]
    let profileUpdated: Bool
    let newRevision: UInt64
    let notices: [String]
}

@MainActor
@Observable
final class KMPLifiCoreBridge {
    static let shared = KMPLifiCoreBridge()

    private(set) var isReady = false
    private(set) var lastEventSummary: String?

    private var core: IosLifiCore?
    private var listener: KMPLifiEventListener?
    private var eventHandler: ((KMPLifiCoreEvent) -> Void)?
    private var pendingToolCalls: [String: ToolCall] = [:]
    private var generation = 0
    private var configurationFingerprint: String?
    private var lastFinishJson: String?
    private var lastMemorySyncJson: String?

    private init() {}

    func initializeIfNeeded() async throws {
        await MemoryBank.shared.ensureKMPMemoryMigration()

        let apiKey = await LocalValues.shared.getAIApiKey()
        let baseURL = await LocalValues.shared.getAIBaseUrl()
        let model = await LocalValues.shared.getAIModel()
        let normalizedURL = normalizeBaseURL(baseURL)
        let fingerprint = [apiKey, normalizedURL, model, TimeZone.current.identifier].joined(separator: "\u{1F}")

        guard core == nil || configurationFingerprint != fingerprint else { return }

        closeCurrentSession()
        generation &+= 1
        let sessionGeneration = generation
        guard let databasePath = KMPSharedDatabaseLocation.databasePath else {
            throw KMPLifiBridgeError.missingSharedDatabasePath
        }

        let newCore = IosLifiCore.companion.create(
            apiKey: apiKey,
            baseUrl: normalizedURL,
            model: model,
            timezone: TimeZone.current.identifier,
            databasePath: databasePath
        )
        let newListener = KMPLifiEventListener(handler: { [weak self] event in
            _Concurrency.Task { @MainActor in
                self?.handle(event: event, generation: sessionGeneration)
            }
        })
        newCore.start(listener: newListener)

        core = newCore
        listener = newListener
        configurationFingerprint = fingerprint
        isReady = true
        lastEventSummary = "KMP LiFi initialized"
    }

    func processInput(_ text: String) async {
        guard let core else {
            eventHandler?(.error("KMP LiFi 尚未初始化"))
            return
        }

        do {
            try await core.processInput(text: text)
        } catch {
            emitError("KMP LiFi 请求失败：\(error.localizedDescription)")
        }
    }

    func extractTasks(_ text: String) async throws -> [AITask] {
        try await initializeIfNeeded()
        guard let core else { throw KMPLifiBridgeError.unavailable }
        return try await core.extractTasks(text: text).map(\.appTask)
    }

    func extractHabits(_ text: String) async throws -> [AIHabit] {
        try await initializeIfNeeded()
        guard let core else { throw KMPLifiBridgeError.unavailable }
        return try await core.extractHabits(text: text).map(\.appHabit)
    }

    func generateMonthlyAnalysis(
        monthName: String,
        metricsSummary: String,
        completedTaskNames: [String]
    ) async throws -> MonthlyAnalysisResult {
        try await initializeIfNeeded()
        guard let core else { throw KMPLifiBridgeError.unavailable }
        let result = try await core.generateMonthlyAnalysis(
            monthName: monthName,
            metricsSummary: metricsSummary,
            completedTaskNames: completedTaskNames
        )
        return MonthlyAnalysisResult(
            month: monthName,
            summary: result.summary,
            keywords: result.keywords
        )
    }

    func validateConfiguration(apiKey: String, baseURL: String, model: String) async throws {
        try await IosLifiCore.companion.validateConfiguration(
            apiKey: apiKey,
            baseUrl: normalizeBaseURL(baseURL),
            model: model,
            timezone: TimeZone.current.identifier
        )
    }

    func submitToolResult(id: String, tool: String, resultJson: String) async {
        guard let core else {
            eventHandler?(.error("KMP LiFi 尚未初始化"))
            return
        }

        do {
            try await core.submitToolResult(toolCallId: id, tool: tool, payload: resultJson)
        } catch {
            emitError("KMP LiFi 工具结果回灌失败：\(error.localizedDescription)")
        }
    }

    func executeToolRequest(_ request: AIToolRequest) async -> ToolCallExecutor.ToolExecutionResult {
        guard let toolCall = pendingToolCalls.removeValue(forKey: request.id) else {
            return await ToolCallExecutor.shared.missingTypedToolCallResult(for: request.tool)
        }
        return await ToolCallExecutor.shared.execute(toolCall: toolCall)
    }

    func setEventHandler(_ handler: @escaping (KMPLifiCoreEvent) -> Void) {
        eventHandler = handler
    }

    func clearEventHandler() {
        eventHandler = nil
    }

    func getLastFinishJson() -> String? {
        lastFinishJson
    }

    func getLastMemorySyncJson() -> String? {
        lastMemorySyncJson
    }

    private func closeCurrentSession() {
        core?.close()
        core = nil
        listener = nil
        pendingToolCalls.removeAll()
        isReady = false
    }

    private func handle(event: CoreEvent, generation eventGeneration: Int) {
        guard eventGeneration == generation else { return }

        switch event {
        case let event as CoreEvent.OnLifecycle:
            let suffix = event.message.map { " - \($0)" } ?? ""
            lastEventSummary = "Lifecycle \(event.stage).\(event.status) [\(event.requestId)]\(suffix)"

        case let event as CoreEvent.OnThinking:
            lastEventSummary = "Thinking: \(event.agentName) [\(event.phase)]"
            eventHandler?(.thinking(agentName: event.agentName, phase: event.phase, message: event.message))

        case let event as CoreEvent.OnTextStream:
            lastEventSummary = "Streaming: \(event.chunk.prefix(32))"
            eventHandler?(.textStream(chunk: event.chunk))

        case let event as CoreEvent.OnToolRequest:
            guard let request = makeToolRequest(id: event.id, toolCall: event.tool, executionMode: event.executionMode) else {
                emitError("KMP LiFi 请求了未支持的工具")
                return
            }
            pendingToolCalls[event.id] = event.tool
            lastEventSummary = "Tool request \(request.tool) [\(event.id)]"
            eventHandler?(.toolRequest(request))

        case let event as CoreEvent.OnFinish:
            let result = event.result
            let payload = DeadlinerCoreFinishPayload(
                primaryIntent: result.primaryIntent ?? "unknown",
                tasks: result.tasks.map(\.appTask),
                habits: result.habits.map(\.appHabit),
                retrievedTasks: result.retrievedTasks.map(\.appTask),
                retrievedHabits: result.retrievedHabits.map(\.appHabit),
                chatResponse: result.chatResponse,
                sessionSummary: result.sessionSummary,
                memorySyncJson: nil
            )
            lastEventSummary = "Finished: \(payload.primaryIntent)"
            lastFinishJson = KMPBridgeFeedbackPayload(finish: payload).json
            if !result.newMemories.isEmpty || result.userProfile != nil {
                MemoryBank.shared.applyKMPCommittedResult(
                    addedMemories: result.newMemories,
                    updatedProfile: result.userProfile,
                    newRevision: 0
                )
            }
            eventHandler?(.finish(payload))

        case let event as CoreEvent.OnMemoryCommitted:
            let revision = UInt64(max(0, event.newRevision))
            lastEventSummary = "Memory committed: +\(event.addedMemories.count), profile=\(event.profileUpdated)"
            MemoryBank.shared.applyKMPCommittedResult(
                addedMemories: event.addedMemories,
                updatedProfile: nil,
                newRevision: revision
            )
            let notices = event.addedMemories.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let payload = DeadlinerCoreMemoryCommitPayload(
                addedMemories: event.addedMemories,
                profileUpdated: event.profileUpdated,
                newRevision: revision,
                notices: notices
            )
            lastMemorySyncJson = KMPBridgeFeedbackPayload(memory: payload).json
            eventHandler?(.memoryCommitted(payload))

        case let event as CoreEvent.OnError:
            emitError(event.message)

        default:
            lastEventSummary = "Unhandled KMP event: \(String(describing: event))"
        }
    }

    private func makeToolRequest(
        id: String,
        toolCall: ToolCall,
        executionMode: CapabilityExecutionMode?
    ) -> AIToolRequest? {
        let mode = executionMode?.name.lowercased()
        switch toolCall {
        case let tool as ToolCall.ReadTasks:
            return request(id: id, tool: "read_tasks", args: ReadTasksArgs(
                timeRangeDays: tool.timeRangeDays.map { Int($0.intValue) },
                status: tool.status,
                keywords: tool.keywords,
                limit: Int(tool.limit),
                sort: tool.sort
            ), reason: tool.reason, executionMode: mode)

        case let tool as ToolCall.CreateTask:
            return request(id: id, tool: "create_task", args: CreateTaskArgs(
                name: tool.name,
                dueTime: tool.dueTime,
                note: tool.note
            ), reason: tool.reason, executionMode: mode)

        case let tool as ToolCall.UpdateDeadline:
            return request(id: id, tool: "update_deadline", args: UpdateDeadlineArgs(
                taskId: tool.taskId,
                newDueTime: tool.newDueTime
            ), reason: tool.reason, executionMode: mode)

        case let tool as ToolCall.ReadHabits:
            return request(id: id, tool: "read_habits", args: ReadHabitsArgs(
                keywords: tool.keywords
            ), reason: tool.reason, executionMode: mode)

        case let tool as ToolCall.CreateHabit:
            return request(id: id, tool: "create_habit", args: CreateHabitArgs(
                name: tool.name,
                period: tool.period,
                timesPerPeriod: Int(tool.timesPerPeriod),
                goalType: tool.goalType,
                totalTarget: tool.totalTarget.map { Int($0.intValue) }
            ), reason: tool.reason, executionMode: mode)

        default:
            return nil
        }
    }

    private func request<T: Encodable>(
        id: String,
        tool: String,
        args: T,
        reason: String?,
        executionMode: String?
    ) -> AIToolRequest? {
        guard let data = try? JSONEncoder().encode(args),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return AIToolRequest(id: id, tool: tool, argsJson: json, reason: reason, executionMode: executionMode)
    }

    private func normalizeBaseURL(_ baseURL: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/v1") || trimmed.hasSuffix("/chat/completions") {
            return trimmed
        }
        return trimmed.isEmpty ? "https://api.deepseek.com/v1" : "\(trimmed)/v1"
    }

    private func emitError(_ message: String) {
        lastEventSummary = "Error: \(message)"
        eventHandler?(.error(message))
    }
}

private final class KMPLifiEventListener: IosLifiEventListener {
    private let handler: @Sendable (CoreEvent) -> Void

    init(handler: @escaping @Sendable (CoreEvent) -> Void) {
        self.handler = handler
    }

    func onEvent(event: CoreEvent) {
        handler(event)
    }
}

private enum KMPLifiBridgeError: LocalizedError {
    case missingSharedDatabasePath
    case unavailable

    var errorDescription: String? {
        switch self {
        case .missingSharedDatabasePath:
            return "无法解析 App Group 的 KMP 数据库路径。"
        case .unavailable:
            return "KMP LiFi 尚未初始化。"
        }
    }
}

private extension AiTaskProposal {
    var appTask: AITask {
        AITask(name: title, dueTime: dueAt, note: note)
    }
}

private extension AiHabitProposal {
    var appHabit: AIHabit {
        let period: String = {
            if schedule.kind == .once { return "ONCE" }
            if schedule.kind == .algorithm { return "EBBINGHAUS" }
            if goal.window == .week { return "WEEKLY" }
            if goal.window == .month { return "MONTHLY" }
            return "DAILY"
        }()
        let isLifetime = goal.window == .lifetime
        return AIHabit(
            name: name,
            period: period,
            timesPerPeriod: Int(goal.targetCount),
            goalType: isLifetime ? "TOTAL" : "PER_PERIOD",
            totalTarget: isLifetime ? Int(goal.targetCount) : nil,
            weekdaysMask: schedule.weekdaysMask.map { Int($0.intValue) },
            alarmTime: reminder?.isEnabled == true ? reminder?.localTime : nil
        )
    }
}

private struct KMPBridgeFeedbackPayload: Codable {
    let kind: String
    let primaryIntent: String?
    let addedMemories: [String]?
    let profileUpdated: Bool?
    let revision: UInt64?

    init(finish: DeadlinerCoreFinishPayload) {
        kind = "finish"
        primaryIntent = finish.primaryIntent
        addedMemories = nil
        profileUpdated = nil
        revision = nil
    }

    init(memory: DeadlinerCoreMemoryCommitPayload) {
        kind = "memoryCommitted"
        primaryIntent = nil
        addedMemories = memory.addedMemories
        profileUpdated = memory.profileUpdated
        revision = memory.newRevision
    }

    var json: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
#endif
