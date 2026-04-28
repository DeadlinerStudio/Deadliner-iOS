//
//  DeadlinerCoreBridge.swift
//  Deadliner
//
//  Created by Codex on 2026/3/19.
//

import Foundation
import Observation

enum DeadlinerCoreBridgeEvent {
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
final class DeadlinerCoreBridge {
    static let shared = DeadlinerCoreBridge()

    private(set) var isReady = false
    private(set) var lastEventSummary: String?

    private var core: DeadlinerCore?
    private var callbackProxy: DeadlinerCoreCallbackProxy?
    private var eventHandler: ((DeadlinerCoreBridgeEvent) -> Void)?

    private init() {}

    private func currentMemorySnapshotJson() -> String {
        MemoryBank.shared.exportSnapshotJson()
    }

    func initializeIfNeeded() async throws {
        guard core == nil else { return }

        let apiKey = await LocalValues.shared.getAIApiKey()
        let baseUrl = await LocalValues.shared.getAIBaseUrl()
        let modelId = await LocalValues.shared.getAIModel()
        let storagePath = makeStoragePath()

        let core = try DeadlinerCore(
            apiKey: apiKey,
            baseUrl: normalizeBaseURL(baseUrl),
            modelId: modelId,
            storagePath: storagePath,
            platform: "ios"
        )

        let proxy = DeadlinerCoreCallbackProxy { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
        }

        core.setCallback(callback: proxy)
        await core.replaceMemorySnapshot(snapshotJson: currentMemorySnapshotJson())

        self.core = core
        self.callbackProxy = proxy
        self.isReady = true
        self.lastEventSummary = "DeadlinerCore initialized"
    }

    func processInput(_ text: String) async {
        guard let core else { return }
        await core.replaceMemorySnapshot(snapshotJson: currentMemorySnapshotJson())
        await core.processInput(text: text)
    }

    func replaceMemorySnapshot(_ snapshotJson: String) async {
        guard let core else { return }
        await core.replaceMemorySnapshot(snapshotJson: snapshotJson)
    }

    func submitToolResult(id: String, resultJson: String) async {
        guard let core else { return }
        await core.replaceMemorySnapshot(snapshotJson: currentMemorySnapshotJson())
        await core.submitToolResult(id: id, resultJson: resultJson)
    }

    func exportMemorySnapshot() -> String? {
        core?.exportMemorySnapshot()
    }

    func getLastFinishJson() -> String? {
        core?.getLastFinishJson()
    }

    func getLastMemorySyncJson() -> String? {
        core?.getLastMemorySyncJson()
    }

    func setEventHandler(_ handler: @escaping (DeadlinerCoreBridgeEvent) -> Void) {
        eventHandler = handler
    }

    func clearEventHandler() {
        eventHandler = nil
    }

    private func handle(event: CoreEvent) {
        switch event {
        case .onLifecycle(let requestId, let stage, let status, let message):
            let suffix = message?.isEmpty == false ? " - \(message!)" : ""
            lastEventSummary = "Lifecycle \(stage).\(status) [\(requestId)]\(suffix)"
        case .onThinking(let agentName, let phase, let message):
            lastEventSummary = "Thinking: \(agentName) [\(phase)]"
            eventHandler?(.thinking(agentName: agentName, phase: phase, message: message))
        case .onTextStream(let chunk):
            lastEventSummary = "Streaming: \(chunk.prefix(32))"
            eventHandler?(.textStream(chunk: chunk))
        case .onToolRequest(let id, let toolName, let argsJson):
            let normalizedToolName = ToolCallExecutor.shared.normalizeToolName(toolName)
            lastEventSummary = "Tool request \(normalizedToolName) [\(id)]"
            let executionMode = decodeToolExecutionMode(from: argsJson)
            eventHandler?(.toolRequest(AIToolRequest(
                id: id,
                tool: normalizedToolName,
                argsJson: argsJson,
                reason: nil,
                executionMode: executionMode
            )))
        case .onFinish(let primaryIntent, let tasks, let habits, let retrievedTasks, let retrievedHabits, let chatResponse, let sessionSummary, let memorySyncJson):
            lastEventSummary = "Finished: \(primaryIntent)"
            eventHandler?(.finish(DeadlinerCoreFinishPayload(
                primaryIntent: primaryIntent,
                tasks: (tasks ?? []).map(\.asAppTask),
                habits: (habits ?? []).map(\.asAppHabit),
                retrievedTasks: (retrievedTasks ?? []).map(\.asAppTask),
                retrievedHabits: (retrievedHabits ?? []).map(\.asAppHabit),
                chatResponse: chatResponse,
                sessionSummary: sessionSummary,
                memorySyncJson: memorySyncJson
            )))
        case .onMemoryCommitted(let addedMemories, let profileUpdated, let newRevision):
            lastEventSummary = "Memory committed: +\(addedMemories.count), profile=\(profileUpdated)"
            let previousProfile = MemoryBank.shared.userProfile
            let updatedProfile = profileUpdated ? core?.getUserProfile() : nil
            MemoryBank.shared.applyCommittedResult(
                addedMemories: addedMemories,
                updatedProfile: updatedProfile,
                newRevision: newRevision
            )

            let snapshotJson = currentMemorySnapshotJson()
            Task {
                await self.replaceMemorySnapshot(snapshotJson)
            }

            let currentProfile = MemoryBank.shared.userProfile.trimmingCharacters(in: .whitespacesAndNewlines)
            let oldProfile = previousProfile.trimmingCharacters(in: .whitespacesAndNewlines)
            var notices = addedMemories.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if profileUpdated && !currentProfile.isEmpty && currentProfile != oldProfile {
                notices.append("画像已更新")
            }

            eventHandler?(.memoryCommitted(DeadlinerCoreMemoryCommitPayload(
                addedMemories: addedMemories,
                profileUpdated: profileUpdated,
                newRevision: newRevision,
                notices: notices
            )))
        case .onError(let message):
            lastEventSummary = "Error: \(message)"
            eventHandler?(.error(message))
        }
    }

    private func makeStoragePath() -> String {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let storageURL = baseURL.appendingPathComponent("DeadlinerAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        return storageURL.path
    }

    private func normalizeBaseURL(_ baseURL: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/v1") || trimmed.hasSuffix("/chat/completions") {
            return trimmed
        }
        return trimmed.isEmpty ? "https://api.deepseek.com/v1" : "\(trimmed)/v1"
    }

    private func decodeToolExecutionMode(from argsJson: String) -> String? {
        guard let data = argsJson.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let meta = object["_meta"] as? [String: Any],
              let executionMode = meta["executionMode"] as? String else {
            return nil
        }
        return executionMode
    }

}

private final class DeadlinerCoreCallbackProxy: CoreCallback {
    private let handler: @Sendable (CoreEvent) -> Void

    init(handler: @escaping @Sendable (CoreEvent) -> Void) {
        self.handler = handler
    }

    func onEvent(event: CoreEvent) {
        handler(event)
    }
}

private extension FfiTask {
    var asAppTask: AITask {
        AITask(name: name, dueTime: dueTime, note: note)
    }
}

private extension FfiHabit {
    var asAppHabit: AIHabit {
        AIHabit(
            name: name,
            period: period,
            timesPerPeriod: Int(timesPerPeriod),
            goalType: goalType,
            totalTarget: totalTarget.map(Int.init)
        )
    }
}
