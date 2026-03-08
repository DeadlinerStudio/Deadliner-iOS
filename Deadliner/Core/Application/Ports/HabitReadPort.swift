//
//  HabitReadPort.swift
//  Deadliner
//
//  Created by Gemini CLI on 2026/3/7.
//

import Foundation

protocol HabitReadPort {
    func getHabitByDDLId(ddlLegacyId: Int64) async throws -> Habit?
    func getHabitsByStatus(status: HabitStatus) async throws -> [Habit]
    func getRecordsByHabitId(habitLegacyId: Int64) async throws -> [HabitRecord]
    func getRecordsByDate(date: String) async throws -> [HabitRecord]
}
