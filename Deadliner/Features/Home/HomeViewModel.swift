//
//  HomeViewModel.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import Foundation
import Combine
import os
import SwiftUI
#if canImport(Shared)
import Shared
#endif

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
    @Published var categories: [TaskCategory] = []
    
    private var allHabitsCache: [HabitWithDailyStatus] = []

    private let repo: any KMPTaskUIStore
    private let habitRepo: any KMPHabitUIStore = PersistenceStores.habits
    private let categoryRepo: any CategoryPersistenceStore = PersistenceStores.categories
    private var cancellables = Set<AnyCancellable>()

    private var reloadTask: _Concurrency.Task<Void, Never>?
    private var isReloading = false
    private var pendingReload = false
    private var kmpTaskListBridge: KMPTaskListViewModelBridge?
    private var kmpHabitListBridge: KMPHabitListViewModelBridge?
    
    private var suppressReloadUntil: Date? = nil
    private var didInitialLoad = false

    private let logger = Logger(subsystem: "Deadliner", category: "HomeViewModel")

    init(repo: any KMPTaskUIStore = PersistenceStores.tasks) {
        self.repo = repo

        NotificationCenter.default.publisher(for: .persistenceDataChanged)
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

    private func logInfo(_ message: String) {
        logger.info("\(message, privacy: .public)")
        AppLog.log(message, category: "home")
    }

    private func logError(_ message: String) {
        logger.error("\(message, privacy: .public)")
        AppLog.log(message, level: .error, category: "home")
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
        await startKMPTaskListBridgeIfNeeded()
        await startKMPHabitListBridgeIfNeeded()
        
        // 刷新 Task 和 Habit
        await reload()
        await refreshCategories()
        await refreshAllHabits(date: selectedDate)
        
        guard !didInitialLoad else { return }
        didInitialLoad = true

        _Concurrency.Task {
            let syncOK = await SyncCoordinator.shared.syncNow()
            logInfo("initial background sync result=\(syncOK)")
        }
    }

    func pullToRefresh() async {
        isLoading = true
        await reload()
        await refreshCategories()
        await refreshAllHabits(date: selectedDate)
        
        let syncOK = await SyncCoordinator.shared.syncNow()
        logInfo("pull-to-refresh sync result=\(syncOK)")
        
        await reload()
        await refreshCategories()
        await refreshAllHabits(date: selectedDate)
        isLoading = false
    }

    func refreshCategories() async {
        do {
            categories = try await categoryRepo.allCategories()
        } catch {
            logError("refreshCategories failed: \(error.localizedDescription)")
            // Preserve the previous category cache on transient store errors.
        }
    }

    // MARK: - Habit Logic (對標鸿蒙)

    func refreshAllHabits(date: Date) async {
        if kmpHabitListBridge == nil {
            await startKMPHabitListBridgeIfNeeded()
        }
        kmpHabitListBridge?.selectDate(date.toDateString())
    }
    
    private func applyHabitFilter() {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            displayHabits = allHabitsCache
        } else {
            let lowerQ = searchQuery.lowercased()
            displayHabits = allHabitsCache.filter { $0.habit.name.lowercased().contains(lowerQ) }
        }
    }
    
    func onDateSelected(_ date: Date) async {
        self.selectedDate = date
        await refreshAllHabits(date: date)
    }
    
    // MARK: - Habit Actions
    
    func archiveHabit(_ habit: Habit) async {
        do {
            _ = try await habitRepo.performHabitStatusAction(id: habit.id, action: .archive)
            await refreshAllHabits(date: selectedDate)
        } catch {
            logError("Archive habit failed: \(error.localizedDescription)")
        }
    }
    
    func archiveHabits(_ habits: [Habit]) async {
        guard !habits.isEmpty else { return }
        do {
            for habit in habits {
                _ = try await habitRepo.performHabitStatusAction(id: habit.id, action: .archive)
            }
            await refreshAllHabits(date: selectedDate)
        } catch {
            logError("Archive habits failed: \(error.localizedDescription)")
        }
    }
    
    func deleteHabit(_ habit: Habit) async {
        do {
            try await habitRepo.deleteHabit(carrierID: habit.id)
            await refreshAllHabits(date: selectedDate)
        } catch {
            logError("Delete habit failed: \(error.localizedDescription)")
        }
    }
    
    func deleteHabits(_ habits: [Habit]) async {
        guard !habits.isEmpty else { return }
        do {
            for habit in habits {
                try await habitRepo.deleteHabit(carrierID: habit.id)
            }
            await refreshAllHabits(date: selectedDate)
        } catch {
            logError("Delete habits failed: \(error.localizedDescription)")
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
        guard item.canApplyPrimaryAction else {
            errorText = "当前日期不可记录该习惯"
            return false
        }

        let completesHabit = !item.isCompleted
            && item.doneCount + max(1, item.primaryActionAmount) >= item.targetCount

        if let kmpHabitListBridge {
            kmpHabitListBridge.applyPrimaryAction(habitUID: item.habit.id)
            return completesHabit
        }
        
        do {
            try await habitRepo.toggleHabitRecord(habitID: item.habit.id, date: selectedDate)
            await refreshAllHabits(date: selectedDate)
            return completesHabit
        } catch {
            logError("toggleHabitRecord failed: \(error.localizedDescription)")
        }
        return false
    }

    // MARK: - Task Logic (Original)

    func loadTasks() async { await initialLoad() }
    func refresh() async { await pullToRefresh() }

    func toggleComplete(_ item: DDLItem) async -> Bool {
        do {
            let action: DDLStateAction = item.isCompleted ? .restoreActive : .markComplete
            let updated = try await performTaskAction(item: item, action: action)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if let idx = tasks.firstIndex(where: { $0.id == item.id }) {
                    tasks[idx] = updated
                }
                sortTasksInPlace()
            }
            return updated.isCompleted
        } catch {
            errorText = "状态流转失败：\(error.localizedDescription)"
            return item.isCompleted
        }
    }
    
    func toggleArchiveItem(item: DDLItem) async {
        do {
            _ = try await performTaskAction(
                item: item,
                action: item.isArchived ? .unarchive : .markArchive
            )
            await reload()
        } catch {
            errorText = "状态流转失败：\(error.localizedDescription)"
        }
    }
    
    func archiveTasks(_ items: [DDLItem]) async {
        guard !items.isEmpty else { return }
        do {
            for item in items {
                _ = try await performTaskAction(item: item, action: .markArchive)
            }
            await reload()
        } catch {
            errorText = "批量归档失败：\(error.localizedDescription)"
        }
    }

    func toggleGiveUpItem(item: DDLItem) async {
        do {
            AppLog.event("task.give-up.started", domain: .kmp, context: ["uid": item.id])
            let updated = try await performTaskAction(
                item: item,
                action: item.state.isAbandonedLike ? .restoreActive : .markGiveUp
            )
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
                sortTasksInPlace()
            }
            AppLog.event(
                "task.give-up.applied",
                domain: .kmp,
                context: ["uid": updated.id, "state": updated.state.rawValue]
            )
            await reload()
        } catch {
            AppLog.failure("task.give-up.failed", domain: .kmp, error: error, context: ["uid": item.id])
            errorText = "状态流转失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Helpers
    private func sortTasksInPlace() {
        tasks = sortedTasks(tasks)
    }

    private func sortedTasks(_ items: [DDLItem]) -> [DDLItem] {
        items.sorted { lhs, rhs in
            if lhs.state.isActionable != rhs.state.isActionable {
                return lhs.state.isActionable && !rhs.state.isActionable
            }
            if lhs.isStared != rhs.isStared {
                return lhs.isStared && !rhs.isStared
            }

            let leftEnd = DeadlineDateParser.safeParseOptional(lhs.endTime) ?? .distantFuture
            let rightEnd = DeadlineDateParser.safeParseOptional(rhs.endTime) ?? .distantFuture
            if leftEnd != rightEnd {
                return leftEnd < rightEnd
            }

            return lhs.id < rhs.id
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
            try await deleteTask(item: item)
            await reload()
        } catch {
            errorText = "删除失败：\(error.localizedDescription)"
        }
    }
    
    func deleteTasks(_ items: [DDLItem]) async {
        guard !items.isEmpty else { return }
        do {
            for item in items {
                try await deleteTask(item: item)
            }
            await reload()
        } catch {
            errorText = "批量删除失败：\(error.localizedDescription)"
        }
    }

    private func performTaskAction(item: DDLItem, action: DDLStateAction) async throws -> DDLItem {
        let updated = try await repo.performTaskAction(id: item.id, action: action)
        kmpTaskListBridge?.refresh()
        return updated
    }

    private func deleteTask(item: DDLItem) async throws {
        try await repo.deleteTask(id: item.id)
        kmpTaskListBridge?.refresh()
    }

    // MARK: - Reload Pipeline

    private func scheduleReload(delay: UInt64 = 0) {
        reloadTask?.cancel()
        reloadTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            try? await _Concurrency.Task.sleep(nanoseconds: delay)
            await self.reload()
            await self.refreshCategories()
            await self.refreshAllHabits(date: selectedDate)
        }
    }

    private func reload(force: Bool = false) async {
        if let kmpTaskListBridge {
            kmpTaskListBridge.refresh()
            return
        }

        if isReloading {
            pendingReload = true
            return
        }
        isReloading = true
        defer { isReloading = false }
        do {
            let fetchedList = try await repo.tasks(of: .task)
            let sortedList = sortedTasks(fetchedList)
            let mainListVisible = sortedList.filter(\.state.isMainListVisible)
            SyncDebugLog.log(
                "[KMP][Home] tasks source=\(sortedList.count) mainListVisible=\(mainListVisible.count)"
            )
            if !force && sortedList == self.tasks {
                // skip
            } else {
                tasks = sortedList
            }
            errorText = nil
        } catch {
            tasks = []
            logError("reload failed: \(error.localizedDescription)")
            errorText = "加载失败：\(error.localizedDescription)"
        }
        if pendingReload {
            pendingReload = false
            await reload()
        }
    }

    private func startKMPTaskListBridgeIfNeeded() async {
        guard kmpTaskListBridge == nil else {
            return
        }

        let bridge = await KMPTaskListViewModelBridge.make()
        kmpTaskListBridge = bridge
        bridge.start { [weak self] state in
            self?.consumeKMPTaskListState(state)
        }
    }

    private func consumeKMPTaskListState(_ state: TaskListUiState) {
        isLoading = state.isLoading
        guard !state.isLoading else { return }

        let projected = state.tasks
            .filter { !$0.isDeleted }
            .map { $0.ddlProjection() }
        let sortedList = sortedTasks(projected)
        let mainListVisible = sortedList.filter(\.state.isMainListVisible)
        SyncDebugLog.log(
            "[KMP][Home][TaskListViewModel] tasks=\(sortedList.count) "
                + "mainListVisible=\(mainListVisible.count)"
        )
        tasks = sortedList
        errorText = state.error
    }

    private func startKMPHabitListBridgeIfNeeded() async {
        guard kmpHabitListBridge == nil else {
            return
        }

        let bridge = await KMPHabitListViewModelBridge.make()
        kmpHabitListBridge = bridge
        bridge.start { [weak self] state in
            _Concurrency.Task { @MainActor [weak self] in
                await self?.consumeKMPHabitListState(state)
            }
        }
    }

    private func consumeKMPHabitListState(_ state: HabitListUiState) async {
        guard !state.isLoading else { return }

        allHabitsCache = state.visibleHabits
            .filter { !$0.habit.isDeleted }
            .map(HabitSharedPresentationMapper.projection)
        applyHabitFilter()
        weekOverview = state.weekOverview.compactMap { item in
            guard let date = habitStateDate(item.date) else { return nil }
            return DayOverview(
                date: date,
                completedCount: Int(item.completedCount),
                totalCount: Int(item.totalCount),
                completionRatio: Double(item.completionRatio)
            )
        }
        if let stateDate = habitStateDate(state.selectedDate) {
            selectedDate = stateDate
        }
        if let error = state.error {
            errorText = error
        }
    }

    private func habitStateDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
    
    private func beginSuppressReload(window: TimeInterval = 0.6) {
        suppressReloadUntil = Date().addingTimeInterval(window)
    }

    func stageRebuildFromCurrentSnapshot(snapshot: [DDLItem], blankDelayMs: Int) async {
        tasks = []
        // 给 UI 一个空档，以便重新创建视图
        try? await _Concurrency.Task.sleep(nanoseconds: UInt64(blankDelayMs * 1_000_000))
        tasks = snapshot
    }
}
