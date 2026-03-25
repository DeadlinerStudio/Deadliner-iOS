//
//  Entities.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import Foundation
import SwiftData

@Model
final class SyncStateEntity {
    // 固定单行：id = 1
    @Attribute(.unique) var singletonId: Int
    var deviceId: String
    var lastLocalTs: String
    var lastLocalCtr: Int

    init(
        singletonId: Int = 1,
        deviceId: String,
        lastLocalTs: String = "1970-01-01T00:00:00Z",
        lastLocalCtr: Int = 0
    ) {
        self.singletonId = singletonId
        self.deviceId = deviceId
        self.lastLocalTs = lastLocalTs
        self.lastLocalCtr = lastLocalCtr
    }
}

@Model
final class DDLItemEntity {
    // 跨平台兼容主键（模拟原 SQL 自增 id）
    @Attribute(.unique) var legacyId: Int64

    var name: String
    var startTime: String
    var endTime: String
    var stateRaw: String?
    var isCompleted: Bool
    var completeTime: String
    var note: String
    var isArchived: Bool
    var isStared: Bool
    var subTasksJSON: Data?
    var typeRaw: String
    var habitCount: Int
    var habitTotalCount: Int
    var calendarEventId: Int64
    var timestamp: String
    var habitAppliedVerTs: String?
    var habitAppliedVerCtr: Int?
    var habitAppliedVerDev: String?

    // Sync fields
    @Attribute(.unique) var uid: String?
    var isTombstoned: Bool
    var verTs: String
    var verCtr: Int
    var verDev: String

    // Relations
    @Relationship(deleteRule: .cascade, inverse: \SubTaskEntity.ddl)
    var subTasks: [SubTaskEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \HabitEntity.ddl)
    var habit: HabitEntity?

    init(
        legacyId: Int64,
        name: String,
        startTime: String,
        endTime: String,
        stateRaw: String? = DDLState.active.rawValue,
        isCompleted: Bool,
        completeTime: String,
        note: String,
        isArchived: Bool,
        isStared: Bool,
        subTasksJSON: Data? = nil,
        typeRaw: String,
        habitCount: Int = 0,
        habitTotalCount: Int = 0,
        calendarEventId: Int64 = -1,
        timestamp: String,
        habitAppliedVerTs: String? = nil,
        habitAppliedVerCtr: Int? = nil,
        habitAppliedVerDev: String? = nil,
        uid: String? = nil,
        deleted: Bool = false,
        verTs: String = "1970-01-01T00:00:00Z",
        verCtr: Int = 0,
        verDev: String = ""
    ) {
        self.legacyId = legacyId
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.stateRaw = stateRaw
        self.isCompleted = isCompleted
        self.completeTime = completeTime
        self.note = note
        self.isArchived = isArchived
        self.isStared = isStared
        self.subTasksJSON = subTasksJSON
        self.typeRaw = typeRaw
        self.habitCount = habitCount
        self.habitTotalCount = habitTotalCount
        self.calendarEventId = calendarEventId
        self.timestamp = timestamp
        self.habitAppliedVerTs = habitAppliedVerTs
        self.habitAppliedVerCtr = habitAppliedVerCtr
        self.habitAppliedVerDev = habitAppliedVerDev
        self.uid = uid
        self.isTombstoned = deleted
        self.verTs = verTs
        self.verCtr = verCtr
        self.verDev = verDev
    }
}

@Model
final class HabitEntity {
    @Attribute(.unique) var legacyId: Int64

    // 与 DDL 一对一（通过对象关系保证）
    var name: String
    var descText: String?
    var color: Int?
    var iconKey: String?
    var periodRaw: String
    var timesPerPeriod: Int
    var goalTypeRaw: String
    var totalTarget: Int?
    var createdAt: String
    var updatedAt: String
    var statusRaw: String
    var sortOrder: Int
    var alarmTime: String?

    @Relationship var ddl: DDLItemEntity?

    @Relationship(deleteRule: .cascade, inverse: \HabitRecordEntity.habit)
    var records: [HabitRecordEntity] = []

    init(
        legacyId: Int64,
        name: String,
        descText: String? = nil,
        color: Int? = nil,
        iconKey: String? = nil,
        periodRaw: String,
        timesPerPeriod: Int = 1,
        goalTypeRaw: String = HabitGoalType.perPeriod.rawValue,
        totalTarget: Int? = nil,
        createdAt: String,
        updatedAt: String,
        statusRaw: String = HabitStatus.active.rawValue,
        sortOrder: Int = 0,
        alarmTime: String? = nil,
        ddl: DDLItemEntity? = nil
    ) {
        self.legacyId = legacyId
        self.name = name
        self.descText = descText
        self.color = color
        self.iconKey = iconKey
        self.periodRaw = periodRaw
        self.timesPerPeriod = timesPerPeriod
        self.goalTypeRaw = goalTypeRaw
        self.totalTarget = totalTarget
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.statusRaw = statusRaw
        self.sortOrder = sortOrder
        self.alarmTime = alarmTime
        self.ddl = ddl
    }
}

@Model
final class HabitRecordEntity {
    @Attribute(.unique) var legacyId: Int64
    var date: String
    var count: Int
    var statusRaw: String
    var createdAt: String

    @Relationship var habit: HabitEntity?

    init(
        legacyId: Int64,
        date: String,
        count: Int = 1,
        statusRaw: String = HabitRecordStatus.completed.rawValue,
        createdAt: String,
        habit: HabitEntity? = nil
    ) {
        self.legacyId = legacyId
        self.date = date
        self.count = count
        self.statusRaw = statusRaw
        self.createdAt = createdAt
        self.habit = habit
    }
}

@Model
final class SubTaskEntity {
    @Attribute(.unique) var legacyId: Int64
    var content: String
    var isCompleted: Bool
    var sortOrder: Int

    // Sync
    @Attribute(.unique) var uid: String?
    var deleted: Bool
    var verTs: String
    var verCtr: Int
    var verDev: String

    @Relationship var ddl: DDLItemEntity?

    init(
        legacyId: Int64,
        content: String,
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        uid: String? = nil,
        deleted: Bool = false,
        verTs: String = "1970-01-01T00:00:00Z",
        verCtr: Int = 0,
        verDev: String = "",
        ddl: DDLItemEntity? = nil
    ) {
        self.legacyId = legacyId
        self.content = content
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.uid = uid
        self.deleted = deleted
        self.verTs = verTs
        self.verCtr = verCtr
        self.verDev = verDev
        self.ddl = ddl
    }
}
