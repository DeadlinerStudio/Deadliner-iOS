import Foundation
import Shared

struct QuickAddDraft: Decodable {
    var kind = "TASK"
    var title = ""
    var dueAt: String?
    var note = ""
    var period = "DAILY"
    var targetCount = 1
    var weekdaysMask = 127
    var reminderTime: String?
    var needsAI = false
    var ready = false
    var source = "LOCAL"
    var message = ""
    var recognitionState: String?

    static func decode(_ json: String) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(json.utf8))
    }
    var habitPeriod: HabitPeriod {
        switch period {
        case "WEEKLY": return .weekly
        case "MONTHLY": return .monthly
        case "EBBINGHAUS": return .ebbinghaus
        case "ONCE": return .once
        default: return .daily
        }
    }
    var detail: String {
        if kind == "TASK" { return "截止：" + (dueAt ?? "未设置") }
        let days = ["一", "二", "三", "四", "五", "六", "日"].enumerated()
            .filter { weekdaysMask & (1 << $0.offset) != 0 }.map(\.element).joined(separator: "、")
        let window = period == "WEEKLY" ? "每周" : period == "MONTHLY" ? "每月" : period == "TOTAL" ? "累计" : "每个执行日"
        return window + " \(targetCount) 次 · 周" + days + (reminderTime.map { " · 提醒 " + $0 } ?? "")
    }
}

/// Explicit values survive model/AI refreshes; nil means the recognizer owns the field.
struct QuickAddOverrides {
    var startAt: Date?
    var dueAt: Date?
    var removesSchedule = false
    var removesDue = false
    var note: String?
    var period: String?
    var targetCount = 1
    var weekdaysMask = 127
    var reminderTime: String?
    var removesReminder = false

    func applying(to draft: QuickAddDraft) -> QuickAddDraft {
        var result = draft
        if removesSchedule {
            result.kind = "TASK"
            result.reminderTime = nil
        }
        if removesDue { result.dueAt = nil }
        else if let dueAt {
            result.dueAt = Self.timestamp(dueAt)
            // Like Android, choosing an explicit deadline confirms a task even when
            // natural-language recognition cannot produce an accepted proposal.
            if result.kind == "TASK", draft.recognitionState != "KIVO_PARTIAL",
               !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.ready = true
                // A deadline edit does not confirm uncertain title/location fields.
                result.needsAI = draft.recognitionState == "READY_WITH_AI"
                result.source = "MANUAL"
                result.recognitionState = result.needsAI ? "READY_WITH_AI" : "MANUAL"
                result.message = ""
            }
        }
        if let note { result.note = note }
        if let period {
            result.period = period
            result.targetCount = targetCount
            result.weekdaysMask = weekdaysMask
        }
        if removesReminder { result.reminderTime = nil }
        else if let reminderTime { result.reminderTime = reminderTime }
        return result
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
