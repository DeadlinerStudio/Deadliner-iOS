import WidgetKit

struct DeadlinerEntry: TimelineEntry {
    let date: Date
    let task: DDLItem?
    let topTasks: [DDLItem]
    let remainingCount: Int
    let totalActiveCount: Int
    let urgentCount: Int
}
