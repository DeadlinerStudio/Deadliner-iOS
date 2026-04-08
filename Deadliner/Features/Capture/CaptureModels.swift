//
//  CaptureModels.swift
//  Deadliner
//
//  Created by Codex on 2026/4/5.
//

import Foundation

struct CaptureInboxItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum CaptureConversionTarget: Identifiable {
    case task(CaptureInboxItem)
    case habit(CaptureInboxItem)

    var id: UUID {
        switch self {
        case .task(let item), .habit(let item):
            return item.id
        }
    }
}

enum CaptureConversionKind {
    case task
    case habit
}

struct CaptureConversionRequest: Identifiable {
    let id = UUID()
    let kind: CaptureConversionKind
    let item: CaptureInboxItem
    let consumedIDs: [UUID]
}
