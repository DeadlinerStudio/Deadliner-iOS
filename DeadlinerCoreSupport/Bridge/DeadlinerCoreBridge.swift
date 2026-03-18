//
//  DeadlinerCoreBridge.swift
//  Deadliner
//
//  Created by Codex on 2026/3/19.
//

import Foundation
import Observation

@MainActor
@Observable
final class DeadlinerCoreBridge {
    static let shared = DeadlinerCoreBridge()

    private(set) var isReady = false
    private(set) var lastEventSummary: String?

    private var core: DeadlinerCore?
    private var callbackProxy: DeadlinerCoreCallbackProxy?

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

    private func handle(event: CoreEvent) {
        switch event {
        case .onThinking(let agentName):
            lastEventSummary = "Thinking: \(agentName)"
        case .onTextStream(let chunk):
            lastEventSummary = "Streaming: \(chunk.prefix(32))"
        case .onToolRequest(let id, let toolName, _):
            lastEventSummary = "Tool request \(toolName) [\(id)]"
        case .onFinish(let primaryIntent, _, _, _, _, _):
            lastEventSummary = "Finished: \(primaryIntent)"
        case .onError(let message):
            lastEventSummary = "Error: \(message)"
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
