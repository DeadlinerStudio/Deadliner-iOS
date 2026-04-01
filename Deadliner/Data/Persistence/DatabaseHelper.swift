//
//  DatabaseHelper.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import Foundation
import SwiftData
import os

struct DDLInsertParams {
    let name: String
    let startTime: String
    let endTime: String
    let state: DDLState
    let completeTime: String
    let note: String
    let isStared: Bool
    let subTasks: [InnerTodo]
    let type: DeadlineType
    let calendarEventId: Int64?
}

struct SubTaskInsertParams {
    let ddlLegacyId: Int64
    let content: String
    let isCompleted: Bool
    let sortOrder: Int
}

actor DatabaseHelper {
    static let shared = DatabaseHelper()

    private var container: ModelContainer?
    private var context: ModelContext?

    // 简单自增序列（替代 SQL AUTOINCREMENT）
    private var ddlSeq: Int64 = 0
    private var subTaskSeq: Int64 = 0
    private var habitSeq: Int64 = 0
    private var habitRecordSeq: Int64 = 0
    
    private let logger = Logger(subsystem: "Deadliner", category: "DatabaseHelper")

    private func trace(_ message: String) {
        logger.info("\(message, privacy: .public)")
        SyncDebugLog.log(message)
    }

    private init() {}

    func isReady() -> Bool { context != nil }

    func initIfNeeded(container: ModelContainer) throws {
        if self.context != nil { return }
        self.container = container
        self.context = ModelContext(container)

        try bootstrapSyncStateIfNeeded()
        try bootstrapSequences()
        try migrateDDLStateAndEmbeddedSubTasksIfNeeded()
    }

    // MARK: - Bootstrap

    private func bootstrapSyncStateIfNeeded() throws {
        guard let context else { throw DBError.notInitialized }

        let fd = FetchDescriptor<SyncStateEntity>(
            predicate: #Predicate { $0.singletonId == 1 }
        )
        let exists = try context.fetch(fd).first
        if exists == nil {
            let s = SyncStateEntity(
                singletonId: 1,
                deviceId: Self.generateRandomHex(bytes: 6)
            )
            context.insert(s)
            try context.save()
        }
    }

    private func bootstrapSequences() throws {
        guard let context else { throw DBError.notInitialized }

        ddlSeq = try maxLegacyId(context: context, for: DDLItemEntity.self)
        subTaskSeq = try maxLegacyId(context: context, for: SubTaskEntity.self)
        habitSeq = try maxLegacyId(context: context, for: HabitEntity.self)
        habitRecordSeq = try maxLegacyId(context: context, for: HabitRecordEntity.self)
    }

    private func nextId(_ type: SeqType) -> Int64 {
        switch type {
        case .ddl:
            ddlSeq += 1; return ddlSeq
        case .subTask:
            subTaskSeq += 1; return subTaskSeq
        case .habit:
            habitSeq += 1; return habitSeq
        case .habitRecord:
            habitRecordSeq += 1; return habitRecordSeq
        }
    }

    // MARK: - Sync Utilities

    func getDeviceId() throws -> String {
        guard let context else { throw DBError.notInitialized }
        let fd = FetchDescriptor<SyncStateEntity>(predicate: #Predicate { $0.singletonId == 1 })
        guard let s = try context.fetch(fd).first else { throw DBError.syncStateMissing }
        return s.deviceId
    }

    func nextVersionUTC() throws -> Ver {
        guard let context else { throw DBError.notInitialized }

        let fd = FetchDescriptor<SyncStateEntity>(predicate: #Predicate { $0.singletonId == 1 })
        guard let s = try context.fetch(fd).first else { throw DBError.syncStateMissing }

        let now = Self.makeVersionTimestampUTC()
        let newer: Ver
        if now > s.lastLocalTs {
            newer = Ver(ts: now, ctr: 0, dev: s.deviceId)
        } else {
            newer = Ver(ts: s.lastLocalTs, ctr: s.lastLocalCtr + 1, dev: s.deviceId)
        }

        s.lastLocalTs = newer.ts
        s.lastLocalCtr = newer.ctr
        try context.save()

        return newer
    }

    // MARK: - DDL Operations

    @discardableResult
    func insertDDL(_ item: DDLInsertParams) throws -> Int64 {
        guard let context else { throw DBError.notInitialized }

        let v = try nextVersionUTC()
        let id = nextId(.ddl)
        let uid = "\(v.dev):\(id)"

        let entity = DDLItemEntity(
            legacyId: id,
            name: item.name,
            startTime: item.startTime,
            endTime: item.endTime,
            stateRaw: item.state.rawValue,
            isCompleted: item.state.isCompletedLike,
            completeTime: item.completeTime,
            note: item.note,
            isArchived: item.state.isArchivedLike,
            isStared: item.isStared,
            subTasksJSON: try Self.encodeSubTasks(item.subTasks),
            typeRaw: item.type.rawValue,
            habitCount: 0,
            habitTotalCount: 0,
            calendarEventId: item.calendarEventId ?? -1,
            timestamp: Self.formatLocalDateTime(Date()),
            uid: uid,
            deleted: false,
            verTs: v.ts,
            verCtr: v.ctr,
            verDev: v.dev
        )
        context.insert(entity)
        try context.save()
        return id
    }

    func getAllDDLs() throws -> [DDLItem] {
        guard let context else { throw DBError.notInitialized }
        let fd = FetchDescriptor<DDLItemEntity>(
            predicate: #Predicate { $0.isTombstoned == false }
        )
        let entities = try context.fetch(fd)
        return entities.map { $0.toDomain() }
    }

    func getDDLById(_ legacyId: Int64) throws -> DDLItem? {
        guard let context else { throw DBError.notInitialized }
        let targetId = legacyId
        let fd = FetchDescriptor<DDLItemEntity>(predicate: #Predicate { $0.legacyId == targetId })
        return try context.fetch(fd).first?.toDomain()
    }

    func getDDLsByType(_ type: DeadlineType) throws -> [DDLItem] {
        guard let context else { throw DBError.notInitialized }

        let typeRaw = type.rawValue
        let fd = FetchDescriptor<DDLItemEntity>(
            predicate: #Predicate { $0.isTombstoned == false && $0.typeRaw == typeRaw }
        )

        let items = try context.fetch(fd)
        let sorted = items.sorted {
            let lhsState = $0.resolvedState()
            let rhsState = $1.resolvedState()
            if lhsState.isCompletedLike != rhsState.isCompletedLike { return lhsState.isCompletedLike == false }
            if $0.endTime != $1.endTime { return $0.endTime < $1.endTime }
            return $0.legacyId < $1.legacyId
        }
        return sorted.map { $0.toDomain() }
    }

    func updateDDL(legacyId: Int64, mutate: (DDLItemEntity) -> Void) throws {
        guard let context else { throw DBError.notInitialized }
        let targetId = legacyId
        let fd = FetchDescriptor<DDLItemEntity>(predicate: #Predicate { $0.legacyId == targetId })
        guard let e = try context.fetch(fd).first else { throw DBError.notFound("DDL \(legacyId)") }

        mutate(e)
        let v = try nextVersionUTC()
        e.timestamp = Self.formatLocalDateTime(Date())
        e.verTs = v.ts
        e.verCtr = v.ctr
        e.verDev = v.dev

        try context.save()
    }

    func deleteDDL(legacyId: Int64) throws {
        try softDeleteDDL(legacyId: legacyId)
    }
    
    func softDeleteDDL(legacyId: Int64) throws {
        guard let context else { throw DBError.notInitialized }

        let targetId = legacyId
        let fd = FetchDescriptor<DDLItemEntity>(
            predicate: #Predicate { $0.legacyId == targetId }
        )
        guard let e = try context.fetch(fd).first else {
            throw DBError.notFound("DDL \(legacyId)")
        }

        // 关键字段一次性明确写入
        e.isTombstoned = true
        e.stateRaw = DDLState.archived.rawValue
        e.isArchived = true
        e.isCompleted = true
        if e.completeTime.isEmpty {
            e.completeTime = Date().toLocalISOString()
        }

        let v = try nextVersionUTC()
        e.verTs = v.ts
        e.verCtr = v.ctr
        e.verDev = v.dev
        e.timestamp = Self.formatLocalDateTime(Date())

        try context.save()
    }

    // MARK: - SubTask

    @discardableResult
    func insertSubTask(_ item: SubTaskInsertParams) throws -> Int64 {
        guard let context else { throw DBError.notInitialized }
        let targetId = item.ddlLegacyId
        let ddlFd = FetchDescriptor<DDLItemEntity>(predicate: #Predicate { $0.legacyId == targetId })
        guard let ddl = try context.fetch(ddlFd).first else { throw DBError.notFound("DDL \(targetId)") }

        let id = nextId(.subTask)
        var subTasks = try ddl.decodedSubTasks()
        subTasks.append(
            InnerTodo(
                id: String(id),
                content: item.content,
                isCompleted: item.isCompleted,
                sortOrder: item.sortOrder,
                createdAt: Date().toLocalISOString(),
                updatedAt: Date().toLocalISOString()
            )
        )
        ddl.subTasksJSON = try Self.encodeSubTasks(subTasks)
        let v = try nextVersionUTC()
        ddl.verTs = v.ts
        ddl.verCtr = v.ctr
        ddl.verDev = v.dev
        ddl.timestamp = Self.formatLocalDateTime(Date())
        try context.save()
        return id
    }

    func getSubTasksByDDL(ddlLegacyId: Int64) throws -> [InnerTodo] {
        guard let context else { throw DBError.notInitialized }

        let targetId = ddlLegacyId
        let fd = FetchDescriptor<DDLItemEntity>(
            predicate: #Predicate { $0.legacyId == targetId }
        )
        guard let ddl = try context.fetch(fd).first else { throw DBError.notFound("DDL \(ddlLegacyId)") }
        return try ddl.decodedSubTasks().sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.id < rhs.id
        }
    }

    func updateSubTaskStatus(ddlLegacyId: Int64, subTaskId: String, isCompleted: Bool) throws {
        guard let context else { throw DBError.notInitialized }
        let fd = FetchDescriptor<DDLItemEntity>(predicate: #Predicate { $0.legacyId == ddlLegacyId })
        guard let ddl = try context.fetch(fd).first else { throw DBError.notFound("DDL \(ddlLegacyId)") }

        var subTasks = try ddl.decodedSubTasks()
        guard let index = subTasks.firstIndex(where: { $0.id == subTaskId }) else {
            throw DBError.notFound("SubTask \(subTaskId)")
        }

        let v = try nextVersionUTC()
        subTasks[index].isCompleted = isCompleted
        subTasks[index].updatedAt = Date().toLocalISOString()
        ddl.subTasksJSON = try Self.encodeSubTasks(subTasks)
        ddl.verTs = v.ts
        ddl.verCtr = v.ctr
        ddl.verDev = v.dev
        ddl.timestamp = Self.formatLocalDateTime(Date())

        try context.save()
    }

    // MARK: - Habit

    @discardableResult
    func insertHabit(ddlLegacyId: Int64, habit: Habit) throws -> Int64 {
        guard let context else { throw DBError.notInitialized }

        let ddlFd = FetchDescriptor<DDLItemEntity>(predicate: #Predicate { $0.legacyId == ddlLegacyId })
        guard let ddl = try context.fetch(ddlFd).first else { throw DBError.notFound("DDL \(ddlLegacyId)") }

        let id = nextId(.habit)
        let entity = HabitEntity(
            legacyId: id,
            name: habit.name,
            descText: habit.description,
            color: habit.color,
            iconKey: habit.iconKey,
            periodRaw: habit.period.rawValue,
            timesPerPeriod: habit.timesPerPeriod,
            goalTypeRaw: habit.goalType.rawValue,
            totalTarget: habit.totalTarget,
            createdAt: habit.createdAt,
            updatedAt: habit.updatedAt,
            statusRaw: habit.status.rawValue,
            sortOrder: habit.sortOrder,
            alarmTime: habit.alarmTime,
            ddl: ddl
        )

        context.insert(entity)
        ddl.habit = entity
        try context.save()
        return id
    }

    func updateHabit(_ habit: Habit) throws {
        guard let context else { throw DBError.notInitialized }
        let targetId = habit.id
        let fd = FetchDescriptor<HabitEntity>(predicate: #Predicate { $0.legacyId == targetId })
        guard let e = try context.fetch(fd).first else { throw DBError.notFound("Habit \(habit.id)") }

        e.apply(domain: habit)
        try context.save()
    }

    func getHabitByDDLId(ddlLegacyId: Int64) throws -> Habit? {
        guard let context else { throw DBError.notInitialized }
        let targetId = ddlLegacyId
        let fd = FetchDescriptor<HabitEntity>(predicate: #Predicate { $0.ddl?.legacyId == targetId })
        return try context.fetch(fd).first?.toDomain()
    }

    func getHabitById(id: Int64) throws -> Habit? {
        guard let context else { throw DBError.notInitialized }
        let targetId = id
        let fd = FetchDescriptor<HabitEntity>(predicate: #Predicate { $0.legacyId == targetId })
        return try context.fetch(fd).first?.toDomain()
    }

    func getAllHabits() throws -> [Habit] {
        guard let context else { throw DBError.notInitialized }
        let fd = FetchDescriptor<HabitEntity>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.legacyId)])
        let entities = try context.fetch(fd)
        return entities.map { $0.toDomain() }
    }

    func deleteHabit(legacyId: Int64) throws {
        guard let context else { throw DBError.notInitialized }
        let targetId = legacyId
        let fd = FetchDescriptor<HabitEntity>(predicate: #Predicate { $0.legacyId == targetId })
        if let e = try context.fetch(fd).first {
            context.delete(e)
            try context.save()
        }
    }

    func deleteHabitByDDLId(ddlLegacyId: Int64) throws {
        guard let context else { throw DBError.notInitialized }
        let targetId = ddlLegacyId
        let fd = FetchDescriptor<HabitEntity>(predicate: #Predicate { $0.ddl?.legacyId == targetId })
        if let e = try context.fetch(fd).first {
            context.delete(e)
            try context.save()
        }
    }

    func getHabitEntityByDDLUID(_ ddlUID: String) throws -> HabitEntity? {
        guard let context else { throw DBError.notInitialized }
        let uid = ddlUID
        let fd = FetchDescriptor<HabitEntity>(predicate: #Predicate { $0.ddl?.uid == uid })
        return try context.fetch(fd).first
    }

    func upsertHabitFromSnapshotV2(
        ddlUID: String,
        payload: HabitSnapshotV2Payload
    ) throws -> HabitEntity {
        guard let context else { throw DBError.notInitialized }
        try Self.validateHabitSnapshotPayload(payload)

        let uid = ddlUID
        let ddlFD = FetchDescriptor<DDLItemEntity>(predicate: #Predicate { $0.uid == uid })
        guard let ddl = try context.fetch(ddlFD).first else {
            throw DBError.notFound("Habit carrier DDL for uid \(ddlUID)")
        }
        guard ddl.typeRaw == DeadlineType.habit.rawValue else {
            throw DBError.invalidData("DDL \(ddlUID) is not a habit carrier")
        }

        if let existing = ddl.habit {
            trace("upsertHabitFromSnapshotV2 update uid=\(ddlUID) habitId=\(existing.legacyId) oldUpdatedAt=\(existing.updatedAt) newUpdatedAt=\(payload.updated_at)")
            existing.name = payload.name
            existing.descText = payload.description
            existing.color = payload.color
            existing.iconKey = payload.icon_key
            existing.periodRaw = payload.period
            existing.timesPerPeriod = payload.times_per_period
            existing.goalTypeRaw = payload.goal_type
            existing.totalTarget = payload.total_target
            existing.createdAt = payload.created_at
            existing.updatedAt = payload.updated_at
            existing.statusRaw = payload.status
            existing.sortOrder = payload.sort_order
            existing.alarmTime = payload.alarm_time
            existing.ddl = ddl
            try context.save()
            return existing
        }

        let habit = HabitEntity(
            legacyId: nextId(.habit),
            name: payload.name,
            descText: payload.description,
            color: payload.color,
            iconKey: payload.icon_key,
            periodRaw: payload.period,
            timesPerPeriod: payload.times_per_period,
            goalTypeRaw: payload.goal_type,
            totalTarget: payload.total_target,
            createdAt: payload.created_at,
            updatedAt: payload.updated_at,
            statusRaw: payload.status,
            sortOrder: payload.sort_order,
            alarmTime: payload.alarm_time,
            ddl: ddl
        )
        trace("upsertHabitFromSnapshotV2 insert uid=\(ddlUID) habitId=\(habit.legacyId) updatedAt=\(payload.updated_at)")
        context.insert(habit)
        ddl.habit = habit
        try context.save()
        return habit
    }

    func replaceHabitRecordsFromSnapshotV2(
        habitLegacyId: Int64,
        records: [HabitRecordSnapshotV2Payload]
    ) throws {
        guard let context else { throw DBError.notInitialized }
        try records.forEach { try Self.validateHabitRecordSnapshotPayload($0) }
        let habitId = habitLegacyId

        let hFD = FetchDescriptor<HabitEntity>(predicate: #Predicate { $0.legacyId == habitId })
        guard let habit = try context.fetch(hFD).first else {
            throw DBError.notFound("Habit \(habitLegacyId)")
        }

        let rFD = FetchDescriptor<HabitRecordEntity>(predicate: #Predicate { $0.habit?.legacyId == habitId })
        let existing = try context.fetch(rFD)
        trace("replaceHabitRecordsFromSnapshotV2 begin habitId=\(habitLegacyId) existing=\(existing.count) incoming=\(records.count)")
        for record in existing {
            context.delete(record)
        }

        for record in records {
            let entity = HabitRecordEntity(
                legacyId: nextId(.habitRecord),
                date: record.date,
                count: record.count,
                statusRaw: record.status,
                createdAt: record.created_at,
                habit: habit
            )
            context.insert(entity)
        }

        try context.save()
        trace("replaceHabitRecordsFromSnapshotV2 end habitId=\(habitLegacyId) final=\(records.count)")
    }

    func touchDDLVersion(legacyId: Int64) throws {
        guard let context else { throw DBError.notInitialized }
        let targetId = legacyId
        let fd = FetchDescriptor<DDLItemEntity>(predicate: #Predicate { $0.legacyId == targetId })
        guard let ddl = try context.fetch(fd).first else {
            throw DBError.notFound("DDL \(legacyId)")
        }

        let v = try nextVersionUTC()
        ddl.verTs = v.ts
        ddl.verCtr = v.ctr
        ddl.verDev = v.dev
        ddl.timestamp = Self.formatLocalDateTime(Date())
        try context.save()
    }

    func setDDLVersionByUID(uid: String, ver: SnapshotVer) throws {
        guard let context else { throw DBError.notInitialized }
        let targetUID = uid
        let fd = FetchDescriptor<DDLItemEntity>(predicate: #Predicate { $0.uid == targetUID })
        guard let ddl = try context.fetch(fd).first else {
            throw DBError.notFound("DDL uid \(uid)")
        }

        ddl.verTs = ver.ts
        ddl.verCtr = ver.ctr
        ddl.verDev = ver.dev
        ddl.timestamp = Self.formatLocalDateTime(Date())
        try context.save()
    }

    func setHabitAppliedVersionByUID(uid: String, ver: SnapshotVer) throws {
        guard let context else { throw DBError.notInitialized }
        let targetUID = uid
        let fd = FetchDescriptor<DDLItemEntity>(predicate: #Predicate { $0.uid == targetUID })
        guard let ddl = try context.fetch(fd).first else {
            throw DBError.notFound("DDL uid \(uid)")
        }

        trace("setHabitAppliedVersionByUID uid=\(uid) ver=\(ver.ts)#\(ver.ctr)#\(ver.dev)")
        ddl.setHabitAppliedSnapshotVersion(ts: ver.ts, ctr: ver.ctr, dev: ver.dev)
        try context.save()
    }

    func touchHabitCarrierVersionByHabitId(habitLegacyId: Int64) throws {
        guard let context else { throw DBError.notInitialized }
        let habitId = habitLegacyId
        let fd = FetchDescriptor<HabitEntity>(predicate: #Predicate { $0.legacyId == habitId })
        guard let habit = try context.fetch(fd).first, let ddl = habit.ddl else {
            throw DBError.notFound("Habit carrier for habit \(habitLegacyId)")
        }

        let v = try nextVersionUTC()
        trace("touchHabitCarrierVersionByHabitId habitId=\(habitLegacyId) ddlId=\(ddl.legacyId) uid=\(ddl.uid ?? "") newVer=\(v.ts)#\(v.ctr)#\(v.dev) oldUpdatedAt=\(habit.updatedAt)")
        habit.updatedAt = v.ts
        ddl.verTs = v.ts
        ddl.verCtr = v.ctr
        ddl.verDev = v.dev
        ddl.timestamp = Self.formatLocalDateTime(Date())
        try context.save()
    }

    // MARK: - Habit Record

    @discardableResult
    func insertHabitRecord(habitLegacyId: Int64, record: HabitRecord) throws -> Int64 {
        guard let context else { throw DBError.notInitialized }

        let hFd = FetchDescriptor<HabitEntity>(predicate: #Predicate { $0.legacyId == habitLegacyId })
        guard let habit = try context.fetch(hFd).first else { throw DBError.notFound("Habit \(habitLegacyId)") }

        let beforeCount = try context.fetch(
            FetchDescriptor<HabitRecordEntity>(predicate: #Predicate { $0.habit?.legacyId == habitLegacyId })
        ).count

        let id = nextId(.habitRecord)
        let entity = HabitRecordEntity(
            legacyId: id,
            date: record.date,
            count: record.count,
            statusRaw: record.status.rawValue,
            createdAt: record.createdAt,
            habit: habit
        )

        context.insert(entity)
        try context.save()
        trace("insertHabitRecord habitId=\(habitLegacyId) recordId=\(id) date=\(record.date) count=\(record.count) before=\(beforeCount) after=\(beforeCount + 1)")
        return id
    }

    func deleteHabitRecord(legacyId: Int64) throws {
        guard let context else { throw DBError.notInitialized }
        let targetId = legacyId
        let fd = FetchDescriptor<HabitRecordEntity>(predicate: #Predicate { $0.legacyId == targetId })
        if let e = try context.fetch(fd).first {
            context.delete(e)
            try context.save()
        }
    }

    func getHabitRecordsForHabitOnDate(habitLegacyId: Int64, date: String) throws -> [HabitRecord] {
        guard let context else { throw DBError.notInitialized }
        let hId = habitLegacyId
        let d = date
        let fd = FetchDescriptor<HabitRecordEntity>(
            predicate: #Predicate { $0.habit?.legacyId == hId && $0.date == d }
        )
        return try context.fetch(fd).map { $0.toDomain() }
    }

    func getHabitRecordsForDate(date: String) throws -> [HabitRecord] {
        guard let context else { throw DBError.notInitialized }
        let d = date
        let fd = FetchDescriptor<HabitRecordEntity>(predicate: #Predicate { $0.date == d })
        return try context.fetch(fd).map { $0.toDomain() }
    }

    func getHabitRecordsInRange(startDate: String, endDate: String) throws -> [HabitRecord] {
        guard let context else { throw DBError.notInitialized }
        let s = startDate
        let e = endDate
        
        let fd = FetchDescriptor<HabitRecordEntity>()
        let all = try context.fetch(fd)
        return all.filter { $0.date >= s && $0.date <= e }
            .sorted { $0.date < $1.date }
            .map { $0.toDomain() }
    }

    func getHabitRecordsForHabitInRange(habitLegacyId: Int64, startDate: String, endDate: String) throws -> [HabitRecord] {
        guard let context else { throw DBError.notInitialized }
        let hId = habitLegacyId
        let s = startDate
        let e = endDate
        
        // SwiftData Predicate 对 String 范围查询支持有限，这里先查出该习惯的所有记录再过滤，或者按 legacyId 范围查
        let fd = FetchDescriptor<HabitRecordEntity>(
            predicate: #Predicate { $0.habit?.legacyId == hId }
        )
        let all = try context.fetch(fd)
        return all.filter { $0.date >= s && $0.date <= e }
            .sorted { $0.date < $1.date }
            .map { $0.toDomain() }
    }

    func deleteHabitRecordsForHabitOnDate(habitLegacyId: Int64, date: String) throws {
        guard let context else { throw DBError.notInitialized }
        let hId = habitLegacyId
        let d = date
        let fd = FetchDescriptor<HabitRecordEntity>(
            predicate: #Predicate { $0.habit?.legacyId == hId && $0.date == d }
        )
        let targets = try context.fetch(fd)
        trace("deleteHabitRecordsForHabitOnDate habitId=\(habitLegacyId) date=\(date) deleteCount=\(targets.count)")
        for t in targets {
            context.delete(t)
        }
        try context.save()
    }

    // MARK: - Archive

    func autoArchiveDDLs(days: Int) throws -> Int {
        guard let context else { throw DBError.notInitialized }
        guard days >= 0 else { return 0 }

        let threshold = Date().addingTimeInterval(TimeInterval(-days * 24 * 3600))
        let thresholdStr = threshold.toLocalISOString()
        let completedStateRaw = DDLState.completed.rawValue

        let fd = FetchDescriptor<DDLItemEntity>(
            predicate: #Predicate {
                $0.isTombstoned == false
                && $0.stateRaw == completedStateRaw
                && $0.completeTime != ""
                && $0.completeTime <= thresholdStr
            }
        )
        let list = try context.fetch(fd)
        if list.isEmpty { return 0 }

        let v = try nextVersionUTC()
        for e in list {
            e.stateRaw = DDLState.archived.rawValue
            e.isArchived = true
            e.isCompleted = true
            e.verTs = v.ts
            e.verCtr = v.ctr
            e.verDev = v.dev
        }

        try context.save()
        return list.count
    }

    // MARK: - Helpers

    private static func generateRandomHex(bytes: Int) -> String {
        let chars = Array("0123456789ABCDEF")
        return String((0..<(bytes * 2)).map { _ in chars.randomElement()! })
    }

    private static func makeVersionTimestampUTC() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func validateHabitSnapshotPayload(_ payload: HabitSnapshotV2Payload) throws {
        guard !payload.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DBError.invalidData("Habit snapshot name must not be empty")
        }
        guard HabitPeriod(rawValue: payload.period) != nil else {
            throw DBError.invalidData("Invalid habit period '\(payload.period)'")
        }
        guard payload.times_per_period > 0 else {
            throw DBError.invalidData("Habit times_per_period must be greater than 0")
        }
        guard HabitGoalType(rawValue: payload.goal_type) != nil else {
            throw DBError.invalidData("Invalid habit goal_type '\(payload.goal_type)'")
        }
        guard HabitStatus(rawValue: payload.status) != nil else {
            throw DBError.invalidData("Invalid habit status '\(payload.status)'")
        }
    }

    private static func validateHabitRecordSnapshotPayload(_ payload: HabitRecordSnapshotV2Payload) throws {
        guard !payload.date.isEmpty else {
            throw DBError.invalidData("Habit record date must not be empty")
        }
        guard payload.count > 0 else {
            throw DBError.invalidData("Habit record count must be greater than 0")
        }
        guard HabitRecordStatus(rawValue: payload.status) != nil else {
            throw DBError.invalidData("Invalid habit record status '\(payload.status)'")
        }
        guard !payload.created_at.isEmpty else {
            throw DBError.invalidData("Habit record created_at must not be empty")
        }
    }

    private static func formatLocalDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: date)
    }

    private func maxLegacyId<T: PersistentModel>(
        context: ModelContext,
        for type: T.Type
    ) throws -> Int64 {
        let fd = FetchDescriptor<T>()
        let all = try context.fetch(fd)
        
        // SwiftData 的 @Model 属性对 Mirror 不友好，改为针对已知类型手动提取
        if type == DDLItemEntity.self {
            return (all as? [DDLItemEntity])?.map { $0.legacyId }.max() ?? 0
        } else if type == SubTaskEntity.self {
            return (all as? [SubTaskEntity])?.map { $0.legacyId }.max() ?? 0
        } else if type == HabitEntity.self {
            return (all as? [HabitEntity])?.map { $0.legacyId }.max() ?? 0
        } else if type == HabitRecordEntity.self {
            return (all as? [HabitRecordEntity])?.map { $0.legacyId }.max() ?? 0
        }
        
        return 0
    }
    
    // MARK: - Sync Bridge (v1 snapshot)

    func getAllDDLsIncludingDeletedForSync() throws -> [DDLItemEntity] {
        guard let context else { throw DBError.notInitialized }
        let fd = FetchDescriptor<DDLItemEntity>() // 不加 predicate，包含 deleted
        return try context.fetch(fd)
    }

    func pruneExpiredTombstones(olderThan retentionDays: Int) throws -> Int {
        guard let context else { throw DBError.notInitialized }
        guard retentionDays > 0 else { return 0 }

        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let fd = FetchDescriptor<DDLItemEntity>(predicate: #Predicate { $0.isTombstoned == true })
        let tombstones = try context.fetch(fd)

        var deletedCount = 0
        for entity in tombstones {
            guard let tombstoneDate = DeadlineDateParser.safeParseOptional(entity.verTs) else { continue }
            guard tombstoneDate < cutoff else { continue }
            context.delete(entity)
            deletedCount += 1
        }

        if deletedCount > 0 {
            try context.save()
        }

        return deletedCount
    }

    func findDDLByUID(_ uid: String) throws -> DDLItemEntity? {
        guard let context else { throw DBError.notInitialized }
        let fd = FetchDescriptor<DDLItemEntity>(
            predicate: #Predicate { $0.uid == uid }
        )
        return try context.fetch(fd).first
    }

    func insertTombstoneByUID(
        uid: String,
        verTs: String,
        verCtr: Int,
        verDev: String
    ) throws {
        guard let context else { throw DBError.notInitialized }

        // 如果已存在同 uid，直接改墓碑状态即可（幂等）
        if let existing = try findDDLByUID(uid) {
            existing.isTombstoned = true
            existing.stateRaw = DDLState.archived.rawValue
            existing.isArchived = true
            existing.isCompleted = true
            existing.verTs = verTs
            existing.verCtr = verCtr
            existing.verDev = verDev
            try context.save()
            return
        }

        let id = nextId(.ddl)
        let tombstone = DDLItemEntity(
            legacyId: id,
            name: "(deleted)",
            startTime: "",
            endTime: "",
            stateRaw: DDLState.archived.rawValue,
            isCompleted: true,
            completeTime: "",
            note: "",
            isArchived: true,
            isStared: false,
            subTasksJSON: try Self.encodeSubTasks([]),
            typeRaw: DeadlineType.task.rawValue,
            habitCount: 0,
            habitTotalCount: 0,
            calendarEventId: -1,
            timestamp: verTs,
            uid: uid,
            deleted: true,
            verTs: verTs,
            verCtr: verCtr,
            verDev: verDev
        )
        context.insert(tombstone)
        try context.save()
    }

    func applyTombstone(
        legacyId: Int64,
        verTs: String,
        verCtr: Int,
        verDev: String
    ) throws {
        guard let context else { throw DBError.notInitialized }

        let targetId = legacyId
        let fd = FetchDescriptor<DDLItemEntity>(
            predicate: #Predicate<DDLItemEntity> { item in
                item.legacyId == targetId
            }
        )
        guard let e = try context.fetch(fd).first else {
            throw DBError.notFound("DDL \(legacyId)")
        }

        e.isTombstoned = true
        e.stateRaw = DDLState.archived.rawValue
        e.isArchived = true
        e.isCompleted = true
        e.verTs = verTs
        e.verCtr = verCtr
        e.verDev = verDev

        try context.save()
    }

    func overwriteDDLFromSnapshotEntity(
        entity e: DDLItemEntity,
        doc: SnapshotDoc,
        verTs: String,
        verCtr: Int,
        verDev: String
    ) throws {
        guard context != nil else { throw DBError.notInitialized }

        e.isTombstoned = false
        e.name = doc.name
        e.startTime = doc.start_time
        e.endTime = doc.end_time
        let state = Self.stateFromV1Flags(isCompleted: doc.is_completed != 0, isArchived: doc.is_archived != 0)
        e.stateRaw = state.rawValue
        e.isCompleted = state.isCompletedLike
        e.completeTime = doc.complete_time
        e.note = doc.note
        e.isArchived = state.isArchivedLike
        e.isStared = (doc.is_stared != 0)
        e.typeRaw = doc.type
        e.habitCount = doc.habit_count
        e.habitTotalCount = doc.habit_total_count
        e.calendarEventId = doc.calendar_event
        e.timestamp = doc.timestamp

        e.verTs = verTs
        e.verCtr = verCtr
        e.verDev = verDev

        try context!.save()
    }

    func overwriteDDLFromSnapshot(
        legacyId: Int64,
        doc: SnapshotDoc,
        verTs: String,
        verCtr: Int,
        verDev: String
    ) throws {
        guard let context else { throw DBError.notInitialized }
        let fd = FetchDescriptor<DDLItemEntity>(
            predicate: #Predicate { $0.legacyId == legacyId }
        )
        guard let entity = try context.fetch(fd).first else {
            throw DBError.notFound("DDL \(legacyId)")
        }
        try overwriteDDLFromSnapshotEntity(
            entity: entity,
            doc: doc,
            verTs: verTs,
            verCtr: verCtr,
            verDev: verDev
        )
    }

    func overwriteDDLFromSnapshotV2Entity(
        entity e: DDLItemEntity,
        doc: SnapshotV2Doc,
        verTs: String,
        verCtr: Int,
        verDev: String
    ) throws {
        guard context != nil else { throw DBError.notInitialized }
        guard let state = DDLState(rawValue: doc.state) else {
            throw DBError.invalidData("Invalid V2 state '\(doc.state)'")
        }

        e.isTombstoned = false
        e.name = doc.name
        e.startTime = doc.start_time
        e.endTime = doc.end_time
        e.stateRaw = state.rawValue
        e.isCompleted = state.isCompletedLike
        e.completeTime = doc.complete_time
        e.note = doc.note
        e.isArchived = state.isArchivedLike
        e.isStared = (doc.is_stared != 0)
        e.subTasksJSON = try Self.encodeSubTasks(doc.sub_tasks.map { $0.toDomain() })
        e.typeRaw = doc.type
        e.habitCount = doc.habit_count
        e.habitTotalCount = doc.habit_total_count
        e.calendarEventId = doc.calendar_event
        e.timestamp = doc.timestamp

        e.verTs = verTs
        e.verCtr = verCtr
        e.verDev = verDev

        try context!.save()
    }

    func insertDDLFromSnapshotV2(
        uid: String,
        doc: SnapshotV2Doc,
        verTs: String,
        verCtr: Int,
        verDev: String
    ) throws {
        guard let context else { throw DBError.notInitialized }
        guard let state = DDLState(rawValue: doc.state) else {
            throw DBError.invalidData("Invalid V2 state '\(doc.state)'")
        }

        if let existing = try findDDLByUID(uid) {
            try overwriteDDLFromSnapshotV2Entity(
                entity: existing,
                doc: doc,
                verTs: verTs,
                verCtr: verCtr,
                verDev: verDev
            )
            return
        }

        let newLocalId = nextId(.ddl)
        let entity = DDLItemEntity(
            legacyId: newLocalId,
            name: doc.name,
            startTime: doc.start_time,
            endTime: doc.end_time,
            stateRaw: state.rawValue,
            isCompleted: state.isCompletedLike,
            completeTime: doc.complete_time,
            note: doc.note,
            isArchived: state.isArchivedLike,
            isStared: (doc.is_stared != 0),
            subTasksJSON: try Self.encodeSubTasks(doc.sub_tasks.map { $0.toDomain() }),
            typeRaw: doc.type,
            habitCount: doc.habit_count,
            habitTotalCount: doc.habit_total_count,
            calendarEventId: doc.calendar_event,
            timestamp: doc.timestamp,
            uid: uid,
            deleted: false,
            verTs: verTs,
            verCtr: verCtr,
            verDev: verDev
        )

        context.insert(entity)
        try context.save()
    }

    func insertDDLFromSnapshot(
        uid: String,
        doc: SnapshotDoc,
        verTs: String,
        verCtr: Int,
        verDev: String
    ) throws {
        guard let context else { throw DBError.notInitialized }

        // 幂等保护：如果本地已经有这个 uid，直接用实体覆盖更新
        if let existing = try findDDLByUID(uid) {
            try overwriteDDLFromSnapshotEntity(
                entity: existing,
                doc: doc,
                verTs: verTs,
                verCtr: verCtr,
                verDev: verDev
            )
            return
        }

        let newLocalId = nextId(.ddl)

        let state = Self.stateFromV1Flags(
            isCompleted: doc.is_completed != 0,
            isArchived: doc.is_archived != 0
        )

        let entity = DDLItemEntity(
            legacyId: newLocalId,
            name: doc.name,
            startTime: doc.start_time,
            endTime: doc.end_time,
            stateRaw: state.rawValue,
            isCompleted: state.isCompletedLike,
            completeTime: doc.complete_time,
            note: doc.note,
            isArchived: state.isArchivedLike,
            isStared: (doc.is_stared != 0),
            subTasksJSON: try Self.encodeSubTasks([]),
            typeRaw: doc.type,
            habitCount: doc.habit_count,
            habitTotalCount: doc.habit_total_count,
            calendarEventId: doc.calendar_event,
            timestamp: doc.timestamp,
            uid: uid,
            deleted: false,
            verTs: verTs,
            verCtr: verCtr,
            verDev: verDev
        )

        context.insert(entity)
        try context.save()
    }
    
    private func bumpDDLSeqIfNeeded(_ id: Int64) {
        if id > ddlSeq { ddlSeq = id }
    }

    private func migrateDDLStateAndEmbeddedSubTasksIfNeeded() throws {
        guard let context else { throw DBError.notInitialized }

        let ddlFD = FetchDescriptor<DDLItemEntity>()
        let ddls = try context.fetch(ddlFD)

        let subTaskFD = FetchDescriptor<SubTaskEntity>()
        let subTaskEntities = try context.fetch(subTaskFD)
        let groupedSubTasks = Dictionary(grouping: subTaskEntities.filter { $0.deleted == false }) { entity in
            entity.ddl?.legacyId
        }

        var hasChanges = false

        for ddl in ddls {
            // Preserve any already-valid canonical stateRaw, including newer states
            // like abandoned / abandonedArchived. Only backfill from legacy booleans
            // when stateRaw is missing or invalid.
            let expectedState = Self.stateFromLegacy(isCompleted: ddl.isCompleted, isArchived: ddl.isArchived)
            if ddl.currentState() == nil {
                ddl.stateRaw = expectedState.rawValue
                hasChanges = true
            }

            if ddl.subTasksJSON == nil {
                let migrated = (groupedSubTasks[ddl.legacyId] ?? []).sorted { lhs, rhs in
                    if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                    return lhs.legacyId < rhs.legacyId
                }.map { entity in
                    InnerTodo(
                        id: String(entity.legacyId),
                        content: entity.content,
                        isCompleted: entity.isCompleted,
                        sortOrder: entity.sortOrder
                    )
                }
                ddl.subTasksJSON = try Self.encodeSubTasks(migrated)
                hasChanges = true
            } else {
                _ = try ddl.decodedSubTasks()
            }
        }

        if hasChanges {
            try context.save()
        }
    }

    private static func stateFromLegacy(isCompleted: Bool, isArchived: Bool) -> DDLState {
        if isArchived { return .archived }
        if isCompleted { return .completed }
        return .active
    }

    private static func stateFromV1Flags(isCompleted: Bool, isArchived: Bool) -> DDLState {
        stateFromLegacy(isCompleted: isCompleted, isArchived: isArchived)
    }

    private static func encodeSubTasks(_ subTasks: [InnerTodo]) throws -> Data {
        try DDLItemEntity.encodeSubTasks(subTasks)
    }
    
    // MARK: - Repair Corrupted Data
    func repairDuplicateData() throws -> Int {
        guard let context else { throw DBError.notInitialized }
            
        // 1. 获取所有数据（包含已删除/被墓碑化的）
        let fd = FetchDescriptor<DDLItemEntity>()
        let allItems = try context.fetch(fd)
            
        var uidMap: [String: DDLItemEntity] = [:]
        var deletedDuplicatesCount = 0
            
        // 2. 按 uid 去重，只保留最新的那条，物理删除其余分身
        for item in allItems {
            let uid = item.uid ?? ""
            if let existing = uidMap[uid] {
                // 判断哪个版本更新
                let isItemNewer: Bool
                if item.verTs != existing.verTs {
                    isItemNewer = item.verTs > existing.verTs
                } else if item.verCtr != existing.verCtr {
                    isItemNewer = item.verCtr > existing.verCtr
                } else {
                    isItemNewer = item.verDev >= existing.verDev
                }
                    
                if isItemNewer {
                    context.delete(existing) // 删掉旧的
                    uidMap[uid] = item
                    deletedDuplicatesCount += 1
                } else {
                    context.delete(item)     // 删掉这一个
                    deletedDuplicatesCount += 1
                }
            } else {
                uidMap[uid] = item
            }
        }
            
        // 3. 重新校准序列号，防止后续新增又撞车
        ddlSeq = try maxLegacyId(context: context, for: DDLItemEntity.self)
        
        try context.save()
        logger.info("Repaired database. Deleted \(deletedDuplicatesCount) duplicate records.")
        return deletedDuplicatesCount
    }
}

enum SeqType { case ddl, subTask, habit, habitRecord }

enum DBError: Error {
    case notInitialized
    case syncStateMissing
    case notFound(String)
    case invalidData(String)
}

private extension SnapshotV2InnerTodo {
    func toDomain() -> InnerTodo {
        InnerTodo(
            id: id,
            content: content,
            isCompleted: is_completed != 0,
            sortOrder: sort_order,
            createdAt: created_at,
            updatedAt: updated_at
        )
    }
}
