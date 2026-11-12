import Foundation

/// Older iOS quick capture stored a deadline with no start. Keep this repair in
/// the presentation adapter, using the immutable creation time instead of now.
enum TaskTimelineCompatibility {
    static func startTime(startAt: String?, dueAt: String?, createdAt: String) -> String {
        if let startAt, !startAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return startAt
        }
        guard let end = dueAt.flatMap(DeadlineDateParser.safeParseOptional),
              let created = DeadlineDateParser.safeParseOptional(createdAt) else { return "" }
        return min(created, end.addingTimeInterval(-60)).toLocalISOString()
    }
}
