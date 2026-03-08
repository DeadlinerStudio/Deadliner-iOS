//
//  HabitRecordEntity+Mapping.swift
//  Deadliner
//
//  Created by Gemini CLI on 2026/3/7.
//

import Foundation

extension HabitRecordEntity {
    func toDomain() -> HabitRecord {
        HabitRecord(
            id: legacyId,
            habitId: habit?.legacyId ?? -1,
            date: date,
            count: count,
            status: HabitRecordStatus(rawValue: statusRaw) ?? .completed,
            createdAt: createdAt
        )
    }
}

extension HabitRecordEntity {
    func apply(domain: HabitRecord) {
        date = domain.date
        count = domain.count
        statusRaw = domain.status.rawValue
        createdAt = domain.createdAt
    }
}
