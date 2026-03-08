//
//  HabitEntity+Mapping.swift
//  Deadliner
//
//  Created by Gemini CLI on 2026/3/7.
//

import Foundation

extension HabitEntity {
    func toDomain() -> Habit {
        Habit(
            id: legacyId,
            ddlId: ddl?.legacyId ?? -1,
            name: name,
            description: descText,
            color: color,
            iconKey: iconKey,
            period: HabitPeriod(rawValue: periodRaw) ?? .daily,
            timesPerPeriod: timesPerPeriod,
            goalType: HabitGoalType(rawValue: goalTypeRaw) ?? .perPeriod,
            totalTarget: totalTarget,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: HabitStatus(rawValue: statusRaw) ?? .active,
            sortOrder: sortOrder,
            alarmTime: alarmTime
        )
    }
}

extension HabitEntity {
    func apply(domain: Habit) {
        name = domain.name
        descText = domain.description
        color = domain.color
        iconKey = domain.iconKey
        periodRaw = domain.period.rawValue
        timesPerPeriod = domain.timesPerPeriod
        goalTypeRaw = domain.goalType.rawValue
        totalTarget = domain.totalTarget
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        statusRaw = domain.status.rawValue
        sortOrder = domain.sortOrder
        alarmTime = domain.alarmTime
    }
}
