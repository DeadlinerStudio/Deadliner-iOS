//
//  OverviewViewModel.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/3/8.
//

import Foundation
import Combine
import SwiftUI

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
    let id = UUID()
    let date: Date
    let count: Int
}

struct MonthlyStat: Identifiable {
    let id = UUID()
    let month: String
    let totalCount: Int
    let completedCount: Int
    let overdueCompletedCount: Int
}

struct WeeklyStat: Identifiable {
    let id = UUID()
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

// DTO for background computation result
struct ComputedStats {
    let completedTodayCount: Int
    let todayTodoCount: Int
    let todayOverdueCount: Int
    let historyStats: [String: Int]
    let completionTimeStats: [(String, Int)]
    let overdueItems: [DDLItem]
    let dailyStats: [DailyStat]
    let monthlyStats: [MonthlyStat]
    let weeklyStats: [WeeklyStat]
    let contributionStats: [ContributionDay]
    let lastMonthDailyStats: [DailyStat]
    let metrics: [Metric]
}

@MainActor
final class OverviewViewModel: ObservableObject {
    @Published var isLoading = true
    
    @Published var todayCompleted = 0
    @Published var todayTodo = 0
    @Published var todayOverdue = 0
    @Published var historyStats: [String: Int] = [:]
    @Published var completionTimeStats: [(String, Int)] = []
    @Published var overdueItems: [DDLItem] = []
    
    @Published var dailyStats: [DailyStat] = []
    @Published var monthlyStats: [MonthlyStat] = []
    @Published var weeklyStats: [WeeklyStat] = []
    @Published var contributionStats: [ContributionDay] = []
    @Published var lastMonthDailyStats: [DailyStat] = []
    @Published var lastMonthName: String = ""
    @Published var monthlyAnalysis: MonthlyAnalysisResult? = nil
    @Published var isAnalyzing = false
    
    @Published var metrics: [Metric] = []
    @Published var allItems: [DDLItem] = []
    
    @Published var overviewCardOrder: [OverviewCard] = [.activeStats, .completionTime, .historyStats]
    @Published var trendCardOrder: [TrendCard] = [.contributionHeatmap, .dailyTrend, .monthlyTrend, .weeklyTrend]
    
    private let repo: TaskRepository
    private var cancellables = Set<AnyCancellable>()
    
    init(repo: TaskRepository = .shared) {
        self.repo = repo
        
        Task {
            await loadSortOrder()
            await loadData()
        }
        
        NotificationCenter.default.publisher(for: .ddlDataChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.loadData() }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .ddlRequestMonthlyAnalysis)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                print("[OverviewViewModel] Manual request for monthly analysis received")
                Task { 
                    let now = Date()
                    let calendar = Calendar.current
                    guard let firstDayOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                          let firstDayOfLastMonth = calendar.date(byAdding: .month, value: -1, to: firstDayOfThisMonth) else {
                        return
                    }
                    let monthKey = DateFormatter()
                    monthKey.dateFormat = "yyyy-MM"
                    let currentMonthKey = monthKey.string(from: firstDayOfLastMonth)
                    
                    await self.generateMonthlyAnalysis(items: self.allItems, monthKey: currentMonthKey, monthLabel: self.lastMonthName)
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadSortOrder() async {
        let savedOverview = await LocalValues.shared.getOverviewCardOrder()
        var loadedOverview = savedOverview.compactMap { OverviewCard(rawValue: $0) }
        for card in OverviewCard.allCases {
            if !loadedOverview.contains(card) {
                loadedOverview.append(card)
            }
        }
        self.overviewCardOrder = loadedOverview
        
        let savedTrend = await LocalValues.shared.getTrendCardOrder()
        var loadedTrend = savedTrend.compactMap { TrendCard(rawValue: $0) }
        for card in TrendCard.allCases {
            if !loadedTrend.contains(card) {
                loadedTrend.append(card)
            }
        }
        self.trendCardOrder = loadedTrend
    }
    
    func loadData() async {
        isLoading = true
        do {
            let items = try await repo.getDDLsByType(.task)
            self.allItems = items
            let now = Date()
            
            // Offload computations to background
            let stats = await Task.detached(priority: .userInitiated) { () -> ComputedStats in
                return await self.performBackgroundCalculations(items: items, now: now)
            }.value
            
            // Apply results back to main actor
            self.todayCompleted = stats.completedTodayCount
            self.todayTodo = stats.todayTodoCount
            self.todayOverdue = stats.todayOverdueCount
            self.historyStats = stats.historyStats
            self.completionTimeStats = stats.completionTimeStats
            self.overdueItems = stats.overdueItems
            self.dailyStats = stats.dailyStats
            self.monthlyStats = stats.monthlyStats
            self.weeklyStats = stats.weeklyStats
            self.contributionStats = stats.contributionStats
            self.lastMonthDailyStats = stats.lastMonthDailyStats
            self.metrics = stats.metrics
            
            let calendar = Calendar.current
            let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "M月"
            self.lastMonthName = monthFormatter.string(from: lastMonthDate)
            
            await loadMonthlyAnalysis(items: items, lastMonthName: self.lastMonthName, now: now)
            
        } catch {
            print("[OverviewViewModel] Load data error: \(error)")
        }
        isLoading = false
    }
    
    // DTO for pre-parsed item to avoid repeated parsing
    private struct ParsedItem {
        let item: DDLItem
        let startTime: Date?
        let endTime: Date?
        let completeTime: Date?
    }

    // Background calculation logic - optimized to avoid repeated O(N) operations
    private func performBackgroundCalculations(items: [DDLItem], now: Date) -> ComputedStats {
        let calendar = Calendar.current
        
        // 1. Pre-parse all items once
        let parsedItems = items.map { item in
            ParsedItem(
                item: item,
                startTime: DeadlineDateParser.safeParseOptional(item.startTime),
                endTime: DeadlineDateParser.safeParseOptional(item.endTime),
                completeTime: DeadlineDateParser.safeParseOptional(item.completeTime)
            )
        }
        
        let activeParsed = parsedItems.filter { !$0.item.isArchived }
        
        // 2. Snapshot stats
        let completedTodayCount = activeParsed.filter { it in
            guard let d = it.completeTime else { return false }
            return calendar.isDate(d, inSameDayAs: now) && it.item.isCompleted
        }.count
        
        let todayTodoCount = activeParsed.filter { it in
            if it.item.isCompleted { return false }
            guard let end = it.endTime else { return false }
            return end >= now
        }.count
        
        let todayOverdueCount = activeParsed.filter { it in
            if it.item.isCompleted { return false }
            guard let end = it.endTime else { return false }
            return calendar.isDate(end, inSameDayAs: now) && end < now
        }.count
        
        let historyCompleted = parsedItems.filter { $0.item.isCompleted }
        let historyIncomplete = parsedItems.filter { !$0.item.isCompleted }
        let historyOverdue = activeParsed.filter { it in
            if it.item.isCompleted { return false }
            guard let end = it.endTime else { return false }
            return end < now
        }
        
        let historyStats = [
            "累计完成": historyCompleted.count,
            "当前待办": historyIncomplete.count,
            "累计逾期": historyOverdue.count
        ]
        
        // 3. Completion Time Bucket
        var bucketMap: [String: Int] = [:]
        historyCompleted.forEach { it in
            if let date = it.completeTime {
                let hour = calendar.component(.hour, from: date)
                let bucket: String
                switch hour {
                case 0..<6: bucket = "深夜"
                case 6..<12: bucket = "上午"
                case 12..<18: bucket = "下午"
                default: bucket = "晚上"
                }
                bucketMap[bucket, default: 0] += 1
            }
        }
        let bucketOrder = ["深夜", "上午", "下午", "晚上"]
        let completionTimeStats = bucketOrder.map { bucket in
            (bucket, bucketMap[bucket] ?? 0)
        }
        
        // 4. Trends (Optimized methods)
        let dailyStats = self.computeDailyStats(items: parsedItems, days: 7, now: now)
        let monthlyStats = self.computeMonthlyStats(items: parsedItems, months: 12, now: now)
        let weeklyStats = self.computeWeeklyStats(items: parsedItems, weeks: 4, now: now)
        let contributionStats = self.computeContributionStats(items: parsedItems, days: 150, now: now)
        let lastMonthDailyStats = self.computeLastMonthDailyStats(items: parsedItems, now: now)
        let metrics = self.computeMetrics(items: parsedItems, now: now)
        
        return ComputedStats(
            completedTodayCount: completedTodayCount,
            todayTodoCount: todayTodoCount,
            todayOverdueCount: todayOverdueCount,
            historyStats: historyStats,
            completionTimeStats: completionTimeStats,
            overdueItems: historyOverdue.map { $0.item },
            dailyStats: dailyStats,
            monthlyStats: monthlyStats,
            weeklyStats: weeklyStats,
            contributionStats: contributionStats,
            lastMonthDailyStats: lastMonthDailyStats,
            metrics: metrics
        )
    }
    
    private func loadMonthlyAnalysis(items: [DDLItem], lastMonthName: String, now: Date) async {
        let calendar = Calendar.current
        guard let firstDayOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let firstDayOfLastMonth = calendar.date(byAdding: .month, value: -1, to: firstDayOfThisMonth) else {
            return
        }
        
        let monthKey = DateFormatter()
        monthKey.dateFormat = "yyyy-MM"
        let currentMonthKey = monthKey.string(from: firstDayOfLastMonth)
        
        if let json = await LocalValues.shared.getMonthlyAnalysis(),
           let data = json.data(using: .utf8) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let result = try decoder.decode(MonthlyAnalysisResult.self, from: data)
                if result.month == currentMonthKey {
                    self.monthlyAnalysis = result
                    return
                }
            } catch {
                print("[OverviewViewModel] Decode monthly analysis error: \(error)")
            }
        }
        
        await generateMonthlyAnalysis(items: items, monthKey: currentMonthKey, monthLabel: lastMonthName)
    }
    
    func generateMonthlyAnalysis(items: [DDLItem], monthKey: String, monthLabel: String) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        
        do {
            let calendar = Calendar.current
            let now = Date()
            guard let firstDayOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let firstDayOfLastMonth = calendar.date(byAdding: .month, value: -1, to: firstDayOfThisMonth),
                  let lastDayOfLastMonth = calendar.date(byAdding: .day, value: -1, to: firstDayOfThisMonth) else {
                isAnalyzing = false
                return
            }
            
            let lastMonthItems = items.filter { it in
                guard let d = DeadlineDateParser.safeParseOptional(it.endTime) else { return false }
                return d >= firstDayOfLastMonth && d <= lastDayOfLastMonth
            }
            
            let completedTaskNames = lastMonthItems.filter { $0.isCompleted }.map { $0.name }
            let metricsSummary = metrics.map { "\($0.label): \($0.value) (\($0.change ?? "无变化"))" }.joined(separator: "\n")
            
            let result = try await AIService.shared.generateMonthlyAnalysis(
                monthName: monthLabel,
                metricsSummary: metricsSummary,
                completedTaskNames: completedTaskNames
            )
            
            let finalResult = MonthlyAnalysisResult(month: monthKey, summary: result.summary, keywords: result.keywords)
            self.monthlyAnalysis = finalResult
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(finalResult), let json = String(data: data, encoding: .utf8) {
                await LocalValues.shared.setMonthlyAnalysis(json)
                await LocalValues.shared.setLastAnalyzedMonth(monthKey)
            }
            
        } catch {
            print("[OverviewViewModel] Generate monthly analysis error: \(error)")
        }
        isAnalyzing = false
    }

    func onCardMove(tab: String, from: Int, to: Int) {
        if tab == "OVERVIEW" {
            overviewCardOrder.move(fromOffsets: IndexSet(integer: from), toOffset: to)
            let order = overviewCardOrder.map { $0.rawValue }
            Task { await LocalValues.shared.setOverviewCardOrder(order) }
        } else {
            trendCardOrder.move(fromOffsets: IndexSet(integer: from), toOffset: to)
            let order = trendCardOrder.map { $0.rawValue }
            Task { await LocalValues.shared.setTrendCardOrder(order) }
        }
    }
    
    // MARK: - Helpers (Optimized to avoid O(N^2))

    private func computeDailyStats(items: [ParsedItem], days: Int, now: Date) -> [DailyStat] {
        let calendar = Calendar.current
        var completedMap: [Date: Int] = [:]
        var overdueMap: [Date: Int] = [:]
        
        for it in items {
            if it.item.isCompleted, let d = it.completeTime {
                let day = calendar.startOfDay(for: d)
                completedMap[day, default: 0] += 1
            }
            if !it.item.isCompleted, let end = it.endTime {
                let day = calendar.startOfDay(for: end)
                if end < now {
                    overdueMap[day, default: 0] += 1
                }
            }
        }
        
        var result: [DailyStat] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        
        for i in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -i, to: now) else { continue }
            let day = calendar.startOfDay(for: date)
            result.append(DailyStat(
                date: formatter.string(from: date),
                completedCount: completedMap[day] ?? 0,
                overdueCount: overdueMap[day] ?? 0
            ))
        }
        return result
    }
    
    private func computeLastMonthDailyStats(items: [ParsedItem], now: Date) -> [DailyStat] {
        let calendar = Calendar.current
        guard let firstDayOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let firstDayOfLastMonth = calendar.date(byAdding: .month, value: -1, to: firstDayOfThisMonth) else {
            return []
        }
        
        var completedMap: [Date: Int] = [:]
        var overdueMap: [Date: Int] = [:]
        
        for it in items {
            if it.item.isCompleted, let d = it.completeTime {
                let day = calendar.startOfDay(for: d)
                completedMap[day, default: 0] += 1
            }
            if !it.item.isCompleted, let end = it.endTime {
                let day = calendar.startOfDay(for: end)
                if end < now {
                    overdueMap[day, default: 0] += 1
                }
            }
        }
        
        let daysInMonth = calendar.dateComponents([.day], from: firstDayOfLastMonth, to: firstDayOfThisMonth).day ?? 0
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        
        var result: [DailyStat] = []
        for i in 0..<daysInMonth {
            guard let date = calendar.date(byAdding: .day, value: i, to: firstDayOfLastMonth) else { continue }
            let day = calendar.startOfDay(for: date)
            result.append(DailyStat(
                date: formatter.string(from: date),
                completedCount: completedMap[day] ?? 0,
                overdueCount: overdueMap[day] ?? 0
            ))
        }
        return result
    }
    
    private func computeMonthlyStats(items: [ParsedItem], months: Int, now: Date) -> [MonthlyStat] {
        let calendar = Calendar.current
        
        var totalMap: [Int: Int] = [:]
        var completedMap: [Int: Int] = [:]
        var overdueCompletedMap: [Int: Int] = [:]
        
        for it in items {
            if let end = it.endTime {
                let year = calendar.component(.year, from: end)
                let month = calendar.component(.month, from: end)
                let key = year * 100 + month
                totalMap[key, default: 0] += 1
                
                if it.item.isCompleted {
                    completedMap[key, default: 0] += 1
                    if let done = it.completeTime, done > end {
                        overdueCompletedMap[key, default: 0] += 1
                    }
                }
            }
        }
        
        var result: [MonthlyStat] = []
        for i in (0..<months).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let key = year * 100 + month
            
            result.append(MonthlyStat(
                month: "\(month)月",
                totalCount: totalMap[key] ?? 0,
                completedCount: completedMap[key] ?? 0,
                overdueCompletedCount: overdueCompletedMap[key] ?? 0
            ))
        }
        return result
    }
    
    private func computeWeeklyStats(items: [ParsedItem], weeks: Int, now: Date) -> [WeeklyStat] {
        let calendar = Calendar.current
        var result: [WeeklyStat] = []
        
        for i in (0..<weeks).reversed() {
            guard let endOfWeek = calendar.date(byAdding: .day, value: -i * 7, to: now),
                  let startOfWeek = calendar.date(byAdding: .day, value: -6, to: endOfWeek) else { continue }
            
            let start = calendar.startOfDay(for: startOfWeek)
            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endOfWeek) ?? endOfWeek
            
            let completed = items.filter { it in
                guard it.item.isCompleted, let d = it.completeTime else { return false }
                return d >= start && d <= end
            }.count
            
            result.append(WeeklyStat(weekLabel: i == 0 ? "本周" : "\(i)周前", completedCount: completed))
        }
        return result
    }

    private func computeContributionStats(items: [ParsedItem], days: Int, now: Date) -> [ContributionDay] {
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        
        for it in items {
            if it.item.isCompleted, let d = it.completeTime {
                let day = calendar.startOfDay(for: d)
                counts[day, default: 0] += 1
            }
        }
        
        var result: [ContributionDay] = []
        for i in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -i, to: now) else { continue }
            let day = calendar.startOfDay(for: date)
            result.append(ContributionDay(date: date, count: counts[day] ?? 0))
        }
        return result
    }

    private func computeMetrics(items: [ParsedItem], now: Date) -> [Metric] {
        let calendar = Calendar.current
        guard let firstDayOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let lastDayOfLastMonth = calendar.date(byAdding: .day, value: -1, to: firstDayOfThisMonth),
              let firstDayOfLastMonth = calendar.date(byAdding: .month, value: -1, to: firstDayOfThisMonth),
              let lastDayOfPrevPrevMonth = calendar.date(byAdding: .day, value: -1, to: firstDayOfLastMonth),
              let firstDayOfPrevPrevMonth = calendar.date(byAdding: .month, value: -1, to: lastDayOfLastMonth) else {
            return []
        }
        
        let lastMonthItems = items.filter { it in
            guard let d = it.endTime else { return false }
            return d >= firstDayOfLastMonth && d <= lastDayOfLastMonth
        }
        let prevPrevMonthItems = items.filter { it in
            guard let d = it.endTime else { return false }
            return d >= firstDayOfPrevPrevMonth && d <= lastDayOfPrevPrevMonth
        }
        
        struct MonthStats {
            let total: Int
            let completed: Int
            let rate: Double
            let overdue: Int
        }
        
        func calcStats(_ items: [ParsedItem]) -> MonthStats {
            let t = items.count
            let c = items.filter { $0.item.isCompleted }.count
            let r = t > 0 ? (Double(c) / Double(t) * 100) : 0
            let o = items.filter { !$0.item.isCompleted }.count
            return .init(total: t, completed: c, rate: r, overdue: o)
        }
        
        let current = calcStats(lastMonthItems)
        let previous = calcStats(prevPrevMonthItems)
        
        func makeMetric(label: String, val: String, curr: Double, prev: Double) -> Metric {
            if prev <= 0 { return Metric(label: label, value: val, change: nil, isDown: nil) }
            let diff = curr - prev
            let percent = (abs(diff) / prev) * 100
            let isDown = diff < 0
            return Metric(label: label, value: val, change: String(format: "%.1f%%", percent), isDown: isDown)
        }
        
        var result: [Metric] = []
        result.append(makeMetric(label: "上月任务数", val: "\(current.total)", curr: Double(current.total), prev: Double(previous.total)))
        result.append(makeMetric(label: "上月完成", val: "\(current.completed)", curr: Double(current.completed), prev: Double(previous.completed)))
        result.append(makeMetric(label: "上月完成率", val: String(format: "%.1f%%", current.rate), curr: current.rate, prev: previous.rate))
        result.append(makeMetric(label: "上月逾期数", val: "\(current.overdue)", curr: Double(current.overdue), prev: Double(previous.overdue)))
        
        let completedInLastMonth = lastMonthItems.filter { $0.item.isCompleted }
        var bucketCount: [String: Int] = [:]
        completedInLastMonth.forEach { it in
            if let d = it.completeTime {
                let hour = calendar.component(.hour, from: d)
                let b: String
                switch hour {
                case 0..<6: b = "深夜"
                case 6..<12: b = "上午"
                case 12..<18: b = "下午"
                default: b = "晚上"
                }
                bucketCount[b, default: 0] += 1
            }
        }
        if let topBucket = bucketCount.max(by: { $0.value < $1.value }) {
            result.append(Metric(label: "最活跃时段", value: topBucket.key, change: "完成 \(topBucket.value) 个", isDown: nil))
        }
        
        let durations = completedInLastMonth.compactMap { it -> TimeInterval? in
            guard let s = it.startTime,
                  let c = it.completeTime,
                  c >= s else { return nil }
            return c.timeIntervalSince(s)
        }
        
        if !durations.isEmpty {
            let avgSeconds = durations.reduce(0, +) / Double(durations.count)
            let minutes = Int(avgSeconds / 60)
            let timeValue = minutes < 60 ? "\(minutes) 分钟" : String(format: "%.1f 小时", Double(minutes) / 60.0)
            result.append(Metric(label: "平均耗时", value: timeValue, change: nil, isDown: nil))
        }
        
        return result
    }
}
