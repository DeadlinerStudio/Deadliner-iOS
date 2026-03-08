//
//  HabitWritePort.swift
//  Deadliner
//
//  Created by Gemini CLI on 2026/3/7.
//

import Foundation

protocol HabitWritePort {
    @discardableResult
    func insertHabit(
        ddlLegacyId: Int64,
        habit: Habit
    ) async throws -> Int64
    
    func updateHabit(_ habit: Habit) async throws
    
    func deleteHabit(legacyId: Int64) async throws
    
    @discardableResult
    func recordHabit(
        habitLegacyId: Int64,
        date: String,
        count: Int,
        status: HabitRecordStatus
    ) async throws -> Int64
    
    func deleteRecord(recordLegacyId: Int64) async throws
}
