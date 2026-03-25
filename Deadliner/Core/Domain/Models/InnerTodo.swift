//
//  InnerTodo.swift
//  Deadliner
//

import Foundation

struct InnerTodo: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var content: String
    var isCompleted: Bool
    var sortOrder: Int
    var createdAt: String?
    var updatedAt: String?

    init(
        id: String = UUID().uuidString,
        content: String,
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.content = content
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
