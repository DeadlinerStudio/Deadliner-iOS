//
//  Habit.swift
//  Deadliner
//
//  Created by Gemini CLI on 2026/3/7.
//

import Foundation

struct Habit: Identifiable, Equatable, Sendable {
    let id: Int64
    let ddlId: Int64
    
    var name: String
    var description: String?
    var color: Int?
    var iconKey: String?
    
    var period: HabitPeriod
    var timesPerPeriod: Int
    var goalType: HabitGoalType
    var totalTarget: Int?
    
    var createdAt: String
    var updatedAt: String
    var status: HabitStatus
    var sortOrder: Int
    var alarmTime: String?
}
