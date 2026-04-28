//
//  SyncServiceV2.swift
//  Deadliner
//

import Foundation
import os

actor SyncServiceV2: SyncService {
    private let db: DatabaseHelper
    private let web: WebDAVClient
    private let snapshotV2Path = "Deadliner/snapshot-v2.json"
    private let habitSnapshotV2Path = "Deadliner/habit-snapshot-v2.json"
    private let snapshotV1Path = "Deadliner/snapshot-v1.json"
    private let logger = Logger(subsystem: "Deadliner", category: "SyncServiceV2")

    init(db: DatabaseHelper, web: WebDAVClient) {
        self.db = db
        self.web = web
    }

    private func trace(_ message: String) {
        logger.info("\(message, privacy: .public)")
        SyncDebugLog.log(message)
    }

    private func tombstoneRetentionCutoff() async -> Date? {
        let retentionDays = await LocalValues.shared.getTombstoneRetentionDays()
        guard retentionDays > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())
    }

    private func shouldKeepDeletedItem(verTs: String, cutoff: Date?) -> Bool {
        guard let cutoff else { return true }
        guard let tombstoneDate = DeadlineDateParser.safeParseOptional(verTs) else { return true }
        return tombstoneDate >= cutoff
    }

    private func pruneExpiredDeletedItems(_ items: [SnapshotV2Item], cutoff: Date?) -> [SnapshotV2Item] {
        items.filter { item in
            !item.deleted || shouldKeepDeletedItem(verTs: item.ver.ts, cutoff: cutoff)
        }
    }

    private func pruneExpiredDeletedItems(_ items: [HabitSnapshotV2Item], cutoff: Date?) -> [HabitSnapshotV2Item] {
        items.filter { item in
            !item.deleted || shouldKeepDeletedItem(verTs: item.ver.ts, cutoff: cutoff)
        }
    }

    func syncOnce() async -> SyncResult {
        do {
            return try await syncAllSnapshotsOnce()
        } catch {
            logger.error("syncOnce failed: \(error.localizedDescription, privacy: .public)")
            SyncDebugLog.log("syncOnce failed: \(error.localizedDescription)")
            return .init(success: false, hasLocalChanges: false)
        }
    }

    private func buildLocalSnapshotV2() async throws -> SnapshotV2Root {
        let items = try await db.getAllDDLsIncludingDeletedForSync()
        let cutoff = await tombstoneRetentionCutoff()

        let snapshotItems = try items.compactMap { entity -> SnapshotV2Item? in
            guard let uid = entity.uid, !uid.isEmpty else { return nil }

            let ver = SnapshotVer(ts: entity.verTs, ctr: entity.verCtr, dev: entity.verDev)
            if entity.isTombstoned {
                guard shouldKeepDeletedItem(verTs: ver.ts, cutoff: cutoff) else {
                    trace("buildLocalSnapshotV2 prune expired tombstone uid=\(uid) ver=\(ver.ts)#\(ver.ctr)#\(ver.dev)")
                    return nil
                }
                return SnapshotV2Item(uid: uid, ver: ver, deleted: true, doc: nil)
            }

            let doc = SnapshotV2Doc(
                id: entity.legacyId,
                name: entity.name,
                start_time: entity.startTime,
                end_time: entity.endTime,
                state: entity.resolvedStateForSync().rawValue,
                complete_time: entity.completeTime,
                note: entity.note,
                is_stared: entity.isStared ? 1 : 0,
                type: entity.typeRaw,
                habit_count: entity.habitCount,
                habit_total_count: entity.habitTotalCount,
                calendar_event: entity.calendarEventId,
                timestamp: entity.timestamp,
                sub_tasks: try entity.decodedSubTasks().map { $0.toSnapshotV2() }
            )
            return SnapshotV2Item(uid: uid, ver: ver, deleted: false, doc: doc)
        }

        let dev = try await db.getDeviceId()
        let now = Date().toLocalISOString()
        return SnapshotV2Root(version: .init(ts: now, dev: dev), items: snapshotItems)
    }

    private func isVerNewer(_ a: SnapshotVer, _ b: SnapshotVer) -> Bool {
        if a.ts != b.ts { return a.ts > b.ts }
        if a.ctr != b.ctr { return a.ctr > b.ctr }
        if a.dev != b.dev { return a.dev > b.dev }
        return false
    }

    private func isHabitPayloadCaughtUp(habitUpdatedAt: String, carrierVerTs: String) -> Bool {
        if habitUpdatedAt == carrierVerTs { return true }
        guard let left = DeadlineDateParser.safeParseOptional(habitUpdatedAt),
              let right = DeadlineDateParser.safeParseOptional(carrierVerTs) else {
            // Fallback: if timestamps match to second-level granularity, treat as caught up.
            return normalizeToSecond(habitUpdatedAt) == normalizeToSecond(carrierVerTs)
        }
        // Accept formatter/precision drift in the same-second to tens-of-ms range.
        if abs(left.timeIntervalSince(right)) <= 0.050 {
            return true
        }
        // Secondary fallback for mixed timestamp formats where parser precision may differ.
        return normalizeToSecond(habitUpdatedAt) == normalizeToSecond(carrierVerTs)
    }

    private func normalizeToSecond(_ raw: String) -> String {
        // Keep "yyyy-MM-ddTHH:mm:ss" part only; ignore fractional/timezone decoration.
        if raw.count >= 19 {
            return String(raw.prefix(19))
        }
        return raw
    }

    private func merge(local: SnapshotV2Root, remoteRoots: [SnapshotV2Root]) -> SnapshotV2Root {
        let cutoff = TaskLocalSyncContext.tombstoneCutoff
        var map: [String: SnapshotV2Item] = [:]
        for item in pruneExpiredDeletedItems(local.items, cutoff: cutoff) {
            map[item.uid] = item
        }

        for root in remoteRoots {
            for item in pruneExpiredDeletedItems(root.items, cutoff: cutoff) {
                if let existing = map[item.uid] {
                    if isVerNewer(item.ver, existing.ver) {
                        map[item.uid] = item
                    }
                } else {
                    map[item.uid] = item
                }
            }
        }

        return SnapshotV2Root(version: local.version, items: Array(map.values))
    }

    private func applySnapshotToLocal(_ merged: SnapshotV2Root) async throws -> Bool {
        var changed = false

        for item in merged.items {
            let mergedVer = item.ver
            let local = try await db.findDDLByUID(item.uid)

            if let local {
                let localVer = SnapshotVer(ts: local.verTs, ctr: local.verCtr, dev: local.verDev)
                if !isVerNewer(mergedVer, localVer) {
                    continue
                }
            }

            if item.deleted {
                if let local {
                    try await db.applyTombstone(
                        legacyId: local.legacyId,
                        verTs: mergedVer.ts,
                        verCtr: mergedVer.ctr,
                        verDev: mergedVer.dev
                    )
                } else {
                    try await db.insertTombstoneByUID(
                        uid: item.uid,
                        verTs: mergedVer.ts,
                        verCtr: mergedVer.ctr,
                        verDev: mergedVer.dev
                    )
                }
                changed = true
                continue
            }

            guard let doc = item.doc else {
                throw DBError.invalidData("V2 snapshot item missing doc for uid \(item.uid)")
            }

            if let local {
                try await db.overwriteDDLFromSnapshotV2Entity(
                    entity: local,
                    doc: doc,
                    verTs: mergedVer.ts,
                    verCtr: mergedVer.ctr,
                    verDev: mergedVer.dev
                )
            } else {
                try await db.insertDDLFromSnapshotV2(
                    uid: item.uid,
                    doc: doc,
                    verTs: mergedVer.ts,
                    verCtr: mergedVer.ctr,
                    verDev: mergedVer.dev
                )
            }
            changed = true
        }

        return changed
    }

    private func loadRemoteV2IfPresent(decoder: JSONDecoder) async throws -> (root: SnapshotV2Root?, etag: String?) {
        let head = try await web.head(path: snapshotV2Path)
        if [404, 409, 410].contains(head.code) {
            return (nil, nil)
        }

        let remote = try await web.getBytes(path: snapshotV2Path)
        let root = try decoder.decode(SnapshotV2Root.self, from: remote.bytes)
        return (root, remote.etag)
    }

    private func loadRemoteV1AsV2IfPresent(decoder: JSONDecoder) async throws -> (root: SnapshotV2Root?, etag: String?) {
        let head = try await web.head(path: snapshotV1Path)
        if [404, 409, 410].contains(head.code) {
            return (nil, nil)
        }

        let remote = try await web.getBytes(path: snapshotV1Path)
        let root = try decoder.decode(SnapshotRoot.self, from: remote.bytes)
        return (try projectV1RootToV2(root), remote.etag)
    }

    private func projectV1RootToV2(_ root: SnapshotRoot) throws -> SnapshotV2Root {
        let items = try root.items.map { item in
            if item.deleted {
                return SnapshotV2Item(uid: item.uid, ver: item.ver, deleted: true, doc: nil)
            }

            guard let doc = item.doc else {
                throw DBError.invalidData("V1 snapshot item missing doc for uid \(item.uid)")
            }

            let state = stateFromV1Flags(isCompleted: doc.is_completed != 0, isArchived: doc.is_archived != 0)
            return SnapshotV2Item(
                uid: item.uid,
                ver: item.ver,
                deleted: false,
                doc: SnapshotV2Doc(
                    id: doc.id,
                    name: doc.name,
                    start_time: doc.start_time,
                    end_time: doc.end_time,
                    state: state.rawValue,
                    complete_time: doc.complete_time,
                    note: doc.note,
                    is_stared: doc.is_stared,
                    type: doc.type,
                    habit_count: doc.habit_count,
                    habit_total_count: doc.habit_total_count,
                    calendar_event: doc.calendar_event,
                    timestamp: doc.timestamp,
                    sub_tasks: []
                )
            )
        }

        return SnapshotV2Root(
            version: .init(ts: root.version.ts, dev: root.version.dev),
            items: items
        )
    }

    nonisolated func projectV2RootToV1(_ root: SnapshotV2Root) throws -> SnapshotRoot {
        let items = try root.items.map { item in
            if item.deleted {
                return SnapshotItem(uid: item.uid, ver: item.ver, deleted: true, doc: nil)
            }

            guard let doc = item.doc else {
                throw DBError.invalidData("V2 snapshot item missing doc for uid \(item.uid)")
            }

            let state = try parseState(doc.state)
            let projectedState = projectStateToV1(state)
            return SnapshotItem(
                uid: item.uid,
                ver: item.ver,
                deleted: false,
                doc: SnapshotDoc(
                    id: doc.id,
                    name: doc.name,
                    start_time: doc.start_time,
                    end_time: doc.end_time,
                    is_completed: projectedState.isCompletedLike ? 1 : 0,
                    complete_time: doc.complete_time,
                    note: doc.note,
                    is_archived: projectedState.isArchivedLike ? 1 : 0,
                    is_stared: doc.is_stared,
                    type: doc.type,
                    habit_count: doc.habit_count,
                    habit_total_count: doc.habit_total_count,
                    calendar_event: doc.calendar_event,
                    timestamp: doc.timestamp
                )
            )
        }

        return SnapshotRoot(version: .init(ts: root.version.ts, dev: root.version.dev), items: items)
    }

    private func syncDDLSnapshotOnce() async throws -> SyncResult {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let cutoff = await tombstoneRetentionCutoff()

        return try await TaskLocalSyncContext.$tombstoneCutoff.withValue(cutoff) {
            let local = try await buildLocalSnapshotV2()
            let remoteV2 = try await loadRemoteV2IfPresent(decoder: decoder)
            let remoteV1Compat = try await loadRemoteV1AsV2IfPresent(decoder: decoder)
            let merged = merge(local: local, remoteRoots: [remoteV2.root, remoteV1Compat.root].compactMap { $0 })

            let mergedV2Bytes = try encoder.encode(merged)
            let mergedV1 = try projectV2RootToV1(merged)
            let mergedV1Bytes = try encoder.encode(mergedV1)

            do {
                _ = await web.ensureDir("Deadliner")
                _ = try await web.putBytes(
                    path: snapshotV2Path,
                    bytes: mergedV2Bytes,
                    ifMatch: remoteV2.etag,
                    ifNoneMatchStar: remoteV2.root == nil
                )
            } catch is PreconditionFailedError {
                let refreshedV2 = try await loadRemoteV2IfPresent(decoder: decoder)
                let refreshedV1 = try await loadRemoteV1AsV2IfPresent(decoder: decoder)
                let mergedRetry = merge(local: local, remoteRoots: [refreshedV2.root, refreshedV1.root].compactMap { $0 })

                let retryV2Bytes = try encoder.encode(mergedRetry)
                _ = try await web.putBytes(
                    path: snapshotV2Path,
                    bytes: retryV2Bytes,
                    ifMatch: refreshedV2.etag,
                    ifNoneMatchStar: refreshedV2.root == nil
                )

                let retryV1 = try projectV2RootToV1(mergedRetry)
                _ = try await web.putBytes(
                    path: snapshotV1Path,
                    bytes: try encoder.encode(retryV1),
                    ifMatch: refreshedV1.etag,
                    ifNoneMatchStar: refreshedV1.root == nil
                )

                let hasChanges = try await applySnapshotToLocal(mergedRetry)
                return .init(success: true, hasLocalChanges: hasChanges)
            }

            _ = try await web.putBytes(
                path: snapshotV1Path,
                bytes: mergedV1Bytes,
                ifMatch: remoteV1Compat.etag,
                ifNoneMatchStar: remoteV1Compat.root == nil
            )

            let hasChanges = try await applySnapshotToLocal(merged)
            return .init(success: true, hasLocalChanges: hasChanges)
        }
    }

    private func buildLocalHabitSnapshotV2() async throws -> HabitSnapshotV2Root {
        let items = try await db.getAllDDLsIncludingDeletedForSync()
        let dev = try await db.getDeviceId()
        let cutoff = await tombstoneRetentionCutoff()

        let snapshotItems = try items.compactMap { entity -> HabitSnapshotV2Item? in
            guard entity.typeRaw == DeadlineType.habit.rawValue else { return nil }
            guard let uid = entity.uid, !uid.isEmpty else { return nil }

            let ver = SnapshotVer(ts: entity.verTs, ctr: entity.verCtr, dev: entity.verDev)
            if entity.isTombstoned {
                guard shouldKeepDeletedItem(verTs: ver.ts, cutoff: cutoff) else {
                    trace("buildLocalHabitSnapshotV2 prune expired tombstone uid=\(uid) carrierVer=\(ver.ts)#\(ver.ctr)#\(ver.dev)")
                    return nil
                }
                return HabitSnapshotV2Item(uid: uid, ver: ver, deleted: true, doc: nil)
            }

            guard let habit = entity.habit else {
                guard entity.verDev == dev else {
                    trace("buildLocalHabitSnapshotV2 skip remote-carrier-without-habit uid=\(uid) carrierVer=\(ver.ts)#\(ver.ctr)#\(ver.dev)")
                    return nil
                }
                trace("buildLocalHabitSnapshotV2 emit tombstone uid=\(uid) carrierVer=\(ver.ts)#\(ver.ctr)#\(ver.dev)")
                return HabitSnapshotV2Item(uid: uid, ver: ver, deleted: true, doc: nil)
            }

            if let applied = entity.habitAppliedSnapshotVersionRaw() {
                let appliedVer = SnapshotVer(ts: applied.ts, ctr: applied.ctr, dev: applied.dev)
                let carrierAheadOfApplied = isVerNewer(ver, appliedVer)
                let habitPayloadCaughtUp = isHabitPayloadCaughtUp(habitUpdatedAt: habit.updatedAt, carrierVerTs: ver.ts)
                if carrierAheadOfApplied && !habitPayloadCaughtUp {
                    trace("buildLocalHabitSnapshotV2 skip stale-local-habit uid=\(uid) carrierVer=\(ver.ts)#\(ver.ctr)#\(ver.dev) appliedVer=\(appliedVer.ts)#\(appliedVer.ctr)#\(appliedVer.dev) status=\(habit.statusRaw) records=\(habit.records.count) updatedAt=\(habit.updatedAt)")
                    return nil
                }
            }

            trace("buildLocalHabitSnapshotV2 emit doc uid=\(uid) carrierVer=\(ver.ts)#\(ver.ctr)#\(ver.dev) status=\(habit.statusRaw) records=\(habit.records.count) updatedAt=\(habit.updatedAt)")

            let doc = HabitSnapshotV2Doc(
                ddl_uid: uid,
                // Always align payload timestamp to carrier version to avoid stale-gate loops.
                habit: habit.toHabitSnapshotV2Payload(updatedAtOverride: ver.ts),
                records: habit.records
                    .sorted { lhs, rhs in
                        if lhs.date != rhs.date { return lhs.date < rhs.date }
                        return lhs.createdAt < rhs.createdAt
                    }
                    .map { $0.toHabitRecordSnapshotV2Payload() }
            )

            return HabitSnapshotV2Item(uid: uid, ver: ver, deleted: false, doc: doc)
        }

        let emittedDocCount = snapshotItems.reduce(0) { $0 + ($1.deleted ? 0 : 1) }
        let emittedTombstoneCount = snapshotItems.reduce(0) { $0 + ($1.deleted ? 1 : 0) }
        trace("buildLocalHabitSnapshotV2 summary items=\(snapshotItems.count) emittedDocCount=\(emittedDocCount) emittedTombstoneCount=\(emittedTombstoneCount)")

        let now = Date().toLocalISOString()
        return HabitSnapshotV2Root(version: .init(ts: now, dev: dev), items: snapshotItems)
    }

    private func merge(local: HabitSnapshotV2Root, remote: HabitSnapshotV2Root?) -> HabitSnapshotV2Root {
        let cutoff = TaskLocalSyncContext.tombstoneCutoff
        var map: [String: HabitSnapshotV2Item] = [:]
        for item in pruneExpiredDeletedItems(local.items, cutoff: cutoff) {
            map[item.uid] = item
        }

        for item in pruneExpiredDeletedItems(remote?.items ?? [], cutoff: cutoff) {
            if let existing = map[item.uid] {
                if isVerNewer(item.ver, existing.ver) {
                    trace("mergeHabitSnapshot replace uid=\(item.uid) localVer=\(existing.ver.ts)#\(existing.ver.ctr)#\(existing.ver.dev) remoteVer=\(item.ver.ts)#\(item.ver.ctr)#\(item.ver.dev) remoteDeleted=\(item.deleted)")
                    map[item.uid] = item
                } else {
                    trace("mergeHabitSnapshot keep-local uid=\(item.uid) localVer=\(existing.ver.ts)#\(existing.ver.ctr)#\(existing.ver.dev) remoteVer=\(item.ver.ts)#\(item.ver.ctr)#\(item.ver.dev) remoteDeleted=\(item.deleted)")
                }
            } else {
                trace("mergeHabitSnapshot insert-remote uid=\(item.uid) remoteVer=\(item.ver.ts)#\(item.ver.ctr)#\(item.ver.dev) remoteDeleted=\(item.deleted)")
                map[item.uid] = item
            }
        }

        return HabitSnapshotV2Root(version: local.version, items: Array(map.values))
    }

    private func loadRemoteHabitV2IfPresent(decoder: JSONDecoder) async throws -> (root: HabitSnapshotV2Root?, etag: String?) {
        let head = try await web.head(path: habitSnapshotV2Path)
        if [404, 409, 410].contains(head.code) {
            return (nil, nil)
        }

        let remote = try await web.getBytes(path: habitSnapshotV2Path)
        let root = try decoder.decode(HabitSnapshotV2Root.self, from: remote.bytes)
        return (root, remote.etag)
    }

    private func applyHabitSnapshotToLocal(_ merged: HabitSnapshotV2Root) async throws -> Bool {
        var changed = false

        for item in merged.items {
            let ddl = try await db.findDDLByUID(item.uid)

            if item.deleted && ddl == nil {
                trace("applyHabitSnapshotToLocal skip-missing-local-tombstone uid=\(item.uid) ver=\(item.ver.ts)#\(item.ver.ctr)#\(item.ver.dev)")
                continue
            }

            guard let ddl else {
                throw DBError.notFound("Habit carrier DDL uid \(item.uid)")
            }

            if let appliedVer = ddl.habitAppliedSnapshotVersionRaw(),
               !isVerNewer(item.ver, SnapshotVer(ts: appliedVer.ts, ctr: appliedVer.ctr, dev: appliedVer.dev)) {
                trace("applyHabitSnapshotToLocal skip-not-newer uid=\(item.uid) incoming=\(item.ver.ts)#\(item.ver.ctr)#\(item.ver.dev) applied=\(appliedVer.ts)#\(appliedVer.ctr)#\(appliedVer.dev) localHasHabit=\(ddl.habit != nil)")
                continue
            }

            if item.deleted {
                if ddl.habit != nil {
                    trace("applyHabitSnapshotToLocal delete uid=\(item.uid) incoming=\(item.ver.ts)#\(item.ver.ctr)#\(item.ver.dev)")
                    try await db.deleteHabitByDDLId(ddlLegacyId: ddl.legacyId)
                }
                try await db.setHabitAppliedVersionByUID(uid: item.uid, ver: item.ver)
                changed = true
                continue
            }

            guard let doc = item.doc else {
                throw DBError.invalidData("Habit snapshot item missing doc for uid \(item.uid)")
            }
            guard doc.ddl_uid == item.uid else {
                throw DBError.invalidData("Habit snapshot ddl_uid mismatch for uid \(item.uid)")
            }

            trace("applyHabitSnapshotToLocal upsert uid=\(item.uid) incoming=\(item.ver.ts)#\(item.ver.ctr)#\(item.ver.dev) records=\(doc.records.count)")
            let habit = try await db.upsertHabitFromSnapshotV2(ddlUID: item.uid, payload: doc.habit)
            try await db.replaceHabitRecordsFromSnapshotV2(habitLegacyId: habit.legacyId, records: doc.records)
            try await db.setHabitAppliedVersionByUID(uid: item.uid, ver: item.ver)
            changed = true
        }

        return changed
    }

    private func syncHabitSnapshotOnce() async throws -> SyncResult {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let cutoff = await tombstoneRetentionCutoff()

        return try await TaskLocalSyncContext.$tombstoneCutoff.withValue(cutoff) {
            let local = try await buildLocalHabitSnapshotV2()
            let remote = try await loadRemoteHabitV2IfPresent(decoder: decoder)
            let merged = merge(local: local, remote: remote.root)
            let localBytes = try encoder.encode(local)
            let mergedBytes = try encoder.encode(merged)
            let mergedChanged = (localBytes != mergedBytes)
            trace("syncHabitSnapshotOnce mergedChanged=\(mergedChanged) localItems=\(local.items.count) mergedItems=\(merged.items.count)")

            do {
                _ = await web.ensureDir("Deadliner")
                trace("syncHabitSnapshotOnce willPut path=\(habitSnapshotV2Path) size=\(mergedBytes.count)")
                let putEtag = try await web.putBytes(
                    path: habitSnapshotV2Path,
                    bytes: mergedBytes,
                    ifMatch: remote.etag,
                    ifNoneMatchStar: remote.root == nil
                )
                trace("syncHabitSnapshotOnce didPut path=\(habitSnapshotV2Path) etag=\(putEtag ?? "")")
            } catch is PreconditionFailedError {
                let refreshed = try await loadRemoteHabitV2IfPresent(decoder: decoder)
                let mergedRetry = merge(local: local, remote: refreshed.root)
                let retryBytes = try encoder.encode(mergedRetry)
                trace("syncHabitSnapshotOnce retry willPut path=\(habitSnapshotV2Path) size=\(retryBytes.count)")
                let retryEtag = try await web.putBytes(
                    path: habitSnapshotV2Path,
                    bytes: retryBytes,
                    ifMatch: refreshed.etag,
                    ifNoneMatchStar: refreshed.root == nil
                )
                trace("syncHabitSnapshotOnce retry didPut path=\(habitSnapshotV2Path) etag=\(retryEtag ?? "")")
                let hasChanges = try await applyHabitSnapshotToLocal(mergedRetry)
                return .init(success: true, hasLocalChanges: hasChanges)
            }

            let hasChanges = try await applyHabitSnapshotToLocal(merged)
            return .init(success: true, hasLocalChanges: hasChanges)
        }
    }

    private func syncAllSnapshotsOnce() async throws -> SyncResult {
        let ddlResult = try await syncDDLSnapshotOnce()
        let habitResult = try await syncHabitSnapshotOnce()
        return .init(
            success: ddlResult.success && habitResult.success,
            hasLocalChanges: ddlResult.hasLocalChanges || habitResult.hasLocalChanges
        )
    }

    nonisolated func parseState(_ raw: String) throws -> DDLState {
        guard let state = DDLState(rawValue: raw) else {
            throw DBError.invalidData("Invalid V2 state '\(raw)'")
        }
        return state
    }

    nonisolated func stateFromV1Flags(isCompleted: Bool, isArchived: Bool) -> DDLState {
        if isArchived { return .archived }
        if isCompleted { return .completed }
        return .active
    }

    nonisolated func projectStateToV1(_ state: DDLState) -> DDLState {
        switch state {
        case .active, .completed, .archived:
            return state
        case .abandoned, .abandonedArchived:
            return .archived
        }
    }
}

private enum TaskLocalSyncContext {
    @TaskLocal static var tombstoneCutoff: Date?
}

private extension InnerTodo {
    func toSnapshotV2() -> SnapshotV2InnerTodo {
        SnapshotV2InnerTodo(
            id: id,
            content: content,
            is_completed: isCompleted ? 1 : 0,
            sort_order: sortOrder,
            created_at: createdAt,
            updated_at: updatedAt
        )
    }
}

private extension HabitEntity {
    func toHabitSnapshotV2Payload(updatedAtOverride: String? = nil) -> HabitSnapshotV2Payload {
        HabitSnapshotV2Payload(
            name: name,
            description: descText,
            color: color,
            icon_key: iconKey,
            period: periodRaw,
            times_per_period: timesPerPeriod,
            goal_type: goalTypeRaw,
            total_target: totalTarget,
            created_at: createdAt,
            updated_at: updatedAtOverride ?? updatedAt,
            status: statusRaw,
            sort_order: sortOrder,
            alarm_time: alarmTime
        )
    }
}

private extension HabitRecordEntity {
    func toHabitRecordSnapshotV2Payload() -> HabitRecordSnapshotV2Payload {
        HabitRecordSnapshotV2Payload(
            date: date,
            count: count,
            status: statusRaw,
            created_at: createdAt
        )
    }
}
