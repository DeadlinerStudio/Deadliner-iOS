//
//  SearchSupport.swift
//  Deadliner
//
//  Created by Codex on 2026/4/2.
//

import SwiftUI

enum SearchViewSupport {
    static func searchResults(in tasks: [DDLItem], query: String, archived: Bool = false) -> [SearchTaskResult] {
        let tokens = queryTokens(from: query)

        return tasks.compactMap { item in
            let title = item.name
            let subtitle = taskSubtitle(for: item, archived: archived)
            let detail = [item.note, item.endTime, item.startTime, item.completeTime]
                .joined(separator: "\n")
            let score = searchScore(title: title, subtitle: subtitle, detail: detail, tokens: tokens)
            guard score > 0 else { return nil }
            return SearchTaskResult(task: item, sortScore: score)
        }
        .sorted(by: searchSortComparator)
    }

    static func searchResults(in habits: [Habit], query: String, archived: Bool = false) -> [SearchHabitResult] {
        let tokens = queryTokens(from: query)

        return habits.compactMap { habit in
            let title = habit.name
            let subtitle = habitSubtitle(for: habit)
            let detail = [habit.description ?? "", habit.updatedAt, habit.createdAt, habitPeriodText(for: habit)]
                .joined(separator: "\n")
            let score = searchScore(title: title, subtitle: subtitle, detail: detail, tokens: tokens)
            guard score > 0 else { return nil }
            return SearchHabitResult(habit: habit, sortScore: score)
        }
        .sorted(by: searchSortComparator)
    }

    static func queryTokens(from query: String) -> [String] {
        query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func searchSortComparator<T: RichSearchSortable>(_ lhs: T, _ rhs: T) -> Bool {
        if lhs.sortScore != rhs.sortScore {
            return lhs.sortScore > rhs.sortScore
        }
        return lhs.sortTitle.localizedStandardCompare(rhs.sortTitle) == .orderedAscending
    }

    static func searchScore(title: String, subtitle: String, detail: String, tokens: [String]) -> Int {
        guard !tokens.isEmpty else { return 0 }

        let titleLower = title.lowercased()
        let subtitleLower = subtitle.lowercased()
        let detailLower = detail.lowercased()

        var score = 0

        for token in tokens {
            guard titleLower.contains(token) || subtitleLower.contains(token) || detailLower.contains(token) else {
                return 0
            }

            if titleLower == token {
                score += 140
            } else if titleLower.hasPrefix(token) {
                score += 100
            } else if titleLower.contains(token) {
                score += 70
            }

            if subtitleLower.contains(token) {
                score += 28
            }

            if detailLower.contains(token) {
                score += 12
            }
        }

        if tokens.count > 1 {
            score += 16
        }

        return score
    }

    static func taskSubtitle(for item: DDLItem, archived: Bool) -> String {
        if !item.note.isEmpty {
            return item.note
        }

        if archived {
            if item.state.isAbandonedLike {
                return item.completeTime.isEmpty ? "已放弃归档" : "放弃于 \(item.completeTime)"
            }
            return item.completeTime.isEmpty ? "已归档" : "完成于 \(item.completeTime)"
        }

        if item.state.isAbandonedLike {
            return "已放弃"
        }

        if !item.endTime.isEmpty {
            return item.endTime
        }

        return "无截止时间"
    }

    static func habitSubtitle(for habit: Habit) -> String {
        if let description = habit.description, !description.isEmpty {
            return description
        }

        return habitPeriodText(for: habit)
    }

    static func habitPeriodText(for habit: Habit) -> String {
        switch habit.period {
        case .daily:
            return "每日"
        case .weekly:
            return "每周"
        case .monthly:
            return "每月"
        case .ebbinghaus:
            return "艾宾浩斯"
        case .once:
            return "单次"
        }
    }

    static func fallbackStatus(for habit: Habit) -> HabitWithDailyStatus {
        HabitWithDailyStatus(
            habit: habit,
            doneCount: 0,
            targetCount: max(1, habit.totalTarget ?? habit.timesPerPeriod),
            isCompleted: false
        )
    }

    static func status(for item: DDLItem) -> DDLStatus {
        if item.state.isAbandonedLike {
            return .abandoned
        }

        if item.isCompleted {
            return .completed
        }

        guard let end = DeadlineDateParser.safeParseOptional(item.endTime) else {
            return .undergo
        }

        let now = Date()
        if end < now {
            return .passed
        }

        let hours = end.timeIntervalSince(now) / 3600
        if hours <= 24 {
            return .near
        }
        return .undergo
    }

    static func remainingTimeText(for item: DDLItem) -> String {
        if item.state.isAbandonedLike {
            return item.isArchived ? "已放弃归档" : "已放弃"
        }

        if item.isCompleted {
            return "已完成"
        }

        guard let end = DeadlineDateParser.safeParseOptional(item.endTime) else {
            return item.endTime
        }

        let now = Date()
        let diffSec = end.timeIntervalSince(now)
        let diffHours = Int(floor(diffSec / 3600.0))

        if diffSec < 0 {
            return "已逾期 \(abs(diffHours)) 小时"
        }

        let days = diffHours / 24
        let hours = diffHours % 24

        if days > 0 {
            return "\(days)天 \(hours)小时"
        }

        return hours == 0 ? "不足1小时" : "\(hours)小时"
    }

    static func progress(for item: DDLItem) -> CGFloat {
        guard
            let start = DeadlineDateParser.safeParseOptional(item.startTime),
            let end = DeadlineDateParser.safeParseOptional(item.endTime),
            end > start
        else {
            return item.isCompleted ? 1 : 0
        }

        if item.isCompleted {
            return 1
        }

        let now = Date()
        if now <= start {
            return 0
        }
        if now >= end {
            return 1
        }

        let raw = now.timeIntervalSince(start) / end.timeIntervalSince(start)
        return CGFloat(min(max(raw, 0), 1))
    }

    static func getEbbinghausState(habit: Habit, targetDate: Date) -> EbbinghausState {
        if habit.period != .ebbinghaus {
            return EbbinghausState(isDue: true, text: "")
        }

        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: targetDate)

        guard let createdAtDate = DeadlineDateParser.safeParseOptional(habit.createdAt) else {
            return EbbinghausState(isDue: true, text: "")
        }

        let startDay = calendar.startOfDay(for: createdAtDate)
        let diffDays = calendar.dateComponents([.day], from: startDay, to: targetDay).day ?? 0
        let curve = [0, 1, 2, 4, 7, 15, 30, 60]

        if diffDays < 0 {
            return EbbinghausState(isDue: false, text: "\(-diffDays) 天后开始")
        }

        if curve.contains(diffDays) {
            return EbbinghausState(isDue: true, text: "")
        }

        if let nextDay = curve.first(where: { $0 > diffDays }) {
            return EbbinghausState(isDue: false, text: "\(nextDay - diffDays) 天后复习")
        }

        return EbbinghausState(isDue: false, text: "已完成记忆周期")
    }

    static func formatDate(_ rawValue: String) -> String {
        guard let date = DeadlineDateParser.safeParseOptional(rawValue) else {
            return rawValue.isEmpty ? "未知时间" : rawValue
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }

    static func formatHabitDetail(_ habit: Habit) -> String {
        "\(habitPeriodText(for: habit)) · 创建于 \(formatDate(habit.createdAt))"
    }

    static func archivedTaskDetail(for item: DDLItem) -> String {
        if item.state.isAbandonedLike {
            return item.completeTime.isEmpty ? "已放弃归档" : "放弃于 \(formatDate(item.completeTime))"
        }

        return formatDate(item.completeTime)
    }

    static func tasks(
        for category: SearchBrowseCategory,
        activeTasks: [DDLItem],
        archivedTasks: [DDLItem]
    ) -> [DDLItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let upcomingEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? today

        switch category {
        case .today:
            return activeTasks.filter { item in
                guard let date = taskRelevantDate(for: item) else { return false }
                return calendar.isDate(date, inSameDayAs: today)
            }
        case .upcoming:
            return activeTasks.filter { item in
                guard let end = DeadlineDateParser.safeParseOptional(item.endTime) else { return false }
                return end >= tomorrow && end <= upcomingEnd
            }
            .sorted { lhs, rhs in
                let left = DeadlineDateParser.safeParseOptional(lhs.endTime) ?? .distantFuture
                let right = DeadlineDateParser.safeParseOptional(rhs.endTime) ?? .distantFuture
                return left < right
            }
        case .starred:
            return activeTasks.filter(\.isStared)
        case .archived:
            return []
        case .tasks:
            return activeTasks
        case .habits:
            return []
        }
    }

    static func habits(for category: SearchBrowseCategory, activeHabits: [Habit]) -> [Habit] {
        switch category {
        case .today:
            return activeHabits.filter { getEbbinghausState(habit: $0, targetDate: Date()).isDue }
        case .habits:
            return activeHabits
        default:
            return []
        }
    }

    static func archivedTasks(for category: SearchBrowseCategory, archivedTasks: [DDLItem]) -> [DDLItem] {
        category == .archived ? archivedTasks : []
    }

    static func archivedHabits(for category: SearchBrowseCategory, archivedHabits: [Habit]) -> [Habit] {
        category == .archived ? archivedHabits : []
    }

    static func taskRelevantDate(for item: DDLItem) -> Date? {
        if let end = DeadlineDateParser.safeParseOptional(item.endTime) {
            return end
        }
        return DeadlineDateParser.safeParseOptional(item.startTime)
    }
}
