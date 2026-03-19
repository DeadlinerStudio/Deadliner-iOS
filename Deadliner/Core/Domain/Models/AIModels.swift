//
//  AIModels.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/21.
//

import Foundation

// MARK: - AI 提取结果模型
public struct AITask: Codable {
    let name: String
    let dueTime: String?
    let note: String?
}

// TODO: Habit的完整内部数据结构待实现，这里仅作为从AI解析的DTO (Data Transfer Object)
public struct AIHabit: Codable {
    let name: String
    let period: String
    let timesPerPeriod: Int
    let goalType: String
    let totalTarget: Int?
}

public struct MixedResult: Codable {
    let primaryIntent: String?
    let tasks: [AITask]?
    let habits: [AIHabit]?
    let newMemories: [String]? // 记忆提取
    let chatResponse: String?  // AI 的暖心回复
    let sessionSummary: String? // 会话摘要（短期）
    let userProfile: String? // 长期画像（可选更新）
    let toolCalls: [AIToolCall]?
}

// MARK: - API 请求/响应模型 (DeepSeek/OpenAI 兼容格式)
struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

struct ChatResponse: Codable {
    struct Choice: Codable {
        let message: ChatMessage
    }
    let choices: [Choice]
}

// MARK: - 错误定义
enum AIError: LocalizedError {
    case missingAPIKey
    case emptyResponse
    case parsingFailed
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "请先在设置中填写 DeepSeek API Key"
        case .emptyResponse: return "AI 返回内容为空"
        case .parsingFailed: return "AI 数据解析失败"
        case .networkError(let err): return "网络请求失败: \(err.localizedDescription)"
        }
    }
}

// MARK: - Tool Calls (MCP-like, local tools)

public struct AIToolCall: Codable {
    let tool: String
    let args: ReadTasksArgs
    let reason: String?
}

// readTasks 的参数（受限查询）
public struct ReadTasksArgs: Codable {
    let timeRangeDays: Int?     // default 7
    let status: String?         // "OPEN" | "DONE" | "ALL"
    let keywords: [String]?     // <=3
    let limit: Int?             // default 20, max 50
    let sort: String?           // "DUE_ASC" | "UPDATED_DESC"
}

// MARK: - Tool Request / Result (App-side)

public struct AIToolRequest: Identifiable, Codable {
    public let id: String
    public let tool: String              // "readTasks"
    public let args: ReadTasksArgs       // 当前只支持 readTasks
    public let reason: String?

    public init(id: String = UUID().uuidString, tool: String, args: ReadTasksArgs, reason: String? = nil) {
        self.id = id
        self.tool = tool
        self.args = args
        self.reason = reason
    }
}

public struct AIToolResult: Identifiable, Codable {
    public let id: String
    public let tool: String              // "readTasks"
    public let appliedArgs: ReadTasksArgs
    public let payload: ReadTasksResultPayload
    public let generatedAt: Date

    public init(
        id: String = UUID().uuidString,
        tool: String,
        appliedArgs: ReadTasksArgs,
        payload: ReadTasksResultPayload,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.tool = tool
        self.appliedArgs = appliedArgs
        self.payload = payload
        self.generatedAt = generatedAt
    }
}

// readTasks 返回给 AI 的精简 DTO
public struct ReadTasksResultPayload: Codable {
    let tasks: [TaskDigestItem]
    let summary: TaskSummary
}

public struct TaskDigestItem: Codable, Identifiable {
    public let id: Int64
    public let name: String
    public let due: String          // "yyyy-MM-dd HH:mm" or ""
    public let status: String       // "OPEN" | "DONE"
    public let notePreview: String  // <= 40 chars

    public init(id: Int64, name: String, due: String, status: String, notePreview: String) {
        self.id = id
        self.name = name
        self.due = due
        self.status = status
        self.notePreview = notePreview
    }
}

public struct TaskSummary: Codable {
    let count: Int
    let overdue: Int
    let dueSoon24h: Int
}

// MARK: - Monthly Analysis

public struct MonthlyAnalysisResult: Codable {
    public let month: String // e.g. "2024-02"
    public let summary: String
    public let keywords: [String]
    public let generatedAt: Date?
    
    public init(month: String, summary: String, keywords: [String], generatedAt: Date = Date()) {
        self.month = month
        self.summary = summary
        self.keywords = keywords
        self.generatedAt = generatedAt
    }
}
