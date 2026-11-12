import Foundation

private func expect(_ value: Bool, _ message: String = "Check failed") { precondition(value, message) }

// Native model boundary fixture: exercises production Swift service lifecycles
// without networking, Core ML or user data. This is not a real-model inference test.
enum HabitPeriod { case daily, weekly, monthly, ebbinghaus, once }
struct NativeBoolean { let boolValue: Bool }
@MainActor final class QuickAddModelSession {
    static var created = 0
    static var closed = 0
    static var preparing = 0
    static var failNext = false
    static var throwNext = false
    static var lastKind = ""
    let number: Int
    var phase = "CHECKING"
    init(cacheDirectory: String, platform: String, manifestJson: String) {
        Self.created += 1
        number = Self.created
    }
    func prepare() async throws -> NativeBoolean {
        Self.preparing += 1
        defer { Self.preparing -= 1 }
        try await Task.sleep(for: .milliseconds(30))
        if Self.throwNext {
            Self.throwNext = false
            throw CocoaError(.fileReadCorruptFile)
        }
        let success = !Self.failNext
        Self.failNext = false
        phase = success ? "READY" : "FAILED"
        return NativeBoolean(boolValue: success)
    }
    func close() async throws {
        expect(Self.preparing == 0, "Closed a native session during preparation")
        Self.closed += 1
    }
    func statusJson() -> String {
        "{\"phase\":\"\(phase)\",\"downloadedBytes\":0,\"totalBytes\":0}"
    }
    func recognizeJson(text: String, kind: String, timezone: String) async throws -> String {
        Self.lastKind = kind
        try await Task.sleep(for: .milliseconds(40))
        return "{\"kind\":\"TASK\",\"title\":\"\(text)\",\"note\":\"\",\"period\":\"DAILY\",\"targetCount\":1,\"weekdaysMask\":127,\"needsAI\":true,\"ready\":true,\"source\":\"MODEL\",\"message\":\"\",\"recognitionState\":\"READY_WITH_AI\"}"
    }
}

@main struct QuickAddKivoChecks {
    @MainActor static func main() async throws {
        let service = QuickAddModelService.shared
        _ = await service.prepare(backend: .rules, language: "zh")
        expect(QuickAddModelSession.created == 0 && service.status().phase == "RULES", "Rules touched native model")
        let first = Task { await service.prepare(backend: .kivo, language: "zh") }
        let duplicate = Task { await service.prepare(backend: .kivo, language: "zh") }
        expect(await first.value)
        expect(await duplicate.value)
        expect(QuickAddModelSession.created == 1, "Duplicate preparation created extra sessions")
        let oldRecognition = Task { try await service.recognize("读书", kind: "TASK", backend: .kivo, language: "zh", timezone: "Asia/Shanghai") }
        try await Task.sleep(for: .milliseconds(5))
        _ = await service.prepare(backend: .rules, language: "zh")
        expect(try await oldRecognition.value == nil, "Old inference escaped resource switch")
        expect(service.status().phase == "RULES" && QuickAddModelSession.closed == 1)
        let newKivo = Task { await service.prepare(backend: .kivo, language: "zh") }
        try await Task.sleep(for: .milliseconds(5))
        let original = Task { await service.prepare(backend: .original, language: "en") }
        expect(!(await newKivo.value), "Superseded preparation reported ready")
        expect(await original.value)
        let mismatched = try await service.recognize("报告", kind: "TASK", backend: .kivo, language: "zh", timezone: "Asia/Shanghai")
        expect(mismatched == nil, "Wrong model accepted current request")
        _ = await service.prepare(backend: .rules, language: "zh")
        QuickAddModelSession.failNext = true
        expect(!(await service.prepare(backend: .kivo, language: "zh")))
        expect(service.status().retryable)
        expect(await service.prepare(backend: .kivo, language: "zh"), "Retry did not rebuild failed session")
        _ = await service.prepare(backend: .rules, language: "zh")
        QuickAddModelSession.throwNext = true
        expect(!(await service.prepare(backend: .kivo, language: "zh")))
        expect(service.status().retryable, "Thrown native error lost retry state")
        expect(await service.prepare(backend: .kivo, language: "zh"))
        let review = try await service.recognize("交报告", kind: "TASK", backend: .kivo, language: "zh", timezone: "Asia/Shanghai")!
        var edits = QuickAddOverrides()
        edits.dueAt = Date()
        expect(edits.applying(to: review).needsAI && edits.applying(to: review).ready, "Manual deadline erased review state")
        var partial = review
        partial.ready = false
        partial.recognitionState = "KIVO_PARTIAL"
        expect(!edits.applying(to: partial).ready, "Manual deadline accepted hard-failed Kivo draft")
        edits.note = "用户备注"
        edits.removesReminder = true
        let retained = edits.applying(to: review)
        expect(retained.note == "用户备注" && retained.reminderTime == nil)
        print("Passed production Swift session switch/deduplication/stale inference/retry and Kivo manual-review regression checks")
    }
}
