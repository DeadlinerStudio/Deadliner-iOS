import Foundation

/// Confirmation text reads V2 fields without rewriting the execution payload.
enum LifiV2Presentation {
    static func habitSummary(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let schedule = root["schedule"] as? [String: Any],
              let goal = root["goal"] as? [String: Any],
              let tracking = root["tracking"] as? [String: Any] else { return nil }
        let name = root["name"] as? String ?? "习惯"
        let count = goal["targetCount"] as? Int ?? 1
        let unit = tracking["mode"] as? String == "QUANTITY" ? (tracking["unit"] as? String ?? "单位") : "次"
        let window = goal["window"] as? String ?? "SCHEDULED_DAY"
        let period: String
        switch window {
        case "WEEK": period = "每周"
        case "MONTH": period = "每月"
        case "LIFETIME": period = "累计"
        default: period = "每个执行日"
        }
        let timing: String
        switch schedule["kind"] as? String {
        case "ONCE": timing = "一次性 · " + (schedule["startOn"] as? String ?? "")
        case "ALGORITHM": timing = "艾宾浩斯计划"
        default:
            let mask = schedule["weekdaysMask"] as? Int ?? 127
            let days = ["一", "二", "三", "四", "五", "六", "日"].enumerated()
                .filter { mask & (1 << $0.offset) != 0 }.map { "周" + $0.element }
            timing = mask == 127 ? "每天" : days.joined(separator: "、")
        }
        var lines = ["习惯：\(name)", "\(timing) · \(period) \(count) \(unit)"]
        if let reminder = root["reminder"] as? [String: Any], reminder["isEnabled"] as? Bool != false,
           let time = reminder["localTime"] as? String { lines.append("提醒：" + time) }
        return lines.joined(separator: "\n")
    }
}
