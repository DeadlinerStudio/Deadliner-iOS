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
    private var eventHandlers: [UUID: (KMPLifiCoreEvent) -> Void] = [:]
    private let legacySubscriber = UUID()
    private var eventPump: _Concurrency.Task<Void, Never>?
    private var eventCursor: Int64 = 0
    private var consumerId = UUID().uuidString
    private var lastDeliveredSeq: Int64 = 0
    private var detachedEvents: [KMPLifiCoreEvent] = []
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
        guard KMPSharedDatabaseLocation.databasePath != nil else {
            throw KMPLifiBridgeError.missingSharedDatabasePath
        }

        let appDatabase = await KMPPersistenceRuntime.shared.coreDatabase()
        let newCore = IosLifiCore.companion.createWithDatabase(
            apiKey: apiKey,
            baseUrl: normalizedURL,
            model: model,
            timezone: TimeZone.current.identifier,
            database: appDatabase,
            ownsDatabase: false
        )
        core = newCore
        configurationFingerprint = fingerprint
        // Reattach from the current snapshot; never replay historical approval requests.
        eventCursor = (try? await newCore.snapshotV2())?.lastSeq ?? 0
        isReady = true
        startEventPump(core: newCore, generation: sessionGeneration)
        lastEventSummary = "KMP LiFi initialized"
    }

    func processInput(_ text: String) async {
        do {
            try await initializeIfNeeded()
            guard let core else { throw KMPLifiBridgeError.unavailable }
            _ = try await core.startRunV2(text: text)
        } catch {
            emitError("KMP LiFi 请求失败：\(error.localizedDescription)")
        }
    }

    func extractQuickAdd(_ text: String, kind: String) async throws -> String {
        try await initializeIfNeeded()
        guard let core else { throw KMPLifiBridgeError.unavailable }
        return try await IosQuickAddBridge().extractJson(core: core, text: text, kind: kind)
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
            deliver(.error("KMP LiFi 尚未初始化"))
            return
        }

        do {
            let expectedGeneration = generation
            let accepted = try await core.submitToolResultV2(toolCallId: id, tool: tool, payload: resultJson)
            guard generation == expectedGeneration else { return }
            guard accepted.boolValue else { emitError("本次确认已失效，请重新发起请求。"); return }
            pendingToolCalls.removeValue(forKey: id)
        } catch {
            emitError("KMP LiFi 工具结果回灌失败：\(error.localizedDescription)")
        }
    }

    func cancelRun() async {
        let expectedGeneration = generation
        try? await core?.cancelRun()
        guard expectedGeneration == generation else { return }
        pendingToolCalls.removeAll()
    }

    func executeToolRequest(_ request: AIToolRequest) async -> ToolCallExecutor.ToolExecutionResult {
        guard pendingToolCalls[request.id] != nil, let core else {
            return await ToolCallExecutor.shared.missingTypedToolCallResult(for: request.tool)
        }
        do {
            let expectedGeneration = generation
            // Configuration changes invalidate the previous core and all of its approvals.
            try await initializeIfNeeded()
            guard generation == expectedGeneration, pendingToolCalls[request.id] != nil else {
                return await ToolCallExecutor.shared.missingTypedToolCallResult(for: request.tool)
            }
            let result = try await core.executeApprovedTool(actionId: request.id, confirmedArguments: request.argsJson)
            if request.tool == "create_task" || request.tool == "update_deadline" {
                PersistenceChangePublisher.publish(.init(resourceKinds: [.task, .taskSubtask]))
                await KMPTaskReminderScheduler.shared.scheduleRefresh()
            } else if request.tool == "create_habit" {
                PersistenceChangePublisher.publish(.init(resourceKinds: [.habit, .habitRecord, .habitSchedule]))
                await KMPHabitReminderScheduler.shared.scheduleRefresh()
            }
            return ToolCallExecutor.ToolExecutionResult(normalizedToolName: request.tool, resultJson: result, displayMessage: nil)
        } catch {
            return ToolCallExecutor.ToolExecutionResult(normalizedToolName: request.tool,
                resultJson: "{\"ok\":false,\"errorCode\":\"TOOL_EXECUTION_FAILED\"}", displayMessage: "操作失败或确认已过期")
        }
    }

    func setEventHandler(_ handler: @escaping (KMPLifiCoreEvent) -> Void) {
        eventHandlers[legacySubscriber] = handler
        replayCurrentSnapshot(to: handler)
    }

    @discardableResult
    func subscribe(_ handler: @escaping (KMPLifiCoreEvent) -> Void) -> UUID {
        let id = UUID()
        eventHandlers[id] = handler
        replayCurrentSnapshot(to: handler)
        return id
    }

    func unsubscribe(_ id: UUID) { eventHandlers.removeValue(forKey: id) }
    func clearEventHandler() { eventHandlers.removeValue(forKey: legacySubscriber) }

    private func deliver(_ event: KMPLifiCoreEvent) {
        if eventHandlers.isEmpty {
            detachedEvents.append(event)
            if detachedEvents.count > 64 { detachedEvents.removeFirst() }
        } else {
            for handler in Array(eventHandlers.values) { handler(event) }
            lastDeliveredSeq = eventCursor
        }
    }

    private func replayCurrentSnapshot(to handler: @escaping (KMPLifiCoreEvent) -> Void) {
        let buffered = detachedEvents
        detachedEvents.removeAll()
        if !buffered.isEmpty { for event in buffered { handler(event) }; return }
        let expectedGeneration = generation
        _Concurrency.Task { @MainActor [weak self] in
            guard let self, let core = self.core,
                  let snapshot = try? await core.snapshotV2(), self.generation == expectedGeneration else { return }
            guard snapshot.lastSeq > self.lastDeliveredSeq else { return }
            if let terminal = snapshot.terminal, let event = terminal.compatibilityEvent {
                self.handle(event: event, generation: expectedGeneration)
            } else if let pending = snapshot.pending {
                self.handle(event: pending, generation: expectedGeneration)
            }
        }
    }

    private func startEventPump(core: IosLifiCore, generation expectedGeneration: Int) {
        eventPump?.cancel()
        eventPump = _Concurrency.Task { @MainActor [weak self] in
            while !_Concurrency.Task.isCancelled {
                guard let self, self.generation == expectedGeneration else { return }
                do {
                    let batch = try await core.readEventsV2(consumerId: self.consumerId, afterSeq: self.eventCursor)
                    guard self.generation == expectedGeneration else { return }
                    guard batch.protocolVersion == 2 else { self.emitError("UNSUPPORTED_PROTOCOL"); return }
                    if batch.resyncRequired {
                        let snapshot = try await core.snapshotV2()
                        self.eventCursor = snapshot.lastSeq
                        self.pendingToolCalls.removeAll()
                        if let terminal = snapshot.terminal, let event = terminal.compatibilityEvent {
                            self.handle(event: event, generation: expectedGeneration)
                        } else if let pending = snapshot.pending {
                            self.handle(event: pending, generation: expectedGeneration)
                        }
                    } else {
                        for record in batch.events {
                            guard record.seq == self.eventCursor + 1 else { self.emitError("EVENT_GAP"); return }
                            self.eventCursor = record.seq
                            if let event = record.compatibilityEvent { self.handle(event: event, generation: expectedGeneration) }
                        }
                    }
                    let ack = try await core.ackEventsV2(consumerId: self.consumerId, batchId: batch.batchId, lastSeq: batch.lastSeq)
                    guard ack.boolValue else { self.emitError("ACK_REJECTED"); return }
                    self.eventCursor = max(self.eventCursor, batch.lastSeq)
                    try await _Concurrency.Task.sleep(for: .milliseconds(50))
                } catch {
                    if !_Concurrency.Task.isCancelled && self.generation == expectedGeneration { self.emitError("LIFI_EVENT_FAILED") }
                    return
                }
            }
        }
    }

    func getLastFinishJson() -> String? {
        lastFinishJson
    }

    func getLastMemorySyncJson() -> String? {
        lastMemorySyncJson
    }

    private func closeCurrentSession() {
        eventPump?.cancel()
        eventPump = nil
        eventCursor = 0
        consumerId = UUID().uuidString
        lastDeliveredSeq = 0
        detachedEvents.removeAll()
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
            deliver(.thinking(agentName: event.agentName, phase: event.phase, message: event.message ?? (event.phase == "retrying" ? "网络暂时不可用，正在重试…" : nil)))

        case let event as CoreEvent.OnTextStream:
            lastEventSummary = "Streaming"
            deliver(.textStream(chunk: event.chunk))

        case let event as CoreEvent.OnToolRequest:
            guard let request = makeToolRequest(id: event.id, toolCall: event.tool, executionMode: event.executionMode) else {
                emitError("KMP LiFi 请求了未支持的工具")
                return
            }
            pendingToolCalls[event.id] = event.tool
            lastEventSummary = "Tool request \(request.tool) [\(event.id)]"
            deliver(.toolRequest(request))

        case let event as CoreEvent.OnFinish:
            pendingToolCalls.removeAll()
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
            deliver(.finish(payload))

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
            deliver(.memoryCommitted(payload))

        case let event as CoreEvent.OnError:
            pendingToolCalls.removeAll()
            emitError(AgentErrorMessages.shared.describe(code: event.message))

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
            // Preserve the V2 schedule/goal/tracking contract, including units and defaults.
            // Legacy fields remain available to the existing card decoder.
            let wire = ToolArgumentCodec.shared.encode(call: tool)
            guard let data = wire.data(using: .utf8),
                  var args = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            args["period"] = tool.period
            args["timesPerPeriod"] = Int(tool.timesPerPeriod)
            args["goalType"] = tool.goalType
            if let total = tool.totalTarget { args["totalTarget"] = Int(total.intValue) }
            guard let encoded = try? JSONSerialization.data(withJSONObject: args, options: .sortedKeys),
                  let json = String(data: encoded, encoding: .utf8) else { return nil }
            return AIToolRequest(id: id, tool: "create_habit", argsJson: json,
                reason: tool.reason, executionMode: mode)

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
        deliver(.error(message))
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
