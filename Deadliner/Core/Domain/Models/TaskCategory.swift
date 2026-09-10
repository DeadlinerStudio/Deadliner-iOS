//
//  TaskCategory.swift
//  Deadliner
//
//  Created by Codex on 2026/7/17.
//

import Foundation

struct TaskCategory: Identifiable, Equatable, Hashable, Sendable {
    let uid: String
    var name: String
    var iconKey: String
    var colorHex: String
    var isPreset: Bool
    var sortOrder: Int
    var createdAt: String
    var updatedAt: String

    var id: String { uid }

    static func == (lhs: TaskCategory, rhs: TaskCategory) -> Bool {
        lhs.uid == rhs.uid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
}

extension TaskCategory {
    static let uncategorizedUID: String? = nil
}
