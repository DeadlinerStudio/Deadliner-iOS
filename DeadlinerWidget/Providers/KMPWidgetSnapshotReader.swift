//
//  KMPWidgetSnapshotReader.swift
//  DeadlinerWidget
//
//  Reads the shared SQLDelight database without loading SwiftData in the widget extension.
//

import Foundation
import Shared

struct KMPWidgetSnapshot {
    let task: DDLItem?
    let topTasks: [DDLItem]
    let remaining: Int
    let active: Int
    let habitRemaining: Int
    let habitTotal: Int
    let urgent: Int
    let nearestUrgentHours: Int?
    let contributionStats: [WidgetContributionDay]

    static let empty = KMPWidgetSnapshot(
        task: nil,
        topTasks: [],
        remaining: 0,
        active: 0,
        habitRemaining: 0,
        habitTotal: 0,
        urgent: 0,
        nearestUrgentHours: nil,
        contributionStats: []
    )
}

enum KMPWidgetSnapshotReader {
    private static let appGroupID = "group.top.aritxonly.deadliner.group"
    private static let databaseName = "deadliner_new_era.db"
    private static let contributionDays = 150

    static func load(now: Date = Date()) -> KMPWidgetSnapshot {
        guard let databasePath = databasePath(),
              FileManager.default.fileExists(atPath: databasePath)
        else { return .empty }

        let database = DeadlinerDatabase.companion.create(
            factory: IosDatabaseDriverFactory(databasePath: databasePath)
        )
        defer { database.close() }

        let tasks = database.tasks.list().filter { !$0.isDeleted }
        let visibleTasks = tasks.filter { task in
            task.state != .archived && task.state != .abandoned && task.state != .abandonedArchived
        }
        let remainingTasks = visibleTasks.filter { $0.state != .completed }
        let sortedRemaining = remainingTasks.sorted { lhs, rhs in
            deadline(for: lhs) < deadline(for: rhs)
        }
        let topTasks = sortedRemaining.prefix(3).map(taskProjection)
        let nearestUrgentTask = sortedRemaining.first(where: isNearTask)
        let tomorrow = now.addingTimeInterval(24 * 60 * 60)
        let urgent = remainingTasks.filter { task in
            guard let dueDate = task.dueAt.flatMap(parseDate) else { return false }
            return dueDate > now && dueDate <= tomorrow
        }.count

        let sourceHabits = database.habits.list()
        let habits = sourceHabits.filter { !$0.isDeleted && $0.status == .active }
        let habitOverview = HabitProgressEngine.shared.dayOverview(
            habits: habits,
            records: database.habits.allRecords(),
            on: localDate(now)
        )
        let dueHabitCount = Int(habitOverview.dueHabitCount)
        let completedHabitCount = Int(habitOverview.completedHabitCount)
        let habitSummary = (
            remaining: max(0, dueHabitCount - completedHabitCount),
            total: dueHabitCount
        )
        print(
            "[KMP][Widget] habits source=\(sourceHabits.count) visible=\(habits.count) "
                + "deleted=\(sourceHabits.filter(\.isDeleted).count) "
                + "archived=\(sourceHabits.filter { $0.status == .archived }.count) "
                + "due=\(dueHabitCount) remaining=\(habitSummary.remaining) total=\(habitSummary.total)"
        )

        let calendar = Calendar.current
        let completedByDay = tasks.reduce(into: [Date: Int]()) { counts, task in
            guard task.state == .completed,
                  let completedAt = task.completedAt.flatMap(parseDate)
            else { return }
            counts[calendar.startOfDay(for: completedAt), default: 0] += 1
        }
        let contributionStats = (0..<contributionDays).reversed().compactMap { offset -> WidgetContributionDay? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            return WidgetContributionDay(
                date: date,
                count: completedByDay[calendar.startOfDay(for: date), default: 0]
            )
        }

        return KMPWidgetSnapshot(
            task: topTasks.first,
            topTasks: topTasks,
            remaining: remainingTasks.count,
            active: visibleTasks.count,
            habitRemaining: habitSummary.remaining,
            habitTotal: habitSummary.total,
            urgent: urgent,
            nearestUrgentHours: nearestUrgentTask.flatMap { hoursUntilDeadline(for: $0, now: now) },
            contributionStats: contributionStats
        )
    }

    private static func databasePath() -> String? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(databaseName)
            .path
    }

    private static func taskProjection(_ task: Task_) -> DDLItem {
        DDLItem(
            id: task.uid,
            name: task.title,
            startTime: task.startAt ?? "",
            endTime: task.dueAt ?? "",
            state: ddlState(for: task.state),
            completeTime: task.completedAt ?? "",
            note: task.note,
            isStared: task.isStarred,
            subTasks: task.subtasks.filter { !$0.isDeleted }.map { subtask in
                InnerTodo(
                    id: subtask.uid,
                    content: subtask.content,
                    isCompleted: subtask.isCompleted,
                    sortOrder: Int(subtask.sortOrder),
                    createdAt: subtask.createdAt,
                    updatedAt: subtask.updatedAt
                )
            },
            type: .task,
            habitCount: 0,
            habitTotalCount: 0,
            calendarEvent: task.calendarEventId?.int64Value ?? 0,
            timestamp: task.updatedAt,
            categoryUID: task.categoryUid
        )
    }

    private static func ddlState(for state: TaskState) -> DDLState {
        switch state {
        case .completed: .completed
        case .archived: .archived
        case .abandoned: .abandoned
        case .abandonedArchived: .abandonedArchived
        default: .active
        }
    }

    private static func deadline(for task: Task_) -> Date {
        task.dueAt.flatMap(parseDate) ?? .distantFuture
    }

    private static func isNearTask(_ task: Task_) -> Bool {
        guard let dueDate = task.dueAt.flatMap(parseDate) else { return false }
        return dueDate.timeIntervalSinceNow > 0 && dueDate.timeIntervalSinceNow <= 24 * 60 * 60
    }

    private static func hoursUntilDeadline(for task: Task_, now: Date) -> Int? {
        guard let dueDate = task.dueAt.flatMap(parseDate) else { return nil }
        return max(0, Int(ceil(dueDate.timeIntervalSince(now) / 3600)))
    }

    private static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
            ?? ISO8601DateFormatter().date(from: value + "Z")
    }

    private static func localDate(_ date: Date) -> Kotlinx_datetimeLocalDate {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return Kotlinx_datetimeLocalDate(
            year: Int32(components.year ?? 1970),
            month: Int32(components.month ?? 1),
            day: Int32(components.day ?? 1)
        )
    }

}
