//
//  KMPHabitStore.swift
//  Deadliner
//
//  UID-first Habit and record access backed by DeadlinerCore.
//

#if canImport(Shared)
import Foundation
import Shared

actor KMPHabitStore: KMPHabitPersistenceStore {
    private let database: DeadlinerDatabase

    init(database: DeadlinerDatabase) {
        self.database = database
    }

    func allHabits() -> [Habit_] {
        database.habits.list().filter { !$0.isDeleted }
    }

    func habit(uid: String) -> Habit_? {
        database.habits.find(uid: uid)
    }

    func records(habitUID: String) -> [Shared.HabitRecord] {
        database.habits.records(habitUid: habitUID).filter { !$0.isDeleted }
    }

    func allRecords() -> [Shared.HabitRecord] {
        database.habits.allRecords().filter { !$0.isDeleted }
    }

    func create(_ habit: Habit_) async {
        database.habits.create(habit: habit)
        trace("create", uid: habit.uid)
        await publishChange(resources: [.habit])
        await KMPHabitReminderScheduler.shared.scheduleRefresh()
    }

    func update(_ habit: Habit_) async {
        database.habits.update(habit: habit)
        trace("update", uid: habit.uid)
        await publishChange(resources: [.habit])
        await KMPHabitReminderScheduler.shared.scheduleRefresh()
    }

    func perform(statusAction: HabitStatusAction, habitUID: String, occurredAt: String) async -> HabitActionResult {
        let result = database.habits.applyStatusAction(uid: habitUID, action: statusAction, occurredAt: occurredAt)
        if result.outcome == .applied {
            trace("status-action", uid: habitUID, extra: ["action": "\(statusAction)"])
            await publishChange(resources: [.habit])
            await KMPHabitReminderScheduler.shared.scheduleRefresh()
        }
        return result
    }

    func delete(uid: String, updatedAt: String) async {
        database.habits.delete(uid: uid, updatedAt: updatedAt)
        trace("delete", uid: uid)
        await publishChange(resources: [.habit, .habitRecord])
        await KMPHabitReminderScheduler.shared.scheduleRefresh()
    }

    func save(record: Shared.HabitRecord) async {
        database.habits.saveRecord(record: record, operation: .update)
        await publishChange(resources: [.habitRecord])
        await KMPHabitReminderScheduler.shared.scheduleRefresh()
    }

    func toggleRecord(habitUID: String, date: Date) async throws {
        let result = database.habits.toggleRecord(habitUid: habitUID, occurredOn: dateString(date), occurredAt: Date().toLocalISOString())
        guard result.outcome != .notFound else { throw KMPHabitStoreError.missingHabit(habitUID) }
        trace("toggle-record", uid: habitUID)
        await publishChange(resources: [.habitRecord])
        await KMPHabitReminderScheduler.shared.scheduleRefresh()
    }

    func applyPrimaryRecordAction(habitUID: String, date: Date) async throws {
        let occurredOn = dateString(date)
        let occurredAt = Date().toLocalISOString()
        let result = database.habits.applyPrimaryRecordAction(
            habitUid: habitUID,
            occurredOn: occurredOn,
            occurredAt: occurredAt
        )
        guard result.outcome != .notFound else { throw KMPHabitStoreError.missingHabit(habitUID) }
        guard result.outcome == .applied else { return }
        trace("primary-record-action", uid: habitUID)
        await publishChange(resources: [.habitRecord])
        await KMPHabitReminderScheduler.shared.scheduleRefresh()
    }

    func clearRecords(habitUID: String, date: Date) async throws {
        let result = database.habits.clearRecords(habitUid: habitUID, occurredOn: dateString(date), occurredAt: Date().toLocalISOString())
        guard result.outcome != .notFound else { throw KMPHabitStoreError.missingHabit(habitUID) }
        trace("clear-records", uid: habitUID)
        await publishChange(resources: [.habitRecord])
        await KMPHabitReminderScheduler.shared.scheduleRefresh()
    }

    private func publishChange(resources: Set<PersistenceResourceKind>) async {
        await MainActor.run {
            PersistenceChangePublisher.publish(.init(resourceKinds: resources))
        }
    }

    private func trace(_ operation: String, uid: String, extra: [String: String] = [:]) {
        var context = extra
        context["uid"] = uid
        AppLog.event("persistence.habit.\(operation)", domain: .persistence, context: context)
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private enum KMPHabitStoreError: LocalizedError {
    case missingHabit(String)

    var errorDescription: String? {
        switch self {
        case let .missingHabit(uid):
            "KMP habit \(uid) no longer exists."
        }
    }
}
#endif
