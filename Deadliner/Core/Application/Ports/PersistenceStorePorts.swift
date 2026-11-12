//
//  PersistenceStorePorts.swift
//  Deadliner
//
//  KMP-backed persistence contracts. Feature code must not depend on the
//  legacy SwiftData migration reader.
//

import Foundation

enum PersistenceHabitStatusAction: Sendable { case archive, restore }

struct HabitCreation: Sendable {
    let habitUID: String
}

protocol KMPTaskUIStore {
    @discardableResult
    func createTask(_ params: TaskInsertParams) async throws -> String

    func task(id: String) async throws -> DDLItem?
    func allTasks() async throws -> [DDLItem]
    func tasks(of type: DeadlineType) async throws -> [DDLItem]
    func updateTask(_ task: DDLItem) async throws
    func performTaskAction(id: String, action: DDLStateAction) async throws -> DDLItem
    func deleteTask(id: String) async throws
    func deleteSubTask(taskId: String, subTaskId: String) async throws -> DDLItem
    func postponeTask(id: String, amount: Int, inHours: Bool) async throws -> DDLItem
}

protocol KMPHabitUIStore {
    @discardableResult
    func createHabitWithCarrier(
        name: String,
        period: HabitPeriod,
        weekdaysMask: Int,
        timesPerPeriod: Int,
        goalType: HabitGoalType,
        totalTarget: Int?,
        description: String,
        color: Int?,
        iconKey: String?,
        categoryUID: String?,
        sortOrder: Int,
        alarmTime: String?
    ) async throws -> HabitCreation

    func allHabits() async throws -> [Habit]
    func updateHabit(_ habit: Habit) async throws
    func performHabitStatusAction(id: String, action: PersistenceHabitStatusAction) async throws -> Habit
    func deleteHabit(carrierID: String) async throws
    func habitRecords(habitID: String, from startDate: Date, through endDate: Date) async throws -> [HabitRecord]
    func habitRecords(from startDate: Date, through endDate: Date) async throws -> [HabitRecord]
    func toggleHabitRecord(habitID: String, date: Date) async throws
    func clearHabitRecords(habitID: String, date: Date) async throws
}

protocol CategoryPersistenceStore {
    func allCategories() async throws -> [TaskCategory]
    func category(uid: String) async throws -> TaskCategory?

    @discardableResult
    func createCategory(name: String, iconKey: String, colorHex: String) async throws -> TaskCategory

    func updateCategory(_ category: TaskCategory) async throws
    func deleteCategory(uid: String) async throws
    func restorePresets() async throws
}

protocol CapturePersistenceStore {
    func unconsumedItems() async throws -> [CaptureInboxItem]
    func createCapture(_ item: CaptureInboxItem) async throws
    func updateCapture(_ item: CaptureInboxItem) async throws
    func deleteCapture(uid: String, updatedAt: Date) async throws
    func importLegacyCaptures(_ items: [CaptureInboxItem]) async throws
}

protocol MemoryPersistenceStore {
    func fragments() async throws -> [MemoryFragment]
    func createMemory(_ fragment: MemoryFragment) async throws
    func updateMemory(_ fragment: MemoryFragment) async throws
    func deleteMemory(uid: String, updatedAt: Date) async throws
    func importLegacyMemories(_ fragments: [MemoryFragment]) async throws
}
