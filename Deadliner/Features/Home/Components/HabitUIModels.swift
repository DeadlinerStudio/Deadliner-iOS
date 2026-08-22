//
//  HabitUIModels.swift
//  Deadliner
//
//  Created by Gemini CLI on 2026/3/7.
//

import Foundation

struct DayOverview: Identifiable, Equatable {
    var id: String { date.toDateString() }
    let date: Date
    let completedCount: Int
    let totalCount: Int
    let completionRatio: Double
}

struct HabitWithDailyStatus: Identifiable, Equatable {
    var id: String { habit.id }
    let habit: Habit
    var doneCount: Int
    var targetCount: Int
    var isCompleted: Bool
    var isDue: Bool = true
    var canApplyPrimaryAction: Bool = true
    var primaryActionAmount: Int = 1
    var progressText: String? = nil
    var scheduleLabel: String? = nil
    var scheduleHintText: String = ""
}
