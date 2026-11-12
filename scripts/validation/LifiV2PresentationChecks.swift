import Foundation

@main struct LifiV2PresentationChecks {
    static func main() {
        let raw = #"{"name":"读书","schedule":{"kind":"WEEKLY_DAYS","weekdaysMask":127},"goal":{"window":"SCHEDULED_DAY","targetCount":20},"tracking":{"mode":"QUANTITY","unit":"分钟"},"reminder":{"localTime":"21:00","isEnabled":true}}"#
        let text = LifiV2Presentation.habitSummary(raw)!
        precondition(text.contains("每天") && text.contains("20 分钟") && text.contains("21:00"))
        precondition(!text.contains("20 次"))
        let weekdays = raw.replacingOccurrences(of: "127", with: "31")
        precondition(!LifiV2Presentation.habitSummary(weekdays)!.contains("周六"))
        precondition(LifiV2Presentation.habitSummary("{}") == nil)
        precondition(LifiV2Presentation.habitSummary("invalid") == nil)
        print("Lifi V2 presentation: 5 checks passed")
    }
}
