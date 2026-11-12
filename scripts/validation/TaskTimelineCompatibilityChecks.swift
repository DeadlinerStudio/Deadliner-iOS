import Foundation

@main
struct TaskTimelineCompatibilityChecks {
    static func main() {
        let created = "2026-10-18T00:00:00"
        let due = "2026-10-19T00:00:00"
        let explicit = "2026-10-17T12:00:00"
        precondition(TaskTimelineCompatibility.startTime(startAt: explicit, dueAt: due, createdAt: created) == explicit)
        let repaired = TaskTimelineCompatibility.startTime(startAt: nil, dueAt: due, createdAt: created)
        precondition(repaired == created)
        let startDate = DeadlineDateParser.safeParseOptional(repaired)!
        let endDate = DeadlineDateParser.safeParseOptional(due)!
        let midpoint = startDate.addingTimeInterval(12 * 3600)
        let elapsed = midpoint.timeIntervalSince(startDate) / endDate.timeIntervalSince(startDate)
        precondition(abs(elapsed - 0.5) < 0.0001, "Repaired task must support time progress")
        precondition(TaskTimelineCompatibility.startTime(startAt: "", dueAt: nil, createdAt: created).isEmpty)
        precondition(TaskTimelineCompatibility.startTime(startAt: nil, dueAt: due, createdAt: "invalid").isEmpty)
        let past = TaskTimelineCompatibility.startTime(startAt: " ", dueAt: explicit, createdAt: created)
        precondition(DeadlineDateParser.safeParseOptional(past)! < DeadlineDateParser.safeParseOptional(explicit)!)
        print("Task timeline compatibility: explicit start, old capture, progress, undated, invalid and past deadline passed")
    }
}
