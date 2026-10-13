//
//  OverviewViewModel.swift
//  Deadliner
//
//  SwiftUI presentation projection of the shared KMP Overview state.
//

import Combine
import Foundation
import SwiftUI
import UIKit

#if canImport(Shared)
import Shared

enum OverviewCard: String, CaseIterable, Codable {
    case activeStats = "ACTIVE_STATS"
    case completionTime = "COMPLETION_TIME"
    case historyStats = "HISTORY_STATS"
}

enum TrendCard: String, CaseIterable, Codable {
    case dailyTrend = "DAILY_TREND"
    case monthlyTrend = "MONTHLY_TREND"
    case weeklyTrend = "WEEKLY_TREND"
    case contributionHeatmap = "CONTRIBUTION_HEATMAP"
}

struct DailyStat: Identifiable {
    let id = UUID()
    let date: String
    let completedCount: Int
    let overdueCount: Int
}

struct ContributionDay: Identifiable {
    let id: String
    let date: Date
    let count: Int
}

struct MonthlyStat: Identifiable {
    let id: String
    let month: String
    let totalCount: Int
    let completedCount: Int
    let overdueCompletedCount: Int
}

struct WeeklyStat: Identifiable {
    let id: String
    let weekLabel: String
    let completedCount: Int
}

struct Metric: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let change: String?
    let isDown: Bool?
}

private struct MonthlyAnalysisContext: Sendable {
    let monthKey: String
    let monthLabel: String
}

@MainActor
final class OverviewViewModel: ObservableObject {
    @Published private(set) var focus: FocusOverviewStatistics?
    @Published var isLoading = true
    @Published var todayCompleted = 0
    @Published var todayTodo = 0
    @Published var todayOverdue = 0
    @Published var activeAbandoned = 0
    @Published var historyStats: [String: Int] = [:]
    @Published var completionTimeStats: [(String, Int)] = []
    @Published var dailyStats: [DailyStat] = []
    @Published var monthlyStats: [MonthlyStat] = []
    @Published var weeklyStats: [WeeklyStat] = []
    @Published private(set) var contributionLoading = true
    @Published private(set) var contributionError: String?
    @Published var contributionStats: [ContributionDay] = []
    @Published var lastMonthDailyStats: [DailyStat] = []
    @Published var lastMonthName = ""
    @Published var monthlyAnalysis: MonthlyAnalysisResult?
    @Published var isAnalyzing = false
    @Published var metrics: [Metric] = []
    @Published var overviewCardOrder: [OverviewCard] = [.activeStats, .completionTime, .historyStats]
    @Published var trendCardOrder: [TrendCard] = [.contributionHeatmap, .dailyTrend, .monthlyTrend, .weeklyTrend]

    @Published var selectedMonth = OverviewPeriod.monthStart(Date())
    @Published private(set) var monthState: OverviewMonthUiState?
    @Published private(set) var comparisonLoading = true
    @Published private(set) var previousMonthState: OverviewMonthUiState?
    @Published private(set) var monthLoading = true
    @Published private(set) var monthError: String?
    @Published private(set) var taskError: String?
    @Published private(set) var focusError: String?
    @Published private(set) var focusLoading = true
    @Published private(set) var focusSessions: [FocusSession] = []
    @Published private(set) var focusManagementStatistics: FocusStatisticsSnapshot?
    @Published private(set) var managementError: String?
    @Published private(set) var managementLoading = true
    @Published private(set) var insightError: String?
    private var currentMonthKey = OverviewPeriod.key(Date(), format: "yyyy-MM")
    private var selectedMonthKey = OverviewPeriod.key(Date(), format: "yyyy-MM")
    private var focusDurationByDay: [String: Int64] = [:]
    private var annualGeneration = 0
    private var monthGeneration = 0
    private var analysisRequestMonth: String?

    var monthTitle: String { "\(OverviewPeriod.calendar.component(.month, from: selectedMonth))月总览" }
    var monthSubtitle: String {
        "\(OverviewPeriod.calendar.component(.year, from: selectedMonth))年 · " + (canGoForward ? "历史月份" : "本月进行中")
    }
    var canGoForward: Bool { selectedMonth < OverviewPeriod.monthStart(Date()) }
    var comparison: (text: String, direction: Int)? {
        guard let monthState, let previousMonthState else { return nil }
        return OverviewPeriod.comparison(current: monthState.daily.map { Int($0.completedCount) },
            previous: previousMonthState.daily.map { Int($0.completedCount) },
            day: OverviewPeriod.comparisonDay(month: selectedMonth, now: Date()))
    }
    var reviewMonthLabel: String {
        guard let lastMonthStart, let date = OverviewPeriod.date(lastMonthStart) else { return "上月" }
        return OverviewPeriod.key(date, format: "yyyy年M月")
    }
    func changeMonth(by offset: Int) {
        let next = OverviewPeriod.shifted(selectedMonth, by: offset)
        guard next <= OverviewPeriod.monthStart(Date()), OverviewPeriod.calendar.component(.year, from: next) >= 1900 else { return }
        selectedMonth = next
        selectedMonthKey = OverviewPeriod.key(next, format: "yyyy-MM")
        loadMonth()
    }
    func refreshForClockChange() { loadData() }
    func retryInsight() {
        guard let context = monthlyAnalysisContext else { return }
        _Concurrency.Task { await resolveMonthlyAnalysis(context: context, retry: true) }
    }
    func mutateFocusSession(uid: String, seconds: Int64?, completion: @escaping (String?) -> Void) {
        guard let bridge else { completion("数据尚未就绪，请重试"); return }
        bridge.mutateFocusSession(uid: uid, seconds: seconds) { [weak self] outcome, error in
            guard error == nil, outcome == .applied || outcome == .noOp else {
                completion(error ?? FocusTimerFormatting.outcomeMessage(outcome) ?? "操作失败，请重试")
                return
            }
            PersistenceChangePublisher.publish(.init(resourceKinds: [.task, .habit, .habitRecord]))
            self?.loadData()
            FocusTimerPresentationModel.shared.refresh()
            completion(nil)
        }
    }
    func focusSeconds(on date: String) -> Int64 { focusDurationByDay[date] ?? 0 }
    private func loadMonth() {
        guard let bridge else { return }
        monthGeneration += 1
        let generation = monthGeneration
        monthLoading = true
        monthError = nil
        monthState = nil
        previousMonthState = nil
        comparisonLoading = true
        let month = OverviewPeriod.key(selectedMonth)
        bridge.loadMonth(month, onState: { [weak self] state in
            guard let self, self.monthGeneration == generation else { return }
            self.monthState = state
            self.monthLoading = false
        }, onError: { [weak self] error in
            guard let self, self.monthGeneration == generation else { return }
            self.monthError = error
            self.monthLoading = false
        })
        bridge.loadMonth(OverviewPeriod.key(OverviewPeriod.shifted(selectedMonth, by: -1)), onState: { [weak self] state in
            guard let self, self.monthGeneration == generation else { return }
            self.previousMonthState = state
            self.comparisonLoading = false
        }, onError: { [weak self] _ in
            guard let self, self.monthGeneration == generation else { return }
            self.previousMonthState = nil
            self.comparisonLoading = false
        })
    }

    private var bridge: KMPOverviewViewModelBridge?
    private var cancellables = Set<AnyCancellable>()
    private var lastMonthStart: String?
    private var lastMonthCompletedTaskTitles: [String] = []
    private var bridgeGeneration = 0
    private var snapshotLoadInFlight = false
    private var snapshotReloadPending = false

    init() {
        overviewLog("view model init")
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            self.overviewLog("load sort order begin")
            await loadSortOrder()
            self.overviewLog("load sort order complete; bridge start begin")
            await startBridge()
        }

        NotificationCenter.default.publisher(for: .persistenceDataChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard event.object is PersistenceChangeEvent else { return }
                self?.loadData()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.loadData() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .ddlRequestMonthlyAnalysis)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                _Concurrency.Task { @MainActor [weak self] in
                    guard let self, let context = self.monthlyAnalysisContext else { return }
                    await self.resolveMonthlyAnalysis(context: context, retry: true)
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        let line = "[KMP][Overview] view model deinit"
        print(line)
        _Concurrency.Task { @MainActor in SyncDebugLog.log(line) }
    }

    func loadData() {
        let current = OverviewPeriod.monthStart(Date())
        if selectedMonthKey == currentMonthKey {
            selectedMonth = current
        } else {
            selectedMonth = min(OverviewPeriod.date(selectedMonthKey + "-01") ?? current, current)
        }
        currentMonthKey = OverviewPeriod.key(current, format: "yyyy-MM")
        selectedMonthKey = OverviewPeriod.key(selectedMonth, format: "yyyy-MM")
        overviewLog("refresh requested generation=\(bridgeGeneration)")
        isLoading = true
        guard let bridge else { return }
        requestSnapshot(from: bridge, generation: bridgeGeneration)
    }

    func onCardMove(tab: String, from: Int, to: Int) {
        if tab == "OVERVIEW" {
            overviewCardOrder.move(fromOffsets: IndexSet(integer: from), toOffset: to)
            let order = overviewCardOrder.map(\.rawValue)
            _Concurrency.Task { await LocalValues.shared.setOverviewCardOrder(order) }
        } else {
            trendCardOrder.move(fromOffsets: IndexSet(integer: from), toOffset: to)
            let order = trendCardOrder.map(\.rawValue)
            _Concurrency.Task { await LocalValues.shared.setTrendCardOrder(order) }
        }
    }

    private func startBridge() async {
        overviewLog("bridge replace begin generation=\(bridgeGeneration)")
        bridge?.close()
        bridgeGeneration &+= 1
        let generation = bridgeGeneration
        let bridge = await KMPOverviewViewModelBridge.make()
        overviewLog("bridge created generation=\(generation)")
        self.bridge = bridge
        snapshotLoadInFlight = false
        snapshotReloadPending = false
        requestSnapshot(from: bridge, generation: generation)
        overviewLog("bridge snapshot requested generation=\(generation)")
    }

    private func requestSnapshot(from bridge: KMPOverviewViewModelBridge, generation: Int) {
        guard !snapshotLoadInFlight else {
            snapshotReloadPending = true
            overviewLog("snapshot coalesced generation=\(generation)")
            return
        }

        snapshotLoadInFlight = true
        loadMonth()
        focusLoading = true
        focusError = nil
        bridge.loadFocusSafely(onState: { [weak self] focus in
            guard let self, self.bridgeGeneration == generation else { return }
            self.focus = focus
            self.focusLoading = false
        }, onError: { [weak self] error in
            self?.focus = nil
            self?.focusError = error
            self?.focusLoading = false
        })
        managementLoading = true
        managementError = nil
        bridge.loadFocusManagement(onState: { [weak self] sessions, statistics in
            guard let self else { return }
            self.focusSessions = sessions
            var totals: [String: Int64] = [:]
            for session in sessions {
                guard let start = DeadlineDateParser.safeParseOptional(session.startedAt) else { continue }
                totals[OverviewPeriod.key(start), default: 0] += session.durationSeconds
            }
            self.focusDurationByDay = totals
            self.focusManagementStatistics = statistics
            self.managementLoading = false
        }, onError: { [weak self] error in
            self?.focusSessions = []
            self?.focusDurationByDay = [:]
            self?.focusManagementStatistics = nil
            self?.managementError = error
            self?.managementLoading = false
        })
        bridge.load { [weak self] state in
            guard let self else { return }
            self.snapshotLoadInFlight = false
            guard self.bridgeGeneration == generation else { return }

            let errorDescription = state.error ?? "nil"
            self.overviewLog(
                "snapshot received generation=\(generation) loading=\(state.isLoading) "
                    + "daily=\(state.daily.count) monthly=\(state.monthly.count) contribution=\(state.contribution.count) error=\(errorDescription)"
            )
            self.apply(state)

            if self.snapshotReloadPending {
                self.snapshotReloadPending = false
                self.requestSnapshot(from: bridge, generation: generation)
            }
        }
    }

    private func apply(_ state: OverviewUiState) {
        overviewLog(
            "apply begin loading=\(state.isLoading) daily=\(state.daily.count) monthly=\(state.monthly.count) "
                + "weekly=\(state.weekly.count) contribution=\(state.contribution.count)"
        )
        taskError = state.error
        if state.error != nil { isLoading = false; return }
        let summary = state.summary
        todayCompleted = Int(summary.completedToday)
        todayTodo = Int(summary.pendingDueFromNow)
        todayOverdue = Int(summary.overdueToday)
        activeAbandoned = Int(summary.activeAbandoned)

        let history = state.history
        historyStats = [
            "累计完成": Int(history.completed),
            "当前待办": Int(history.pending),
            "累计放弃": Int(history.abandoned),
            "累计逾期": Int(history.overdue),
        ]
        completionTimeStats = state.completionBuckets.map {
            (completionPeriodLabel($0.period), Int($0.completedCount))
        }
        dailyStats = state.daily.map {
            DailyStat(date: shortDate($0.date), completedCount: Int($0.completedCount), overdueCount: Int($0.overdueCount))
        }
        monthlyStats = state.monthly.suffix(6).map {
            MonthlyStat(
                id: $0.monthStart,
                month: monthLabel($0.monthStart),
                totalCount: Int($0.totalCount),
                completedCount: Int($0.completedCount),
                overdueCompletedCount: Int($0.overdueCompletedCount)
            )
        }
        weeklyStats = state.weekly.enumerated().map { index, stat in
            let remaining = state.weekly.count - index - 1
            return WeeklyStat(
                id: stat.weekStart,
                weekLabel: remaining == 0 ? "本周" : "\(remaining)周前",
                completedCount: Int(stat.completedCount)
            )
        }
        if state.error == nil { loadAnnualContribution() }
        overviewLog("apply primary projections complete")

        let lastMonth = state.lastMonth
        lastMonthDailyStats = lastMonth.daily.map {
            DailyStat(date: dayLabel($0.date), completedCount: Int($0.completedCount), overdueCount: Int($0.overdueCount))
        }
        lastMonthStart = lastMonth.monthStart
        lastMonthName = lastMonth.monthStart.map(monthLabel) ?? ""
        metrics = presentationMetrics(lastMonth.metrics)
        lastMonthCompletedTaskTitles = lastMonth.completedTaskTitles
        isLoading = state.isLoading
        overviewLog("apply complete loading=\(isLoading) metrics=\(metrics.count) lastMonthDays=\(lastMonthDailyStats.count)")

        if state.error == nil, let context = monthlyAnalysisContext {
            if monthlyAnalysis?.month != context.monthKey {
                monthlyAnalysis = nil
            }
            _Concurrency.Task { [weak self] in
                guard let self else { return }
                await self.resolveMonthlyAnalysis(context: context, retry: false)
            }
        } else {
            monthlyAnalysis = nil
        }
    }

    /// Expand the legacy 150-day projection to the current year using shared monthly activity.
    private func loadAnnualContribution() {
        guard let bridge else { return }
        annualGeneration += 1
        let generation = annualGeneration
        contributionLoading = true
        contributionError = nil
        let today = OverviewPeriod.calendar.startOfDay(for: Date())
        let year = OverviewPeriod.calendar.component(.year, from: today)
        let count = OverviewPeriod.calendar.component(.month, from: today)
        var pending = count
        var days: [ContributionDay] = []
        for month in 1...count {
            bridge.loadMonth(String(format: "%04d-%02d-01", year, month), onState: { [weak self] state in
                guard let self, self.annualGeneration == generation else { return }
                days += state.daily.compactMap { point in
                    guard let date = OverviewPeriod.date(point.date), date <= today else { return nil }
                    return ContributionDay(id: point.date, date: date, count: Int(point.completedCount))
                }
                pending -= 1
                if pending == 0 {
                    self.contributionLoading = false
                    if self.contributionError == nil { self.contributionStats = days.sorted { $0.date < $1.date } }
                }
            }, onError: { [weak self] error in
                guard let self, self.annualGeneration == generation else { return }
                self.contributionError = error
                pending -= 1
                if pending == 0 { self.contributionLoading = false }
            })
        }
    }

    private func loadSortOrder() async {
        let savedOverview = await LocalValues.shared.getOverviewCardOrder()
        var loadedOverview = savedOverview.compactMap(OverviewCard.init(rawValue:))
        OverviewCard.allCases.filter { !loadedOverview.contains($0) }.forEach { loadedOverview.append($0) }
        overviewCardOrder = loadedOverview

        let savedTrend = await LocalValues.shared.getTrendCardOrder()
        var loadedTrend = savedTrend.compactMap(TrendCard.init(rawValue:))
        TrendCard.allCases.filter { !loadedTrend.contains($0) }.forEach { loadedTrend.append($0) }
        trendCardOrder = loadedTrend
    }

    private func overviewLog(_ message: String) {
        let line = "[KMP][Overview] \(message)"
        print(line)
        SyncDebugLog.log(line)
    }

    private var monthlyAnalysisContext: MonthlyAnalysisContext? {
        guard let monthStart = lastMonthStart else { return nil }
        return MonthlyAnalysisContext(monthKey: String(monthStart.prefix(7)), monthLabel: monthLabel(monthStart))
    }

    private var canAutoGenerateMonthlyAnalysis: Bool {
        let defaults = UserDefaults.standard
        let isConfigured = defaults.object(forKey: "settings.ai.is_configured") as? Bool ?? false
        let isEnabled = defaults.object(forKey: "settings.ai.enabled") as? Bool ?? true
        let tier = UserTier(rawValue: defaults.string(forKey: "userTier") ?? UserTier.free.rawValue) ?? .free
        return isConfigured && isEnabled && tier != .free
    }

    private func resolveMonthlyAnalysis(context: MonthlyAnalysisContext, retry: Bool) async {
        guard monthlyAnalysis?.month != context.monthKey, analysisRequestMonth != context.monthKey else { return }
        analysisRequestMonth = context.monthKey
        isAnalyzing = true
        insightError = nil
        let metricsSummary = metrics.map { "\($0.label): \($0.value) (\($0.change ?? "无变化"))" }.joined(separator: "\n")
        let titles = lastMonthCompletedTaskTitles
        let legacy = await LocalValues.shared.getMonthlyAnalysis()
        let unavailable = canAutoGenerateMonthlyAnalysis ? nil : "AI 未配置、已关闭或当前方案不支持月度分析"
        let result = await MonthlyInsightRepository.shared.resolve(month: context.monthKey, retry: retry,
            unavailableReason: unavailable, legacyJSON: legacy) {
                let response = try await KMPLifiCoreBridge.shared.generateMonthlyAnalysis(
                    monthName: context.monthLabel, metricsSummary: metricsSummary, completedTaskNames: titles)
                return MonthlyAnalysisResult(month: context.monthKey, summary: response.summary, keywords: response.keywords)
            }
        guard analysisRequestMonth == context.monthKey else { return }
        analysisRequestMonth = nil
        isAnalyzing = false
        guard monthlyAnalysisContext?.monthKey == context.monthKey else { return }
        switch result {
        case .success(let analysis): monthlyAnalysis = analysis
        case .unavailable(let message): insightError = message
        }
    }

    private func presentationMetrics(_ metrics: OverviewMonthlyMetrics) -> [Metric] {
        let baseMetrics = [
            percentageMetric("上月任务数", current: Double(metrics.totalTasks), previous: Double(metrics.previousTotalTasks), value: "\(metrics.totalTasks)"),
            percentageMetric("上月完成", current: Double(metrics.completedTasks), previous: Double(metrics.previousCompletedTasks), value: "\(metrics.completedTasks)"),
            percentageMetric("上月完成率", current: metrics.completionRate, previous: metrics.previousCompletionRate, value: String(format: "%.1f%%", metrics.completionRate)),
            percentageMetric("上月逾期数", current: Double(metrics.overdueTasks), previous: Double(metrics.previousOverdueTasks), value: "\(metrics.overdueTasks)"),
        ]
        let activePeriodMetric: [Metric] = metrics.mostActivePeriod.map { period in
            [Metric(label: "最活跃时段", value: completionPeriodLabel(period), change: "完成 \(metrics.mostActivePeriodCompletedCount) 个", isDown: nil)]
        } ?? []
        let averageDurationMetric: [Metric] = metrics.averageCompletionMinutes.map { duration in
            let minutes = Int(duration.intValue)
            let value = minutes < 60 ? "\(minutes) 分钟" : String(format: "%.1f 小时", Double(minutes) / 60)
            return [Metric(label: "平均耗时", value: value, change: nil, isDown: nil)]
        } ?? []

        return baseMetrics + activePeriodMetric + averageDurationMetric
    }

    private func percentageMetric(_ label: String, current: Double, previous: Double, value: String) -> Metric {
        guard previous > 0 else { return Metric(label: label, value: value, change: nil, isDown: nil) }
        let change = abs(current - previous) / previous * 100
        return Metric(label: label, value: value, change: String(format: "%.1f%%", change), isDown: current < previous)
    }

    private func completionPeriodLabel(_ period: OverviewCompletionPeriod) -> String {
        switch String(describing: period).uppercased() {
        case let value where value.contains("OVERNIGHT"): return "深夜"
        case let value where value.contains("MORNING"): return "上午"
        case let value where value.contains("AFTERNOON"): return "下午"
        default: return "晚上"
        }
    }

    private func isoDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func shortDate(_ value: String) -> String {
        guard let date = isoDate(value) else { return value }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }

    private func dayLabel(_ value: String) -> String {
        guard let date = isoDate(value) else { return value }
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func monthLabel(_ value: String) -> String {
        guard let date = isoDate(value) else { return value }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月"
        return formatter.string(from: date)
    }
}
#endif
