//
//  KMPHabitPresentationStore.swift
//  Deadliner
//
//  UID-first Habit UI store backed directly by the KMP aggregate.
//

#if canImport(Shared)
import Foundation
import Shared

enum KMPHabitPresentationError: LocalizedError {
    case missingHabit(String)
    case invalidStatusAction

    var errorDescription: String? {
        switch self {
        case let .missingHabit(uid):
            return "KMP habit \(uid) no longer exists."
        case .invalidStatusAction:
            return "The requested KMP habit status action could not be applied."
        }
    }
}

actor KMPHabitPresentationStore: KMPHabitUIStore {
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
    ) async throws -> HabitCreation {
        let uid = UUID().uuidString.lowercased()
        let now = Date().toLocalISOString()
        let schedule = KMPHabitMapping.schedule(
            period: period,
            startOn: dateString(Date()),
            endOn: nil,
            weekdaysMask: weekdaysMask
        )
        let goal = KMPHabitMapping.goal(
            period: period,
            timesPerPeriod: timesPerPeriod,
            goalType: goalType,
            totalTarget: totalTarget
        )
        let habit = Habit_(
            uid: uid,
            name: name,
            description: description.isEmpty ? nil : description,
            color: color.map { KotlinInt(value: Int32($0)) },
            iconKey: iconKey,
            categoryUid: categoryUID,
            schedule: schedule,
            goal: goal,
            tracking: KMPHabitMapping.tracking(targetCount: Int(goal.targetCount)),
            status: .active,
            sortOrder: Int32(sortOrder),
            reminder: alarmTime.map { HabitReminder(localTime: $0, isEnabled: true) },
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        let store = await KMPPersistenceRuntime.shared.habitStore()
        await store.create(habit)
        trace("create", uid: uid)
        return HabitCreation(habitUID: uid)
    }

    func allHabits() async throws -> [Habit] {
        let store = await KMPPersistenceRuntime.shared.habitStore()
        return await store.allHabits().map { $0.projection() }
    }

    func updateHabit(_ habit: Habit) async throws {
        let store = await KMPPersistenceRuntime.shared.habitStore()
        guard let existing = await store.habit(uid: habit.id), !existing.isDeleted else {
            throw KMPHabitPresentationError.missingHabit(habit.id)
        }
        await store.update(habit.kmpValue(existing: existing))
        trace("update", uid: habit.id)
    }

    func performHabitStatusAction(id: String, action: PersistenceHabitStatusAction) async throws -> Habit {
        let store = await KMPPersistenceRuntime.shared.habitStore()
        let result = await store.perform(
            statusAction: action.kmpValue,
            habitUID: id,
            occurredAt: Date().toLocalISOString()
        )
        guard result.outcome == .applied, let habit = result.habit else {
            throw KMPHabitPresentationError.invalidStatusAction
        }
        trace("status-action", uid: id)
        return habit.projection()
    }

    func deleteHabit(carrierID: String) async throws {
        let store = await KMPPersistenceRuntime.shared.habitStore()
        await store.delete(uid: carrierID, updatedAt: Date().toLocalISOString())
        trace("delete", uid: carrierID)
    }

    func habitRecords(habitID: String, from startDate: Date, through endDate: Date) async throws -> [HabitRecord] {
        await records(habitUID: habitID)
            .filter { $0.occurredOn >= dateString(startDate) && $0.occurredOn <= dateString(endDate) }
            .map { $0.projection() }
    }

    func habitRecords(from startDate: Date, through endDate: Date) async throws -> [HabitRecord] {
        let start = dateString(startDate)
        let end = dateString(endDate)
        let store = await KMPPersistenceRuntime.shared.habitStore()
        return await store.allRecords()
            .filter { $0.occurredOn >= start && $0.occurredOn <= end }
            .map { $0.projection() }
    }

    func toggleHabitRecord(habitID: String, date: Date) async throws {
        let store = await KMPPersistenceRuntime.shared.habitStore()
        try await store.toggleRecord(habitUID: habitID, date: date)
        trace("toggle-record", uid: habitID)
    }

    func clearHabitRecords(habitID: String, date: Date) async throws {
        let store = await KMPPersistenceRuntime.shared.habitStore()
        try await store.clearRecords(habitUID: habitID, date: date)
        trace("clear-records", uid: habitID)
    }

    private func records(habitUID: String) async -> [Shared.HabitRecord] {
        let store = await KMPPersistenceRuntime.shared.habitStore()
        return await store.records(habitUID: habitUID)
    }


    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func trace(_ operation: String, uid: String) {
        AppLog.event(
            "kmp.ui.habit.\(operation)",
            domain: .kmp,
            context: ["uid": uid]
        )
    }
}

extension Habit_ {
    func projection() -> Habit {
        Habit(
            id: uid,
            name: name,
            description: description_,
            color: color.map { Int($0.intValue) },
            iconKey: iconKey,
            categoryUID: categoryUid,
            period: KMPHabitMapping.period(schedule: schedule, goal: goal),
            weekdaysMask: Int(schedule.weekdaysMask?.intValue ?? 127),
            timesPerPeriod: Int(goal.targetCount),
            goalType: goal.window == .lifetime ? .total : .perPeriod,
            totalTarget: goal.window == .lifetime ? Int(goal.targetCount) : nil,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: status.projection,
            sortOrder: Int(sortOrder),
            alarmTime: reminder?.isEnabled == true ? reminder?.localTime : nil
        )
    }
}

extension Habit {
    func kmpValue(existing: Habit_) -> Habit_ {
        let schedule = KMPHabitMapping.schedule(
            period: period,
            startOn: existing.schedule.startOn,
            endOn: existing.schedule.endOn,
            weekdaysMask: weekdaysMask
        )
        let goal = KMPHabitMapping.goal(
            period: period,
            timesPerPeriod: timesPerPeriod,
            goalType: goalType,
            totalTarget: totalTarget
        )
        return Habit_(
            uid: id,
            name: name,
            description: description,
            color: color.map { KotlinInt(value: Int32($0)) },
            iconKey: iconKey,
            categoryUid: categoryUID,
            schedule: schedule,
            goal: goal,
            tracking: KMPHabitMapping.tracking(
                targetCount: Int(goal.targetCount),
                unit: existing.tracking.unit,
                defaultIncrement: Int(existing.tracking.defaultIncrement)
            ),
            status: status.kmpValue,
            sortOrder: Int32(sortOrder),
            reminder: alarmTime.map { HabitReminder(localTime: $0, isEnabled: true) },
            createdAt: existing.createdAt,
            updatedAt: Date().toLocalISOString(),
            isDeleted: existing.isDeleted
        )
    }
}

extension PersistenceHabitStatusAction {
    var kmpValue: HabitStatusAction { self == .archive ? .archive : .restore }
}

extension Shared.HabitRecord {
    func projection() -> HabitRecord {
        HabitRecord(
            id: uid,
            habitId: habitUid,
            date: occurredOn,
            count: Int(count),
            status: status.projection,
            createdAt: createdAt
        )
    }
}

private enum KMPHabitMapping {
    static let allDaysMask = 0b1111111
    static let ebbinghausAlgorithmKey = "EBBINGHAUS_CLASSIC_V1"

    static func schedule(
        period: HabitPeriod,
        startOn: String,
        endOn: String?,
        weekdaysMask: Int
    ) -> HabitSchedule {
        switch period {
        case .once:
            return HabitSchedule(
                kind: .once,
                startOn: startOn,
                endOn: endOn,
                weekdaysMask: nil,
                algorithmKey: nil
            )
        case .ebbinghaus:
            return HabitSchedule(
                kind: .algorithm,
                startOn: startOn,
                endOn: endOn,
                weekdaysMask: nil,
                algorithmKey: ebbinghausAlgorithmKey
            )
        case .daily, .weekly, .monthly:
            let normalizedMask = weekdaysMask & allDaysMask
            return HabitSchedule(
                kind: .weeklyDays,
                startOn: startOn,
                endOn: endOn,
                weekdaysMask: KotlinInt(value: Int32(normalizedMask == 0 ? allDaysMask : normalizedMask)),
                algorithmKey: nil
            )
        }
    }

    static func goal(
        period: HabitPeriod,
        timesPerPeriod: Int,
        goalType: HabitGoalType,
        totalTarget: Int?
    ) -> HabitGoal {
        if period == .ebbinghaus {
            return HabitGoal(window: .scheduledDay, targetCount: 1)
        }

        if goalType == .total {
            return HabitGoal(window: .lifetime, targetCount: Int32(max(1, totalTarget ?? timesPerPeriod)))
        }

        let window: Shared.HabitGoalWindow
        switch period {
        case .weekly: window = .week
        case .monthly: window = .month
        case .daily, .once, .ebbinghaus: window = .scheduledDay
        }
        return HabitGoal(window: window, targetCount: Int32(max(1, timesPerPeriod)))
    }

    static func tracking(
        targetCount: Int,
        unit: String? = nil,
        defaultIncrement: Int = 1
    ) -> HabitTracking {
        let isCheckOff = targetCount <= 1
        return HabitTracking(
            mode: isCheckOff ? .checkOff : .quantity,
            unit: unit,
            defaultIncrement: Int32(isCheckOff ? 1 : max(1, defaultIncrement))
        )
    }

    static func period(schedule: HabitSchedule, goal: HabitGoal) -> HabitPeriod {
        if schedule.kind == .once { return .once }
        if schedule.kind == .algorithm && schedule.algorithmKey == ebbinghausAlgorithmKey { return .ebbinghaus }
        if goal.window == .week { return .weekly }
        if goal.window == .month { return .monthly }
        return .daily
    }
}

extension HabitStatus {
    var kmpValue: Shared.HabitStatus { self == .archived ? .archived : .active }
}

private extension Shared.HabitStatus {
    var projection: HabitStatus { self == .archived ? .archived : .active }
}

private extension Shared.HabitRecordStatus {
    var projection: HabitRecordStatus {
        if self == .skipped { return .skipped }
        if self == .failed { return .failed }
        return .completed
    }
}

#endif
