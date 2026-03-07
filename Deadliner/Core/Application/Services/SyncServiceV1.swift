//
//  SyncServiceV1.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import Foundation

actor SyncServiceV1: SyncService {
    private let db: DatabaseHelper
    private let web: WebDAVClient
    private let snapshotPath = "Deadliner/snapshot-v1.json"

    init(db: DatabaseHelper, web: WebDAVClient) {
        self.db = db
        self.web = web
    }

    func syncOnce() async -> SyncResult {
        do {
            return try await syncSnapshotOnce()
        } catch {
            return .init(success: false, hasLocalChanges: false)
        }
    }

    // MARK: - Snapshot Build

    private func buildLocalSnapshot() async throws -> SnapshotRoot {
        let items = try await db.getAllDDLsIncludingDeletedForSync()

        let snapItems: [SnapshotItem] = items.compactMap { e in
            guard let uid = e.uid, !uid.isEmpty else { return nil }

            let ver = SnapshotVer(ts: e.verTs, ctr: e.verCtr, dev: e.verDev)
            if e.isTombstoned {
                return SnapshotItem(uid: uid, ver: ver, deleted: true, doc: nil)
            } else {
                let doc = SnapshotDoc(
                    id: e.legacyId,
                    name: e.name,
                    start_time: e.startTime,
                    end_time: e.endTime,
                    is_completed: e.isCompleted ? 1 : 0,
                    complete_time: e.completeTime,
                    note: e.note,
                    is_archived: e.isArchived ? 1 : 0,
                    is_stared: e.isStared ? 1 : 0,
                    type: e.typeRaw,
                    habit_count: e.habitCount,
                    habit_total_count: e.habitTotalCount,
                    calendar_event: e.calendarEventId,
                    timestamp: e.timestamp
                )
                return SnapshotItem(uid: uid, ver: ver, deleted: false, doc: doc)
            }
        }

        let dev = try await db.getDeviceId()
        let now = Date().toLocalISOString()
        return SnapshotRoot(version: .init(ts: now, dev: dev), items: snapItems)
    }

    // MARK: - Merge

    private func isVerNewer(_ a: SnapshotVer, _ b: SnapshotVer) -> Bool {
        if a.ts != b.ts { return a.ts > b.ts }
        if a.ctr != b.ctr { return a.ctr > b.ctr }
        if a.dev != b.dev { return a.dev > b.dev }
        return false
    }

    private func newer(_ a: SnapshotItem, _ b: SnapshotItem) -> Bool {
        isVerNewer(a.ver, b.ver)
    }

    private func merge(local: SnapshotRoot, remote: SnapshotRoot) -> SnapshotRoot {
        var map: [String: SnapshotItem] = [:]
        for i in local.items { map[i.uid] = i }
        for r in remote.items {
            if let l = map[r.uid] {
                if newer(r, l) { map[r.uid] = r }
            } else {
                map[r.uid] = r
            }
        }
        return SnapshotRoot(version: local.version, items: Array(map.values))
    }

    // MARK: - Apply back to local

    private func applySnapshotToLocal(_ merged: SnapshotRoot) async throws -> Bool {
        var changed = false

        for item in merged.items {
            let uid = item.uid
            let mergedVer = item.ver

            let local = try await db.findDDLByUID(uid)
            if let local {
                let localVer = SnapshotVer(ts: local.verTs, ctr: local.verCtr, dev: local.verDev)
                // 🟢 核心优化：只有远程/合并后的版本确实更新时，才应用到本地。
                // 之前是 !isVerNewer(localVer, mergedVer) 就会应用，导致版本相等时也在冗余覆盖。
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
                    changed = true
                } else {
                    try await db.insertTombstoneByUID(
                        uid: uid,
                        verTs: mergedVer.ts,
                        verCtr: mergedVer.ctr,
                        verDev: mergedVer.dev
                    )
                    changed = true
                }
            } else if let doc = item.doc {
                if let local {
                    try await db.overwriteDDLFromSnapshotEntity(
                        entity: local,
                        doc: doc,
                        verTs: mergedVer.ts,
                        verCtr: mergedVer.ctr,
                        verDev: mergedVer.dev
                    )
                } else {
                    try await db.insertDDLFromSnapshot(
                        uid: uid,
                        doc: doc,
                        verTs: mergedVer.ts,
                        verCtr: mergedVer.ctr,
                        verDev: mergedVer.dev
                    )
                }
                changed = true
            }
        }

        return changed
    }

    // MARK: - One-shot sync

    private func syncSnapshotOnce() async throws -> SyncResult {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let localSnap = try await buildLocalSnapshot()

        let head = try await web.head(path: snapshotPath)
        let code = head.code

        if [404, 409, 410].contains(code) {
            _ = await web.ensureDir("Deadliner")
            let bytes = try encoder.encode(localSnap)
            _ = try await web.putBytes(path: snapshotPath, bytes: bytes, ifMatch: nil, ifNoneMatchStar: true)
            return .init(success: true, hasLocalChanges: false)
        }

        let remoteResp = try await web.getBytes(path: snapshotPath)
        var remoteSnap = try decoder.decode(SnapshotRoot.self, from: remoteResp.bytes)

        if remoteResp.bytes.count > 1000, remoteSnap.items.isEmpty {
            return .init(success: false, hasLocalChanges: false)
        }

        let merged = merge(local: localSnap, remote: remoteSnap)
        let mergedBytes = try encoder.encode(merged)

        do {
            _ = try await web.putBytes(
                path: snapshotPath,
                bytes: mergedBytes,
                ifMatch: remoteResp.etag,
                ifNoneMatchStar: false
            )
        } catch is PreconditionFailedError {
            let remoteResp2 = try await web.getBytes(path: snapshotPath)
            let remoteSnap2 = try decoder.decode(SnapshotRoot.self, from: remoteResp2.bytes)

            let merged2 = merge(local: localSnap, remote: remoteSnap2)
            _ = try await applySnapshotToLocal(merged2)

            return .init(success: true, hasLocalChanges: true)
        }

        let hasChanges = try await applySnapshotToLocal(merged)
        return .init(success: true, hasLocalChanges: hasChanges)
    }
}
