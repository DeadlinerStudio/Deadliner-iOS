//
//  HabitSnapshotV2.swift
//  Deadliner
//

import Foundation

struct HabitSnapshotV2Payload: Codable, Sendable {
    let name: String
    let description: String?
    let color: Int?
    let icon_key: String?
    let period: String
    let times_per_period: Int
    let goal_type: String
    let total_target: Int?
    let created_at: String
    let updated_at: String
    let status: String
    let sort_order: Int
    let alarm_time: String?
}

struct HabitRecordSnapshotV2Payload: Codable, Sendable {
    let date: String
    let count: Int
    let status: String
    let created_at: String
}

struct HabitSnapshotV2Doc: Codable, Sendable {
    let ddl_uid: String
    let habit: HabitSnapshotV2Payload
    let records: [HabitRecordSnapshotV2Payload]
}

struct HabitSnapshotV2Item: Codable, Sendable {
    let uid: String
    let ver: SnapshotVer
    let deleted: Bool
    let doc: HabitSnapshotV2Doc?
}

struct HabitSnapshotV2Version: Codable, Sendable {
    let ts: String
    let dev: String
}

struct HabitSnapshotV2Root: Codable, Sendable {
    let version: HabitSnapshotV2Version
    var items: [HabitSnapshotV2Item]
}
