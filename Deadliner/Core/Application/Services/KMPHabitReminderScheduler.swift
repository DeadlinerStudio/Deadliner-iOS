//
//  KMPHabitReminderScheduler.swift
//  Deadliner
//
//  Schedules Apple notifications from KMP Habit and HabitRecord aggregates.
//

#if canImport(Shared)
import Foundation
import Shared

actor KMPHabitReminderScheduler {
    static let shared = KMPHabitReminderScheduler()
    private let horizonDays: Int32 = 64
    private let maxPendingHabitInstances = 48

    private var pendingRefresh: _Concurrency.Task<Void, Never>?

    func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
            guard !_Concurrency.Task.isCancelled else { return }
            await refresh()
        }
    }

    func refresh() async {
        await NotificationManager.shared.cancelAllKMPHabitNotifications()
        let store = await KMPPersistenceRuntime.shared.habitStore()
        let now = Date()
        let recordsByHabit = Dictionary(grouping: await store.allRecords(), by: \.habitUid)
        var planned: [(habitUID: String, name: String, fireAt: Date)] = []

        for habit in await store.allHabits() where habit.status == .active {
            let localTimes = HabitReminderPlanner.shared.plan(
                habit: habit,
                records: recordsByHabit[habit.uid, default: []],
                from: localDate(now),
                horizonDays: horizonDays
            )
            for localTime in localTimes {
                guard let fireAt = parseLocalFireAt(localTime), fireAt > now else { continue }
                planned.append((habit.uid, habit.name, fireAt))
            }
        }

        for instance in planned.sorted(by: { $0.fireAt < $1.fireAt }).prefix(maxPendingHabitInstances) {
            NotificationManager.shared.scheduleKMPHabitInstance(
                uid: instance.habitUID,
                name: instance.name,
                date: instance.fireAt
            )
        }
    }

    private func parseLocalFireAt(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: value)
    }

    private func localDate(_ date: Date) -> Kotlinx_datetimeLocalDate {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return Kotlinx_datetimeLocalDate(
            year: Int32(components.year ?? 1970),
            month: Int32(components.month ?? 1),
            day: Int32(components.day ?? 1)
        )
    }
}
#endif
