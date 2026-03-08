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
    var id: Int64 { habit.id }
    let habit: Habit
    var doneCount: Int
    var targetCount: Int
    var isCompleted: Bool
}

struct EbbinghausState: Equatable {
    let isDue: Bool
    let text: String
}
