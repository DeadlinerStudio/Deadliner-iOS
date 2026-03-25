//
//  SyncSnapshotV2.swift
//  Deadliner
//

import Foundation

struct SnapshotV2InnerTodo: Codable, Sendable {
    let id: String
    let content: String
    let is_completed: Int
    let sort_order: Int
    let created_at: String?
    let updated_at: String?
}

struct SnapshotV2Doc: Codable, Sendable {
    let id: Int64
    let name: String
    let start_time: String
    let end_time: String
    let state: String
    let complete_time: String
    let note: String
    let is_stared: Int
    let type: String
    let habit_count: Int
    let habit_total_count: Int
    let calendar_event: Int64
    let timestamp: String
    let sub_tasks: [SnapshotV2InnerTodo]
}

struct SnapshotV2Item: Codable, Sendable {
    let uid: String
    let ver: SnapshotVer
    let deleted: Bool
    let doc: SnapshotV2Doc?
}

struct SnapshotV2Version: Codable, Sendable {
    let ts: String
    let dev: String
}

struct SnapshotV2Root: Codable, Sendable {
    let version: SnapshotV2Version
    var items: [SnapshotV2Item]
}
