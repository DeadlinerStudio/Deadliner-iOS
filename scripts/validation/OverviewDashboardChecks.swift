import Foundation

actor Counter {
    var value = 0
    func add() { value += 1 }
}
@main struct OverviewDashboardChecks {
    static func main() async throws {
        let october = OverviewPeriod.date("2026-10-01")!
        let now = OverviewPeriod.date("2026-10-13")!
        precondition(OverviewPeriod.comparisonDay(month: october, now: now) == 13)
        precondition(OverviewPeriod.comparisonDay(month: OverviewPeriod.date("2024-02-01")!, now: now) == 29)
        precondition(OverviewPeriod.key(OverviewPeriod.shifted(OverviewPeriod.date("2026-01-01")!, by: -1)) == "2025-12-01")
        let result = OverviewPeriod.comparison(current: Array(repeating: 2, count: 31), previous: Array(repeating: 1, count: 30), day: 13)
        precondition(result.direction == 1 && result.text.contains("100.0%"))
        precondition(OverviewPeriod.comparison(current: [2], previous: [0], day: 1).text.contains("新增 2"))
        precondition(OverviewPeriod.comparison(current: [0], previous: [0], day: 1).direction == 0)
        precondition(OverviewPeriod.comparison(current: [1], previous: [2], day: 1).direction == -1)
        precondition(OverviewPeriod.comparison(current: Array(repeating: 1, count: 31), previous: Array(repeating: 1, count: 28), day: 31).text.contains("10.7%"))
        let instant = ISO8601DateFormatter().date(from: "2026-10-13T12:00:00Z")!
        precondition(OverviewPeriod.key(instant, timeZone: TimeZone(secondsFromGMT: 14 * 3600)!) == "2026-10-14")
        precondition(OverviewPeriod.key(instant, timeZone: TimeZone(secondsFromGMT: -12 * 3600)!) == "2026-10-13")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = MonthlyInsightRepository(directory: directory)
        let counter = Counter()
        let month = OverviewPeriod.key(OverviewPeriod.shifted(Date(), by: -1), format: "yyyy-MM")
        let generate: @Sendable () async throws -> MonthlyAnalysisResult = {
            await counter.add()
            try await _Concurrency.Task.sleep(for: .milliseconds(80))
            return MonthlyAnalysisResult(month: month, summary: "A real saved fixture", keywords: ["fixture"])
        }
        async let first = repo.resolve(month: month, retry: false, unavailableReason: nil, generate: generate)
        async let second = repo.resolve(month: month, retry: false, unavailableReason: nil, generate: generate)
        _ = await (first, second)
        let count1 = await counter.value
        precondition(count1 == 1)
        let restarted = MonthlyInsightRepository(directory: directory)
        if case .success(let saved) = await restarted.resolve(month: month, retry: true, unavailableReason: "Disabled", generate: generate) {
            precondition(saved.summary == "A real saved fixture")
        } else { preconditionFailure("Restart must preserve successful cache") }
        let count2 = await counter.value
        precondition(count2 == 1)
        let failedMonth = OverviewPeriod.key(OverviewPeriod.shifted(Date(), by: -2), format: "yyyy-MM")
        let failing: @Sendable () async throws -> MonthlyAnalysisResult = { await counter.add(); throw NSError(domain: "Fixture", code: 1) }
        _ = await repo.resolve(month: failedMonth, retry: false, unavailableReason: nil, generate: failing)
        _ = await restarted.resolve(month: failedMonth, retry: false, unavailableReason: nil, generate: failing)
        let count3 = await counter.value
        precondition(count3 == 2)
        _ = await repo.resolve(month: failedMonth, retry: true, unavailableReason: nil, generate: failing)
        let count4 = await counter.value
        precondition(count4 == 3)
        let pendingMonth = OverviewPeriod.key(Date(), format: "yyyy-MM")
        _ = await repo.resolve(month: pendingMonth, retry: true, unavailableReason: nil, generate: failing)
        let count5 = await counter.value
        precondition(count5 == 3)
        let thirdMonth = OverviewPeriod.key(OverviewPeriod.shifted(Date(), by: -3), format: "yyyy-MM")
        let caller = _Concurrency.Task {
            await repo.resolve(month: thirdMonth, retry: false, unavailableReason: nil) {
                try await _Concurrency.Task.sleep(for: .milliseconds(100))
                return MonthlyAnalysisResult(month: thirdMonth, summary: "Survives caller cancellation", keywords: [])
            }
        }
        try await _Concurrency.Task.sleep(for: .milliseconds(20)); caller.cancel()
        _ = await caller.value
        if case .success = await restarted.resolve(month: thirdMonth, retry: false, unavailableReason: nil, generate: failing) {} else { preconditionFailure("Caller cancellation must preserve generation") }
        let fourthMonth = OverviewPeriod.key(OverviewPeriod.shifted(Date(), by: -4), format: "yyyy-MM")
        let badDirectory = directory.appendingPathComponent("not-a-directory")
        try Data("fixture".utf8).write(to: badDirectory)
        let unwritable = MonthlyInsightRepository(directory: badDirectory)
        _ = await unwritable.resolve(month: fourthMonth, retry: false, unavailableReason: nil, generate: failing)
        let storageCount = await counter.value
        precondition(storageCount == 3, "Storage failure must prevent an AI request")
        print("PASS: date boundaries, short/leap months, same-period comparison, zero base, per-month persistence, concurrency, failure/retry, month gate, cancellation")
    }
}
