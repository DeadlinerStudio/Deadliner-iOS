import SwiftData
import WidgetKit

struct DeadlinerWidgetProvider: TimelineProvider {
    private static let contributionDays = 150

    func placeholder(in context: Context) -> DeadlinerEntry {
        DeadlinerEntry(
            date: Date(),
            task: DDLItem.mock(),
            topTasks: [DDLItem.mock()],
            remainingCount: 5,
            totalActiveCount: 7,
            urgentCount: 2,
            contributionStats: Self.mockContributionStats(days: Self.contributionDays)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DeadlinerEntry) -> Void) {
        let entry = DeadlinerEntry(
            date: Date(),
            task: DDLItem.mock(),
            topTasks: [DDLItem.mock()],
            remainingCount: 5,
            totalActiveCount: 7,
            urgentCount: 2,
            contributionStats: Self.mockContributionStats(days: Self.contributionDays)
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeadlinerEntry>) -> Void) {
        Task {
            let stats = await fetchWidgetData()
            let entry = DeadlinerEntry(
                date: Date(),
                task: stats.task,
                topTasks: stats.topTasks,
                remainingCount: stats.remaining,
                totalActiveCount: stats.active,
                urgentCount: stats.urgent,
                contributionStats: stats.contributionStats
            )
            let nextUpdate = Date().addingTimeInterval(15 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    @MainActor
    private func fetchWidgetData() async -> (task: DDLItem?, topTasks: [DDLItem], remaining: Int, active: Int, urgent: Int, contributionStats: [WidgetContributionDay]) {
        let container = SharedModelContainer.shared
        let context = ModelContext(container)

        let fd = FetchDescriptor<DDLItemEntity>()
        let allEntities = (try? context.fetch(fd)) ?? []

        let taskTypeRaw = "task"
        let validTasks = allEntities.filter { entity in
            entity.isTombstoned == false && entity.typeRaw == taskTypeRaw
        }

        let visibleTasks = validTasks.filter { entity in
            let state = entity.resolvedState()
            return !state.isArchivedLike && !state.isAbandonedLike
        }
        let activeTasks = visibleTasks
        let remainingTasks = activeTasks.filter { !$0.isCompleted }
        let sortedRemaining = remainingTasks.sorted { $0.endTime < $1.endTime }

        let topTasks = sortedRemaining.prefix(3).map { $0.toDomain() }
        let nearestTask = topTasks.first

        let remaining = remainingTasks.count
        let active = activeTasks.count

        let now = Date()
        let tomorrow = now.addingTimeInterval(24 * 3600)
        let urgent = remainingTasks.filter { item in
            guard let date = DeadlineDateParser.safeParseOptional(item.endTime) else { return false }
            return date > now && date <= tomorrow
        }.count

        var completedCountsByDay: [Date: Int] = [:]
        let calendar = Calendar.current
        for entity in validTasks where entity.isCompleted {
            guard let completedAt = DeadlineDateParser.safeParseOptional(entity.completeTime) else { continue }
            let day = calendar.startOfDay(for: completedAt)
            completedCountsByDay[day, default: 0] += 1
        }

        let contributionStats: [WidgetContributionDay] = (0..<Self.contributionDays).reversed().compactMap { offset in
            guard let dayDate = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let day = calendar.startOfDay(for: dayDate)
            return WidgetContributionDay(date: dayDate, count: completedCountsByDay[day] ?? 0)
        }

        return (nearestTask, topTasks, remaining, active, urgent, contributionStats)
    }

    private static func mockContributionStats(days: Int) -> [WidgetContributionDay] {
        let calendar = Calendar.current
        let today = Date()

        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }

            let cycle = (days - offset) % 11
            let count: Int
            switch cycle {
            case 0, 1, 2: count = 0
            case 3, 4: count = 1
            case 5, 6: count = 2
            case 7, 8: count = 4
            case 9: count = 6
            default: count = 8
            }
            return WidgetContributionDay(date: date, count: count)
        }
    }
}
