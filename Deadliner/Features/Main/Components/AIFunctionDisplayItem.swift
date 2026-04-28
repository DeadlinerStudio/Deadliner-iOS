//
//  AIFunctionDisplayItem.swift
//  Deadliner
//

import Foundation

// MARK: - 对话流模型（稳定 id）
struct DisplayItem: Identifiable {
    enum Kind {
        case userQuery(String)
        case aiChat(String)
        case aiThinking(String)
        case aiTask(AITask)
        case aiHabit(AIHabit)
        case aiMemory(String)
        case aiToolRequest(AIToolRequest)
        case aiToolResult(AIToolResult)
    }

    let id: String
    let kind: Kind

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .userQuery:
            self.id = "user:\(UUID().uuidString)"
        case .aiChat:
            self.id = "chat:\(UUID().uuidString)"
        case .aiThinking:
            self.id = "thinking:\(UUID().uuidString)"
        case .aiTask:
            self.id = "task:\(UUID().uuidString)"
        case .aiHabit:
            self.id = "habit:\(UUID().uuidString)"
        case .aiMemory:
            self.id = "memory:\(UUID().uuidString)"
        case .aiToolRequest(let request):
            self.id = "tool-request:\(request.id)"
        case .aiToolResult(let result):
            self.id = "tool-result:\(result.id)"
        }
    }
}
