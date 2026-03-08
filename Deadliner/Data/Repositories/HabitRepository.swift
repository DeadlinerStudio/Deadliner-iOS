//
//  HabitRepository.swift
//  Deadliner
//
//  Created by Gemini CLI on 2026/3/7.
//

import Foundation
import os

class HabitRepository {
    static let shared = HabitRepository()
    private let db = DatabaseHelper.shared
    private let logger = Logger(subsystem: "Deadliner", category: "HabitRepository")
    
    private var reminderUpdateTimer: Timer?
    
    private init() {}
    
    // MARK: - Helper: Date Formatting
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    
    private func nowISO() -> String {
        // 使用项目通用的 ISO 格式
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
    
    // MARK: - Habit 本体
    
    @discardableResult
    func createHabitForDdl(
        ddlId: Int64,
        name: String,
        period: HabitPeriod,
        timesPerPeriod: Int = 1,
        goalType: HabitGoalType = .perPeriod,
        totalTarget: Int? = nil,
        description: String = "",
        color: Int? = nil,
        iconKey: String? = nil,
        sortOrder: Int = 0,
        alarmTime: String? = nil
    ) async throws -> Int64 {
        let now = nowISO()
        let habit = Habit(
            id: -1,
            ddlId: ddlId,
            name: name,
            description: description,
            color: color,
            iconKey: iconKey,
            period: period,
            timesPerPeriod: timesPerPeriod,
            goalType: goalType,
            totalTarget: totalTarget,
            createdAt: now,
            updatedAt: now,
            status: .active,
            sortOrder: sortOrder,
            alarmTime: alarmTime
        )
        let id = try await db.insertHabit(ddlLegacyId: ddlId, habit: habit)
        scheduleReminderRefresh()
        return id
    }
    
    func getHabitByDDLId(ddlLegacyId: Int64) async throws -> Habit? {
        return try await db.getHabitByDDLId(ddlLegacyId: ddlLegacyId)
    }
    
    func getHabitById(id: Int64) async throws -> Habit? {
        return try await db.getHabitById(id: id)
    }
    
    func getAllHabits() async throws -> [Habit] {
        return try await db.getAllHabits()
    }
    
    func updateHabit(_ habit: Habit) async throws {
        var updated = habit
        updated.updatedAt = nowISO()
        try await db.updateHabit(updated)
        scheduleReminderRefresh()
    }
    
    func deleteHabitByDdlId(ddlId: Int64) async throws {
        try await db.deleteHabitByDDLId(ddlLegacyId: ddlId)
        scheduleReminderRefresh()
    }
    
    // MARK: - Habit 打卡记录
    
    func getRecordsForHabitOnDate(habitId: Int64, date: Date) async throws -> [HabitRecord] {
        return try await db.getHabitRecordsForHabitOnDate(habitLegacyId: habitId, date: formatDate(date))
    }
    
    func getRecordsForDate(date: Date) async throws -> [HabitRecord] {
        return try await db.getHabitRecordsForDate(date: formatDate(date))
    }
    
    func getRecordsForHabitInRange(
        habitId: Int64,
        startDate: Date,
        endDateInclusive: Date
    ) async throws -> [HabitRecord] {
        return try await db.getHabitRecordsForHabitInRange(
            habitLegacyId: habitId,
            startDate: formatDate(startDate),
            endDate: formatDate(endDateInclusive)
        )
    }
    
    func getRecordsForDateRange(
        startDate: Date,
        endDate: Date
    ) async throws -> [HabitRecord] {
        // 由于 DatabaseHelper 目前没有通用的 getHabitRecordsInRange，我们暂时复用 existing logic or add it
        // 为了高性能，我们去 DatabaseHelper 增加一个
        return try await db.getHabitRecordsInRange(
            startDate: formatDate(startDate),
            endDate: formatDate(endDate)
        )
    }
    
    @discardableResult
    func insertRecord(
        habitId: Int64,
        date: Date,
        count: Int = 1,
        status: HabitRecordStatus = .completed
    ) async throws -> Int64 {
        let record = HabitRecord(
            id: -1,
            habitId: habitId,
            date: formatDate(date),
            count: count,
            status: status,
            createdAt: nowISO()
        )
        return try await db.insertHabitRecord(habitLegacyId: habitId, record: record)
    }
    
    func deleteRecordsForHabitOnDate(habitId: Int64, date: Date) async throws {
        try await db.deleteHabitRecordsForHabitOnDate(habitLegacyId: habitId, date: formatDate(date))
    }
    
    func getCompletedIdsForDate(date: Date) async throws -> Set<Int64> {
        let records = try await getRecordsForDate(date: date)
        let completed = records.filter { $0.status == .completed }.map { $0.habitId }
        return Set(completed)
    }
    
    // MARK: - Logic: Period Calculation
    
    func periodBounds(period: HabitPeriod, date: Date) -> (Date, Date) {
        let calendar = Calendar.current
        let d = calendar.startOfDay(for: date)
        
        switch period {
        case .daily:
            return (d, d)
        case .weekly:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
            guard let monday = calendar.date(from: components) else { return (d, d) }
            let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? d
            return (monday, sunday)
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: d)
            guard let firstDay = calendar.date(from: components) else { return (d, d) }
            let lastDay = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: firstDay) ?? d
            return (firstDay, lastDay)
        default:
            return (d, d)
        }
    }
    
    // MARK: - Logic: Toggle
    
    /**
     * 切换某天某个习惯的完成状态
     * 适配 ONCE (单次) 和 EBBINGHAUS (艾宾浩斯)
     */
    func toggleRecord(habitId: Int64, date: Date) async throws {
        guard let habit = try await db.getHabitById(id: habitId) else { return }
        let dateStr = formatDate(date)
        
        let recordsToday = (try await db.getHabitRecordsForHabitOnDate(habitLegacyId: habitId, date: dateStr))
            .filter { $0.status == .completed }
        let todayCount = recordsToday.reduce(0) { $0 + $1.count }
        
        if habit.period == .daily || habit.period == .once || habit.period == .ebbinghaus {
            // === 简单模式 (0/1) ===
            if todayCount > 0 {
                try await db.deleteHabitRecordsForHabitOnDate(habitLegacyId: habitId, date: dateStr)
            } else {
                try await insertRecord(habitId: habitId, date: date, count: 1, status: .completed)
            }
        } else {
            // === 累积模式 (Weekly/Monthly) ===
            let target = max(1, habit.timesPerPeriod)
            let (start, end) = periodBounds(period: habit.period, date: date)
            
            let recordsInPeriod = (try await db.getHabitRecordsForHabitInRange(
                habitLegacyId: habitId,
                startDate: formatDate(start),
                endDate: formatDate(end)
            )).filter { $0.status == .completed }
            
            let totalInPeriod = recordsInPeriod.reduce(0) { $0 + $1.count }
            
            if todayCount > 0 {
                try await db.deleteHabitRecordsForHabitOnDate(habitLegacyId: habitId, date: dateStr)
            } else {
                if totalInPeriod >= target && habit.goalType == .perPeriod {
                    logger.info("Habit goal reached for period. No-op.")
                } else {
                    try await insertRecord(habitId: habitId, date: date, count: 1, status: .completed)
                }
            }
        }
        
        // 触发提醒更新
        scheduleReminderRefresh()
    }
    
    // MARK: - Reminders
    
    func scheduleReminderRefresh() {
        DispatchQueue.main.async {
            self.reminderUpdateTimer?.invalidate()
            self.reminderUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                Task {
                    await self.performReminderRefresh()
                }
            }
        }
    }
    
    private func performReminderRefresh() async {
        do {
            logger.info("Triggering Habit Reminder Scheduler (placeholder)...")
            // TODO: ReminderScheduler.refreshHabits(try await getAllHabits())
        } catch {
            logger.error("Habit reminder refresh failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Port Implementations

extension HabitRepository: HabitReadPort {
    func getHabitsByStatus(status: HabitStatus) async throws -> [Habit] {
        let all = try await getAllHabits()
        return all.filter { $0.status == status }
    }
    
    func getRecordsByHabitId(habitLegacyId: Int64) async throws -> [HabitRecord] {
        return try await getRecordsForHabitInRange(
            habitId: habitLegacyId,
            startDate: Date(timeIntervalSince1970: 0),
            endDateInclusive: Date().addingTimeInterval(3600 * 24 * 365 * 10)
        )
    }
    
    func getRecordsByDate(date: String) async throws -> [HabitRecord] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: date) else { return [] }
        return try await getRecordsForDate(date: d)
    }
}

extension HabitRepository: HabitWritePort {
    func insertHabit(ddlLegacyId: Int64, habit: Habit) async throws -> Int64 {
        return try await createHabitForDdl(
            ddlId: ddlLegacyId,
            name: habit.name,
            period: habit.period,
            timesPerPeriod: habit.timesPerPeriod,
            goalType: habit.goalType,
            totalTarget: habit.totalTarget,
            description: habit.description ?? "",
            color: habit.color,
            iconKey: habit.iconKey,
            sortOrder: habit.sortOrder,
            alarmTime: habit.alarmTime
        )
    }
    
    func deleteHabit(legacyId: Int64) async throws {
        try await db.deleteHabit(legacyId: legacyId)
        scheduleReminderRefresh()
    }
    
    func recordHabit(habitLegacyId: Int64, date: String, count: Int, status: HabitRecordStatus) async throws -> Int64 {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: date) else { return -1 }
        return try await insertRecord(habitId: habitLegacyId, date: d, count: count, status: status)
    }
    
    func deleteRecord(recordLegacyId: Int64) async throws {
        try await db.deleteHabitRecord(legacyId: recordLegacyId)
    }
}
