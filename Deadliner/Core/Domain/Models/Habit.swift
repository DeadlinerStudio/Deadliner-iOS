//
//  Habit.swift
//  Deadliner
//
//  Created by Gemini CLI on 2026/3/7.
//

import Foundation

struct Habit: Identifiable, Equatable, Sendable {
    /// KMP Habit aggregate UID. `ddlId` existed only for the old carrier row.
    let id: String
    
    var name: String
    var description: String?
    var color: Int?
    var iconKey: String?
    var categoryUID: String? = nil
    
    var period: HabitPeriod
    /// Monday is bit 0 and Sunday is bit 6, matching KMP HabitWeekdays.
    var weekdaysMask: Int = 127
    var timesPerPeriod: Int
    var goalType: HabitGoalType
    var totalTarget: Int?
    
    var createdAt: String
    var updatedAt: String
    var status: HabitStatus
    var sortOrder: Int
    var alarmTime: String?
}
