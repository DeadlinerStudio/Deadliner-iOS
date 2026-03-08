//
//  HomeViewModel.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import Foundation
import Combine
import os

@MainActor
final class HomeViewModel: ObservableObject {
    // MARK: - Task State
    @Published var tasks: [DDLItem] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var progressDir: Bool = false
    
    // MARK: - Habit State (v2.0)
    @Published var selectedDate: Date = Date()
    @Published var searchQuery: String = ""
    @Published var weekOverview: [DayOverview] = []
    @Published var displayHabits: [HabitWithDailyStatus] = []
    
    private var allHabitsCache: [HabitWithDailyStatus] = []

    private let repo: TaskRepository
    private let habitRepo: HabitRepository = .shared
    private var cancellables = Set<AnyCancellable>()

    private var reloadTask: Task<Void, Never>?
    private var isReloading = false
    private var pendingReload = false
    
    private var suppressReloadUntil: Date? = nil
    private var didInitialLoad = false

    private let logger = Logger(subsystem: "Deadliner", category: "HomeViewModel")

    init(repo: TaskRepository = .shared) {
        self.repo = repo

        NotificationCenter.default.publisher(for: .ddlDataChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.handleDataChangedNotification()
            }
            .store(in: &cancellables)
            
        // 监听搜索词变化
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyHabitFilter()
            }
            .store(in: &cancellables)
    }

    private func handleDataChangedNotification() {
        if let until = self.suppressReloadUntil {
            let now = Date()
            if now < until {
                let delayMs = Int(until.timeIntervalSince(now) * 1000) + 100
                self.scheduleReload(delay: UInt64(delayMs * 1_000_000))
                return
            }
        }
        self.scheduleReload()
    }

    // MARK: - Lifecycle

    func initialLoad() async {
        self.progressDir = await LocalValues.shared.getProgressDir()
        
        // 刷新 Task 和 Habit
        await reload()
        await refreshAllHabits(date: selectedDate)
        
        guard !didInitialLoad else { return }
        didInitialLoad = true

        Task {
            let syncOK = await repo.syncNow()
            logger.info("initial background sync result=\(syncOK, privacy: .public)")
        }
    }

    func pullToRefresh() async {
        isLoading = true
        await reload()
        await refreshAllHabits(date: selectedDate)
        
        let syncOK = await repo.syncNow()
        logger.info("pull-to-refresh sync result=\(syncOK, privacy: .public)")
        
        await reload()
        await refreshAllHabits(date: selectedDate)
        isLoading = false
    }

    // MARK: - Habit Logic (對標鸿蒙)

    func refreshAllHabits(date: Date) async {
        do {
            let allRaw = try await habitRepo.getAllHabits()
            let activeHabits = allRaw.filter { $0.status != .archived }
            
            var statusList: [HabitWithDailyStatus] = []
            for h in activeHabits {
                if let status = await buildStatusForDate(habit: h, date: date) {
                    statusList.append(status)
                }
            }
            
            self.allHabitsCache = statusList
            applyHabitFilter()
            
            await calculateWeekOverview(centerDate: date, allHabits: activeHabits)
        } catch {
            logger.error("refreshAllHabits failed: \(error.localizedDescription)")
        }
    }
    
    private func buildStatusForDate(habit: Habit, date: Date) async -> HabitWithDailyStatus? {
        let bounds = habitRepo.periodBounds(period: habit.period, date: date)
        let start = bounds.0
        let end = bounds.1
        
        // 如果是累计总数模式，从 1970 开始计算
        let queryStart = habit.goalType == .total ? Date(timeIntervalSince1970: 0) : start
        let queryEnd = habit.goalType == .total ? date : end
        
        do {
            let records = try await habitRepo.getRecordsForHabitInRange(habitId: habit.id, startDate: queryStart, endDateInclusive: queryEnd)
            let done = records.filter { $0.status == .completed }.reduce(0) { $0 + $1.count }
            
            var target = max(1, habit.timesPerPeriod)
            if habit.goalType == .total {
                target = habit.totalTarget.map { max(1, $0) } ?? max(1, done)
            }
            
            return HabitWithDailyStatus(
                habit: habit,
                doneCount: done,
                targetCount: target,
                isCompleted: habit.totalTarget != nil ? done >= (habit.totalTarget ?? 0) : done >= target
            )
        } catch {
            return nil
        }
    }
    
    private func applyHabitFilter() {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            displayHabits = allHabitsCache
        } else {
            let lowerQ = searchQuery.lowercased()
            displayHabits = allHabitsCache.filter { $0.habit.name.lowercased().contains(lowerQ) }
        }
    }
    
    func getEbbinghausState(habit: Habit, targetDate: Date) -> EbbinghausState {
        if habit.period != .ebbinghaus {
            return EbbinghausState(isDue: true, text: "")
        }
        
        let calendar = Calendar.current
        let tDate = calendar.startOfDay(for: targetDate)
        
        // 使用 DeadlineDateParser 解析 createdAt
        guard let createdAtDate = DeadlineDateParser.safeParseOptional(habit.createdAt) else {
            return EbbinghausState(isDue: true, text: "")
        }
        let sDate = calendar.startOfDay(for: createdAtDate)
        
        let diffDays = calendar.dateComponents([.day], from: sDate, to: tDate).day ?? 0
        let curve = [0, 1, 2, 4, 7, 15, 30, 60]
        
        if diffDays < 0 {
            return EbbinghausState(isDue: false, text: "\(-diffDays) 天后开始")
        }
        
        if curve.contains(diffDays) {
            return EbbinghausState(isDue: true, text: "")
        }
        
        if let nextDay = curve.first(where: { $0 > diffDays }) {
            return EbbinghausState(isDue: false, text: "\(nextDay - diffDays) 天后复习")
        } else {
            return EbbinghausState(isDue: false, text: "已完成记忆周期")
        }
    }
    
    private func calculateWeekOverview(centerDate: Date, allHabits: [Habit]) async {
        let calendar = Calendar.current
        let day = calendar.component(.weekday, from: centerDate)
        // 调整周一为一周起始 (Sunday=1, Monday=2...)
        let diff = (day == 1 ? -6 : (2 - day))
        guard let monday = calendar.date(byAdding: .day, value: diff, to: calendar.startOfDay(for: centerDate)) else { return }
        
        // 1. 一次性获取本周范围的所有打卡记录，极大减少 DB 往返
        guard let sunday = calendar.date(byAdding: .day, value: 6, to: monday) else { return }
        
        var weekRecords: [HabitRecord] = []
        do {
            weekRecords = try await habitRepo.getRecordsForDateRange(startDate: monday, endDate: sunday)
        } catch {
            logger.error("Failed to fetch records for week overview: \(error.localizedDescription)")
        }
        
        // 2. 预分组记录以便快速查询
        let recordsByDate = Dictionary(grouping: weekRecords, by: { $0.date })
        
        var week: [DayOverview] = []
        for i in 0..<7 {
            guard let current = calendar.date(byAdding: .day, value: i, to: monday) else { continue }
            let dateStr = current.toDateString()
            
            // 计算当日可见习惯数及完成数
            var completedCount = 0
            var visibleCount = 0
            
            for h in allHabits {
                // 艾宾浩斯：只有当 isDue 为 true 时，才计入当天的完成率统计
                if h.period == .ebbinghaus {
                    if !getEbbinghausState(habit: h, targetDate: current).isDue { continue }
                }
                
                // 其他类型（Daily, Weekly, Monthly, Once）始终计入分母
                visibleCount += 1
                let dailyRecords = recordsByDate[dateStr] ?? []
                let isDone = dailyRecords.contains { $0.habitId == h.id && $0.status == .completed }
                if isDone { completedCount += 1 }
            }
            
            week.append(DayOverview(
                date: current,
                completedCount: completedCount,
                totalCount: visibleCount,
                completionRatio: visibleCount > 0 ? Double(completedCount) / Double(visibleCount) : 0
            ))
        }
        self.weekOverview = week
    }
    
    func onDateSelected(_ date: Date) async {
        self.selectedDate = date
        await refreshAllHabits(date: date)
    }
    
    // MARK: - Habit Actions
    
    func archiveHabit(_ habit: Habit) async {
        do {
            var updated = habit
            updated.status = .archived
            try await habitRepo.updateHabit(updated)
            await refreshAllHabits(date: selectedDate)
            NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        } catch {
            logger.error("Archive habit failed: \(error.localizedDescription)")
        }
    }
    
    func deleteHabit(_ habit: Habit) async {
        do {
            try await habitRepo.deleteHabitByDdlId(ddlId: habit.ddlId)
            await refreshAllHabits(date: selectedDate)
            NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        } catch {
            logger.error("Delete habit failed: \(error.localizedDescription)")
        }
    }
    
    func getTodayCompletionRatio() -> Double {
        let calendar = Calendar.current
        if let todayOverview = weekOverview.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) }) {
            return todayOverview.completionRatio
        }
        return 0
    }
    
    func changeWeek(offset: Int) async {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .day, value: offset * 7, to: selectedDate) {
            self.selectedDate = newDate
            
            // 乐观更新日期，确保切换动画时日期立即改变
            updateWeekDatesOptimistically(centerDate: newDate)
            
            await refreshAllHabits(date: newDate)
        }
    }
    
    private func updateWeekDatesOptimistically(centerDate: Date) {
        let calendar = Calendar.current
        let day = calendar.component(.weekday, from: centerDate)
        let diff = (day == 1 ? -6 : (2 - day))
        guard let monday = calendar.date(byAdding: .day, value: diff, to: calendar.startOfDay(for: centerDate)) else { return }
        
        var week: [DayOverview] = []
        for i in 0..<7 {
            guard let current = calendar.date(byAdding: .day, value: i, to: monday) else { continue }
            // 保持原有的完成率或重置，关键是日期变了
            week.append(DayOverview(
                date: current,
                completedCount: 0,
                totalCount: 0,
                completionRatio: 0
            ))
        }
        self.weekOverview = week
    }
    
    func toggleHabitRecord(item: HabitWithDailyStatus) async -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentSel = calendar.startOfDay(for: selectedDate)
        
        if currentSel > today { return false }
        
        // 艾宾浩斯非复习日阻断打卡
        let ebState = getEbbinghausState(habit: item.habit, targetDate: selectedDate)
        if !ebState.isDue {
            self.errorText = "今天不是该记忆周期的复习日"
            return false
        }
        
        let beforeRate = Double(item.doneCount) / Double(item.targetCount)
        
        do {
            try await habitRepo.toggleRecord(habitId: item.habit.id, date: selectedDate)
            await refreshAllHabits(date: selectedDate)
            
            if let afterItem = allHabitsCache.first(where: { $0.habit.id == item.habit.id }) {
                let afterRate = Double(afterItem.doneCount) / Double(afterItem.targetCount)
                if beforeRate < 1.0 && afterRate >= 1.0 {
                    return true // 触发烟花
                }
            }
        } catch {
            logger.error("toggleHabitRecord failed: \(error.localizedDescription)")
        }
        return false
    }

    // MARK: - Task Logic (Original)

    func loadTasks() async { await initialLoad() }
    func refresh() async { await pullToRefresh() }

    func toggleCompleteLocal(_ item: DDLItem) -> Bool {
        beginSuppressReload()
        var updated = item
        updated.isCompleted.toggle()
        updated.completeTime = updated.isCompleted ? Date().toLocalISOString() : ""
        if let idx = tasks.firstIndex(where: { $0.id == item.id }) {
            tasks[idx] = updated
        }
        sortTasksInPlace()
        return updated.isCompleted
    }

    func persistToggleComplete(original: DDLItem) async {
        var updated = original
        updated.isCompleted.toggle()
        updated.completeTime = updated.isCompleted ? Date().toLocalISOString() : ""
        do {
            try await repo.updateDDL(updated)
        } catch {
            errorText = "更新失败：\(error.localizedDescription)"
            rollbackTo(original)
        }
    }
    
    func toggleArchiveItem(item: DDLItem) async {
        var updated = item
        updated.isArchived.toggle()
        do {
            try await repo.updateDDL(updated)
            await reload()
        } catch {
            errorText = "更新失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Helpers
    private func sortTasksInPlace() {
        tasks.sort { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted && rhs.isCompleted
            }
            return lhs.endTime < rhs.endTime
        }
    }

    private func rollbackTo(_ original: DDLItem) {
        if let idx = tasks.firstIndex(where: { $0.id == original.id }) {
            tasks[idx] = original
        }
        sortTasksInPlace()
    }

    func delete(_ item: DDLItem) async {
        do {
            try await repo.deleteDDL(item.id)
            await reload()
        } catch {
            errorText = "删除失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Reload Pipeline

    private func scheduleReload(delay: UInt64 = 0) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: delay)
            await self.reload()
            await self.refreshAllHabits(date: selectedDate)
        }
    }

    private func reload(force: Bool = false) async {
        if isReloading {
            pendingReload = true
            return
        }
        isReloading = true
        defer { isReloading = false }
        do {
            let sortedList = try await repo.getDDLsByType(.task)
            if !force && sortedList == self.tasks {
                // skip
            } else {
                tasks = sortedList
            }
            errorText = nil
        } catch {
            tasks = []
            errorText = "加载失败：\(error.localizedDescription)"
        }
        if pendingReload {
            pendingReload = false
            await reload()
        }
    }
    
    private func beginSuppressReload(window: TimeInterval = 0.6) {
        suppressReloadUntil = Date().addingTimeInterval(window)
    }

    func stageRebuildFromCurrentSnapshot(snapshot: [DDLItem], blankDelayMs: Int) async {
        tasks = []
        // 给 UI 一个空档，以便重新创建视图
        try? await Task.sleep(nanoseconds: UInt64(blankDelayMs * 1_000_000))
        tasks = snapshot
    }
}
