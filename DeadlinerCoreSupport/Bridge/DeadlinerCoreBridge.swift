//
//  DeadlinerCoreBridge.swift
//  Deadliner
//
//  Created by Codex on 2026/3/19.
//

import Foundation
import Observation

enum DeadlinerCoreBridgeEvent {
    case thinking(agentName: String)
    case textStream(chunk: String)
    case toolRequest(AIToolRequest)
    case finish(DeadlinerCoreFinishPayload)
    case error(String)
}

struct DeadlinerCoreFinishPayload {
    let primaryIntent: String
    let tasks: [AITask]
    let habits: [AIHabit]
    let chatResponse: String?
    let sessionSummary: String?
    let memorySyncJson: String?
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

    func initializeIfNeeded() async {
        guard core == nil else { return }

        let apiKey = await LocalValues.shared.getAIApiKey()
        let baseUrl = await LocalValues.shared.getAIBaseUrl()
        let modelId = await LocalValues.shared.getAIModel()
        let storagePath = makeStoragePath()

        let core = DeadlinerCore(
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
        await core.replaceMemorySnapshot(snapshotJson: MemoryBank.shared.exportSnapshotJson())

        self.core = core
        self.callbackProxy = proxy
        self.isReady = true
        self.lastEventSummary = "DeadlinerCore initialized"
    }

    func processInput(_ text: String) async {
        guard let core else { return }
        await core.processInput(text: text)
    }

    func replaceMemorySnapshot(_ snapshotJson: String) async {
        guard let core else { return }
        await core.replaceMemorySnapshot(snapshotJson: snapshotJson)
    }

    func submitToolResult(id: String, resultJson: String) async {
        guard let core else { return }
        await core.submitToolResult(id: id, resultJson: resultJson)
    }

    func exportMemorySnapshot() -> String? {
        core?.exportMemorySnapshot()
    }

    func setEventHandler(_ handler: @escaping (DeadlinerCoreBridgeEvent) -> Void) {
        eventHandler = handler
    }

    func clearEventHandler() {
        eventHandler = nil
    }

    private func handle(event: CoreEvent) {
        switch event {
        case .onThinking(let agentName):
            lastEventSummary = "Thinking: \(agentName)"
            eventHandler?(.thinking(agentName: agentName))
        case .onTextStream(let chunk):
            lastEventSummary = "Streaming: \(chunk.prefix(32))"
            eventHandler?(.textStream(chunk: chunk))
        case .onToolRequest(let id, let toolName, let argsJson):
            let normalizedToolName = ToolCallExecutor.shared.normalizeToolName(toolName)
            lastEventSummary = "Tool request \(normalizedToolName) [\(id)]"
            let args = decodeReadTasksArgs(from: argsJson)
            eventHandler?(.toolRequest(AIToolRequest(
                id: id,
                tool: normalizedToolName,
                args: args,
                reason: nil
            )))
        case .onFinish(let primaryIntent, let tasks, let habits, let chatResponse, let sessionSummary, let memorySyncJson):
            lastEventSummary = "Finished: \(primaryIntent)"
            if let memorySyncJson, !memorySyncJson.isEmpty {
                let applied = MemoryBank.shared.applySyncPayloadJson(memorySyncJson)
                if !applied {
                    let snapshotJson = MemoryBank.shared.exportSnapshotJson()
                    Task {
                        await self.replaceMemorySnapshot(snapshotJson)
                    }
                }
            }
            eventHandler?(.finish(DeadlinerCoreFinishPayload(
                primaryIntent: primaryIntent,
                tasks: (tasks ?? []).map(\.asAppTask),
                habits: (habits ?? []).map(\.asAppHabit),
                chatResponse: chatResponse,
                sessionSummary: sessionSummary,
                memorySyncJson: memorySyncJson
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

    private func decodeReadTasksArgs(from argsJson: String) -> ReadTasksArgs {
        guard let data = argsJson.data(using: .utf8),
              let args = try? JSONDecoder().decode(ReadTasksArgs.self, from: data) else {
            return ReadTasksArgs(
                timeRangeDays: 7,
                status: "OPEN",
                keywords: nil,
                limit: 20,
                sort: "DUE_ASC"
            )
        }
        return args
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
