import Foundation

func isWithin12Hours(task: DDLItem) -> Bool {
    guard let endDate = DeadlineDateParser.safeParseOptional(task.endTime) else { return false }
    return endDate.timeIntervalSinceNow < 12 * 3600
}

func remainingTimeStr(task: DDLItem) -> String {
    guard let endDate = DeadlineDateParser.safeParseOptional(task.endTime) else { return "" }
    let diff = endDate.timeIntervalSinceNow
    if diff < 0 { return "0m" }

    let hours = Int(diff / 3600)
    if hours >= 24 {
        return "\(hours / 24)d"
    } else if hours >= 1 {
        return "\(hours)h"
    } else {
        return "\(max(0, Int(diff / 60)))m"
    }
}

func calculateProgress(task: DDLItem) -> Double {
    if task.type == .habit { return task.progress }

    guard let start = DeadlineDateParser.safeParseOptional(task.startTime),
          let end = DeadlineDateParser.safeParseOptional(task.endTime) else { return 0 }

    let total = end.timeIntervalSince(start)
    guard total > 0 else { return 1.0 }
    return max(0, min(Date().timeIntervalSince(start) / total, 1.0))
}
