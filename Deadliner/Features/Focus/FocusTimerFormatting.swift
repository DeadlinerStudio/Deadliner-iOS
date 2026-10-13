#if canImport(Shared)
import Foundation
import Shared

enum FocusTimerFormatting {
    static func clock(_ seconds: Int64) -> String {
        let safe = max(0, seconds)
        return safe >= 3_600
            ? String(format: "%02lld:%02lld:%02lld", safe / 3_600, safe % 3_600 / 60, safe % 60)
            : String(format: "%02lld:%02lld", safe / 60, safe % 60)
    }
    static func duration(_ seconds: Int64) -> String {
        let safe = max(0, seconds)
        if safe > 0 && safe < 60 { return "\(safe) 秒" }
        if safe < 3_600 { return "\(safe / 60) 分钟" }
        return "\(safe / 3_600) 小时 \(safe % 3_600 / 60) 分"
    }
    static func historyDate(_ raw: String) -> String {
        guard let date = FocusAlarmPortAdapter.parseDate(raw) else { return raw }
        return date.formatted(.dateTime.month().day().hour().minute())
    }
    static func validAmount(_ input: String) -> Int? {
        guard let amount = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)),
              amount > 0, amount <= Int(Int32.max) else { return nil }
        return amount
    }
    static func outcomeMessage(_ outcome: FocusTimerOutcome?) -> String? {
        guard let outcome, outcome != .applied && outcome != .noOp else { return nil }
        switch outcome {
        case .timerAlreadyActive, .timerRequiresResolution: return "请先结束或放弃当前专注"
        case .taskRequired: return "请选择任务或习惯"
        case .taskNotFound, .habitNotFound: return "绑定的任务或习惯已被删除"
        case .taskNotActive, .habitNotActive: return "绑定目标已不再进行中，不能继续计时"
        case .habitNotDue: return "本次专注的开始日不可打卡，可选择仅结束专注"
        case .habitInvalidAmount: return "数量或习惯设置已变化，请确认实际数量后重试"
        case .invalidDuration: return "时长必须为 1 秒以上，且不能超过 24 小时或真实跨度"
        case .clockAnomaly: return "系统时间发生变化，请确认计时记录"
        case .timerNotFound: return "当前专注已结束，请查看最近记录"
        default: return "操作未完成，请刷新后重试"
        }
    }
    static func warningMessage(_ warning: FocusTimerWarning?) -> String? {
        switch warning {
        case .alarmUnavailable: return "系统提醒不可用；计时仍会保存，回到应用后核对结果。"
        case .clockAnomaly: return "系统时间发生变化，请检查计时；异常时间不会自动保存。"
        case .longRunning: return "本轮已超过 12 小时，请确认是否忘记结束计时。"
        case .excessiveDuration: return "本轮跨度过长，请核对有效时长，必要时向下更正。"
        default: return nil
        }
    }
}
#endif
