import Foundation
import Shared

/// Process-lifetime owner. Only weights are downloaded; inference uses system Core ML.
@MainActor
final class QuickAddModelService {
    static let shared = QuickAddModelService()
    private var session: QuickAddModelSession?
    private var sessionResource: String?
    private var preparation: _Concurrency.Task<Bool, Never>?
    private var requestedResource: String?
    private var generation = UUID()
    private var ready = false
    private var idleStatus = QuickAddModelDownloadStatus()

    func prepare(backend: QuickAddBackend = .current,
                 language: String = Locale.preferredLanguages.first ?? "zh") async -> Bool {
        let resource = backend.manifestResource(language: language)
        if ready, sessionResource == resource, status().phase == "READY" { return true }
        if let preparation, requestedResource == resource { return await preparation.value }
        let previous = preparation
        let ticket = UUID()
        generation = ticket
        requestedResource = resource
        ready = false
        let task = _Concurrency.Task { @MainActor in
            // A different configuration waits for the old native operation before closing it.
            // Never close a model while its preparation still owns its mutex.
            if let previous { _ = await previous.value }
            guard generation == ticket else { return false }
            let oldSession = session
            session = nil
            sessionResource = nil
            try? await oldSession?.close()
            guard generation == ticket else { return false }
            idleStatus = QuickAddModelDownloadStatus(phase: resource == nil ? "RULES" : "CHECKING")
            guard let resource else { return false }
            do {
                guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
                    idleStatus = QuickAddModelDownloadStatus(phase: "FAILED")
                    return false
                }
                let config = try await _Concurrency.Task.detached { try String(contentsOf: url, encoding: .utf8) }.value
                guard generation == ticket else { return false }
                let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true)
                let active = QuickAddModelSession(cacheDirectory: directory.path, platform: "ios", manifestJson: config)
                session = active
                sessionResource = resource
                let result = try await active.prepare().boolValue
                guard generation == ticket else { return false }
                ready = result
                return result
            } catch {
                guard generation == ticket else { return false }
                let failed = session
                session = nil
                sessionResource = nil
                ready = false
                idleStatus = QuickAddModelDownloadStatus(phase: "FAILED")
                try? await failed?.close()
                return false
            }
        }
        preparation = task
        let result = await task.value
        guard generation == ticket else { return false }
        preparation = nil
        return result
    }

    func status() -> QuickAddModelDownloadStatus {
        guard let session else { return idleStatus }
        return (try? JSONDecoder().decode(QuickAddModelDownloadStatus.self, from: Data(session.statusJson().utf8))) ?? idleStatus
    }

    func recognize(_ text: String, kind: String, backend: QuickAddBackend,
                   language: String, timezone: String) async throws -> QuickAddDraft? {
        let resource = backend.manifestResource(language: language)
        guard ready, let session, resource != nil, resource == sessionResource else { return nil }
        let ticket = generation
        let json = try await session.recognizeJson(text: text, kind: kind, timezone: timezone)
        guard generation == ticket, ready, self.session === session, sessionResource == resource else { return nil }
        return try QuickAddDraft.decode(json)
    }

}

struct QuickAddModelDownloadStatus: Decodable {
    var phase = "UNCONFIGURED"
    var downloadedBytes: Double = 0
    var totalBytes: Double = 0
    var progress: Double { totalBytes > 0 ? min(1, max(0, downloadedBytes / totalBytes)) : 0 }
    var retryable: Bool { phase == "FAILED" || phase == "CANCELLED" }
    var label: String {
        switch phase {
        case "RULES": return "当前使用规则识别"
        case "CHECKING": return "正在检查识别模型缓存"
        case "DOWNLOADING": return "正在下载识别模型 · \(Int(progress * 100))%"
        case "LOADING": return "正在加载识别模型"
        case "READY": return "端侧识别模型已就绪"
        case "FAILED": return "模型不可用，当前使用规则识别"
        case "CANCELLED": return "模型下载已暂停，当前使用规则识别"
        default: return "模型尚未配置，当前使用规则识别"
        }
    }
}
