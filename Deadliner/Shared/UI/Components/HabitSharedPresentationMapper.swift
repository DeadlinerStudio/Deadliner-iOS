//
//  HabitSharedPresentationMapper.swift
//  Deadliner
//
//  Thin iOS projection over the KMP Habit presentation authority.
//

import Foundation
#if canImport(Shared)
import Shared

enum HabitSharedPresentationMapper {
    static func statusMap(
        from state: HabitListUiState,
        on date: Date
    ) -> [String: HabitWithDailyStatus] {
        let activeHabits = state.habits.filter {
            !$0.isDeleted && $0.status == .active
        }
        let statuses = HabitPresentationEngine.shared.statuses(
            habits: activeHabits,
            records: state.records,
            rawDate: date.toDateString(),
            today: localDate(date)
        )
        return Dictionary(uniqueKeysWithValues: statuses.map { status in
            (status.habit.uid, projection(status))
        })
    }

    static func projection(_ status: Shared.HabitDayStatus) -> HabitWithDailyStatus {
        HabitWithDailyStatus(
            habit: status.habit.projection(),
            doneCount: Int(status.doneCount),
            targetCount: Int(status.targetCount),
            isCompleted: status.isCompleted,
            isDue: status.scheduleState.isDue,
            canApplyPrimaryAction: status.canApplyPrimaryAction,
            primaryActionAmount: Int(status.primaryAction.amount),
            progressText: progressText(status),
            scheduleLabel: scheduleLabel(status.habit),
            scheduleHintText: scheduleHint(status)
        )
    }

    static func scheduleLabel(for habit: Habit) -> String {
        let scheduleText: String
        switch habit.period {
        case .daily, .weekly, .monthly:
            scheduleText = weekdayLabel(mask: habit.weekdaysMask)
        case .once:
            scheduleText = "单次"
        case .ebbinghaus:
            scheduleText = "艾宾浩斯"
        }

        let goalText: String?
        if habit.goalType == .total {
            goalText = "总目标 \(max(1, habit.totalTarget ?? habit.timesPerPeriod))"
        } else {
            switch habit.period {
            case .weekly: goalText = "每周"
            case .monthly: goalText = "每月"
            case .daily, .once, .ebbinghaus: goalText = nil
            }
        }

        return [scheduleText, goalText]
            .compactMap { $0 }
            .reduce(into: [String]()) { labels, label in
                if !labels.contains(label) { labels.append(label) }
            }
            .joined(separator: " · ")
    }

    static func weekdayLabel(mask: Int) -> String {
        let normalized = mask & 0b1111111
        if normalized == 0b1111111 { return "每天" }
        if normalized == 0b0011111 { return "工作日" }
        if normalized == 0b1100000 { return "周末" }

        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        let mondayFirst = Array(symbols.dropFirst()) + [symbols[0]]
        let selected = mondayFirst.enumerated()
            .filter { normalized & (1 << $0.offset) != 0 }
            .map(\.element)
        return selected.isEmpty ? "未设置执行日" : selected.joined(separator: "/")
    }

    private static func progressText(_ status: Shared.HabitDayStatus) -> String {
        let base = "\(status.doneCount)/\(status.targetCount)"
        guard let unit = status.habit.tracking.unit, !unit.isEmpty else { return base }
        return "\(base) \(unit)"
    }

    private static func scheduleLabel(_ habit: Habit_) -> String {
        let scheduleText: String
        if habit.schedule.kind == .algorithm {
            scheduleText = habit.schedule.algorithmKey == "EBBINGHAUS_CLASSIC_V1"
                ? "艾宾浩斯"
                : "算法计划"
        } else if habit.schedule.kind == .once {
            scheduleText = "单次"
        } else {
            let mask = habit.schedule.weekdaysMask.map { Int($0.intValue) } ?? 127
            scheduleText = weekdayLabel(mask: mask)
        }

        let goalText: String?
        if habit.goal.window == .lifetime {
            goalText = "总目标 \(habit.goal.targetCount)"
        } else if habit.goal.window == .month {
            goalText = "每月"
        } else if habit.goal.window == .week {
            goalText = "每周"
        } else {
            goalText = nil
        }

        return [scheduleText, goalText]
            .compactMap { $0 }
            .reduce(into: [String]()) { labels, label in
                if !labels.contains(label) { labels.append(label) }
            }
            .joined(separator: " · ")
    }

    private static func scheduleHint(_ status: Shared.HabitDayStatus) -> String {
        guard let hint = status.scheduleState.hintKind else { return "" }
        let days = status.scheduleState.daysUntil.map { Int($0.intValue) }
        if hint == .startsIn { return days.map { "\($0) 天后开始" } ?? "" }
        if hint == .nextReviewIn { return days.map { "\($0) 天后复习" } ?? "" }
        if hint == .completedCycle { return "已完成记忆周期" }
        return ""
    }

    private static func localDate(_ date: Date) -> Kotlinx_datetimeLocalDate {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return Kotlinx_datetimeLocalDate(
            year: Int32(components.year ?? 1970),
            month: Int32(components.month ?? 1),
            day: Int32(components.day ?? 1)
        )
    }
}
#endif
