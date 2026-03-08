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
    let isCompleted: Bool
    let completeTime: String
    let note: String
    let isArchived: Bool
    let isStared: Bool
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

    private init() {}

    func isReady() -> Bool { context != nil }

    func initIfNeeded(container: ModelContainer) throws {
        if self.context != nil { return }
        self.container = container
        self.context = ModelContext(container)

        try bootstrapSyncStateIfNeeded()
        try bootstrapSequences()
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

        let now = Date().toLocalISOString()
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
            isCompleted: item.isCompleted,
            completeTime: item.completeTime,
            note: item.note,
            isArchived: item.isArchived,
            isStared: item.isStared,
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
            if $0.isCompleted != $1.isCompleted { return $0.isCompleted == false }
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
        e.isArchived = true
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

        let v = try nextVersionUTC()
        let id = nextId(.subTask)
        let uid = "\(v.dev):st:\(id)"

        let st = SubTaskEntity(
            legacyId: id,
            content: item.content,
            isCompleted: item.isCompleted,
            sortOrder: item.sortOrder,
            uid: uid,
            deleted: false,
            verTs: v.ts,
            verCtr: v.ctr,
            verDev: v.dev,
            ddl: ddl
        )
        context.insert(st)
        try context.save()
        return id
    }

    func getSubTasksByDDL(ddlLegacyId: Int64) throws -> [SubTaskEntity] {
        guard let context else { throw DBError.notInitialized }

        let targetId = ddlLegacyId
        let fd = FetchDescriptor<SubTaskEntity>(
            predicate: #Predicate { $0.deleted == false && $0.ddl?.legacyId == targetId }
        )

        let items = try context.fetch(fd)
        return items.sorted { $0.sortOrder < $1.sortOrder }
    }

    func updateSubTaskStatus(subTaskLegacyId: Int64, isCompleted: Bool) throws {
        guard let context else { throw DBError.notInitialized }
        let fd = FetchDescriptor<SubTaskEntity>(predicate: #Predicate { $0.legacyId == subTaskLegacyId })
        guard let st = try context.fetch(fd).first else { throw DBError.notFound("SubTask \(subTaskLegacyId)") }

        let v = try nextVersionUTC()
        st.isCompleted = isCompleted
        st.verTs = v.ts
        st.verCtr = v.ctr
        st.verDev = v.dev

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

    // MARK: - Habit Record

    @discardableResult
    func insertHabitRecord(habitLegacyId: Int64, record: HabitRecord) throws -> Int64 {
        guard let context else { throw DBError.notInitialized }

        let hFd = FetchDescriptor<HabitEntity>(predicate: #Predicate { $0.legacyId == habitLegacyId })
        guard let habit = try context.fetch(hFd).first else { throw DBError.notFound("Habit \(habitLegacyId)") }

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

        let fd = FetchDescriptor<DDLItemEntity>(
            predicate: #Predicate {
                $0.isTombstoned == false
                && $0.isCompleted == true
                && $0.isArchived == false
                && $0.completeTime != ""
                && $0.completeTime <= thresholdStr
            }
        )
        let list = try context.fetch(fd)
        if list.isEmpty { return 0 }

        let v = try nextVersionUTC()
        for e in list {
            e.isArchived = true
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
            isCompleted: true,
            completeTime: "",
            note: "",
            isArchived: true,
            isStared: false,
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
        e.isCompleted = (doc.is_completed != 0)
        e.completeTime = doc.complete_time
        e.note = doc.note
        e.isArchived = (doc.is_archived != 0)
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

        let entity = DDLItemEntity(
            legacyId: newLocalId,
            name: doc.name,
            startTime: doc.start_time,
            endTime: doc.end_time,
            isCompleted: (doc.is_completed != 0),
            completeTime: doc.complete_time,
            note: doc.note,
            isArchived: (doc.is_archived != 0),
            isStared: (doc.is_stared != 0),
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
}
