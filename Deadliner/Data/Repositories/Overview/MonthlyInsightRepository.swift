import Foundation

/// Application lifetime ownership: page disappearance never cancels an in-flight month.
actor MonthlyInsightRepository {
    static let shared = MonthlyInsightRepository()
    enum Result {
        case success(MonthlyAnalysisResult)
        case unavailable(String)
    }
    private struct Record: Codable {
        var attempted: Bool
        var analysis: MonthlyAnalysisResult?
    }
    private let directory: URL
    private var inFlight: [String: _Concurrency.Task<Result, Never>] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OverviewMonthlyReviews", isDirectory: true)
    }

    func resolve(month: String, retry: Bool, unavailableReason: String?, legacyJSON: String? = nil,
                 generate: @escaping @Sendable () async throws -> MonthlyAnalysisResult) async -> Result {
        guard let start = OverviewPeriod.date(month + "-01"), OverviewPeriod.key(start, format: "yyyy-MM") == month,
              start < OverviewPeriod.monthStart(Date()) else { return .unavailable("该月份尚未结束") }
        let url = directory.appendingPathComponent(month + ".json")
        var record: Record
        do {
            record = FileManager.default.fileExists(atPath: url.path)
                ? try JSONDecoder().decode(Record.self, from: Data(contentsOf: url)) : Record(attempted: false)
            if let analysis = record.analysis, valid(analysis, month: month) { return .success(analysis) }
            if let legacyJSON, let data = legacyJSON.data(using: .utf8),
               let analysis = try? JSONDecoder().decode(MonthlyAnalysisResult.self, from: data), valid(analysis, month: month) {
                try save(Record(attempted: true, analysis: analysis), to: url)
                return .success(analysis)
            }
        } catch { return .unavailable("复盘存储读取失败，请重试") }
        if let pending = inFlight[month] { return await pending.value }
        if let unavailableReason { return .unavailable(unavailableReason) }
        guard retry || !record.attempted else { return .unavailable("上次分析未完成，请点击重试") }
        do { try save(Record(attempted: true), to: url) }
        catch { return .unavailable("无法保存分析尝试，请重试") }
        let pending = _Concurrency.Task<Result, Never> {
            do {
                let analysis = try await generate()
                guard self.valid(analysis, month: month) else { return .unavailable("AI 未返回有效洞察，请重试") }
                try self.save(Record(attempted: true, analysis: analysis), to: url)
                return .success(analysis)
            } catch { return .unavailable("月度分析失败，请重试") }
        }
        inFlight[month] = pending
        let result = await pending.value
        inFlight[month] = nil
        return result
    }
    private func valid(_ analysis: MonthlyAnalysisResult, month: String) -> Bool {
        analysis.month == month && !analysis.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private func save(_ record: Record, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
    }
}
