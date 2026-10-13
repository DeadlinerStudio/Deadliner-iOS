import Foundation

/// Gregorian local dates match the shared ISO month contract, regardless of the user's calendar preference.
nonisolated enum OverviewPeriod {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }
    static func monthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }
    static func shifted(_ month: Date, by offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: monthStart(month))!
    }
    static func key(_ date: Date, format: String = "yyyy-MM-dd", timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
    static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }
    static func comparisonDay(month: Date, now: Date) -> Int {
        monthStart(month) == monthStart(now) ? calendar.component(.day, from: now) : calendar.range(of: .day, in: .month, for: month)!.count
    }
    static func comparison(current: [Int], previous: [Int], day: Int) -> (text: String, direction: Int) {
        let currentCount = current.prefix(day).reduce(0, +)
        let previousCount = previous.prefix(day).reduce(0, +)
        let delta = currentCount - previousCount
        if delta == 0 { return ("较上月同期持平", 0) }
        if previousCount == 0 { return ("较上月同期新增 \(delta) 项", 1) }
        return (String(format: "较上月同期 %@ %.1f%%", delta > 0 ? "增长" : "减少", abs(Double(delta) / Double(previousCount)) * 100), delta > 0 ? 1 : -1)
    }
}
