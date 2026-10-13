import Foundation
import Shared

/// Process-lifetime owner. Only weights are downloaded; inference uses system Core ML.
@MainActor
final class QuickAddModelService {
    static let shared = QuickAddModelService()
    private var session: QuickAddModelSession?
    private var preparation: _Concurrency.Task<Bool, Never>?
    private var ready = false

    func prepare() async -> Bool {
        if ready && status().phase == "READY" { return true }
        if let preparation { return await preparation.value }
        let task = _Concurrency.Task { @MainActor in
            do {
                let config = await _Concurrency.Task.detached {
                    Bundle.main.url(forResource: Locale.preferredLanguages.first?.hasPrefix("en") == true ? "quick-add-model-en" : "quick-add-model", withExtension: "json")
                        .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
                }.value
                let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true)
                let active = session ?? QuickAddModelSession(cacheDirectory: directory.path, platform: "ios", manifestJson: config)
                session = active
                ready = try await active.prepare().boolValue
                return ready
            } catch { return false }
        }
        preparation = task
        let result = await task.value
        preparation = nil
        return result
    }

    func status() -> QuickAddModelDownloadStatus {
        guard let session else { return QuickAddModelDownloadStatus() }
        return (try? JSONDecoder().decode(QuickAddModelDownloadStatus.self, from: Data(session.statusJson().utf8))) ?? QuickAddModelDownloadStatus()
    }

    func recognize(_ text: String, kind: String) async throws -> QuickAddDraft? {
        guard ready, let session else { return nil }
        let json = try await session.recognizeJson(text: text, kind: kind, timezone: TimeZone.current.identifier)
        let result = try QuickAddDraft.decode(json)
        return result
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
