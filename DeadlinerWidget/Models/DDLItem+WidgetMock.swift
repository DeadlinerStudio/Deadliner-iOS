import Foundation

extension DDLItem {
    static func mock() -> DDLItem {
        let now = Date()
        let end = now.addingTimeInterval(3600 * 24 * 3)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return DDLItem(
            id: -1,
            name: "完成项目演示文档",
            startTime: "",
            endTime: fmt.string(from: end),
            isCompleted: false,
            completeTime: "",
            note: "",
            isArchived: false,
            isStared: true,
            type: .task,
            habitCount: 0,
            habitTotalCount: 0,
            calendarEvent: -1,
            timestamp: ""
        )
    }
}
