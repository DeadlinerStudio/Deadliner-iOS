import SwiftData
import WidgetKit

struct DeadlinerWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeadlinerEntry {
        DeadlinerEntry(
            date: Date(),
            task: DDLItem.mock(),
            topTasks: [DDLItem.mock()],
            remainingCount: 5,
            totalActiveCount: 7,
            urgentCount: 2
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DeadlinerEntry) -> Void) {
        let entry = DeadlinerEntry(
            date: Date(),
            task: DDLItem.mock(),
            topTasks: [DDLItem.mock()],
            remainingCount: 5,
            totalActiveCount: 7,
            urgentCount: 2
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
                urgentCount: stats.urgent
            )
            let nextUpdate = Date().addingTimeInterval(15 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    @MainActor
    private func fetchWidgetData() async -> (task: DDLItem?, topTasks: [DDLItem], remaining: Int, active: Int, urgent: Int) {
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

        return (nearestTask, topTasks, remaining, active, urgent)
    }
}
