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
    let retrievedTasks: [AITask]?
    let retrievedHabits: [AIHabit]?
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

public struct ReadHabitsArgs: Codable {
    let keywords: [String]?
}

public struct CreateTaskArgs: Codable {
    let name: String
    let dueTime: String?
    let note: String?
    let tasks: [CreateTaskItemArgs]?

    enum CodingKeys: String, CodingKey {
        case name
        case dueTime
        case due_time
        case note
        case tasks
    }

    public init(name: String, dueTime: String?, note: String?, tasks: [CreateTaskItemArgs]? = nil) {
        self.name = name
        self.dueTime = dueTime
        self.note = note
        self.tasks = tasks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTasks = try container.decodeIfPresent([CreateTaskItemArgs].self, forKey: .tasks)
        tasks = decodedTasks

        if let first = decodedTasks?.first {
            name = first.name
            dueTime = first.dueTime
            note = first.note
        } else {
            name = try container.decode(String.self, forKey: .name)
            dueTime = try container.decodeIfPresent(String.self, forKey: .dueTime)
                ?? container.decodeIfPresent(String.self, forKey: .due_time)
            note = try container.decodeIfPresent(String.self, forKey: .note)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(dueTime, forKey: .dueTime)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(tasks, forKey: .tasks)
    }

    var normalizedItems: [CreateTaskItemArgs] {
        let fromArray = (tasks ?? []).filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !fromArray.isEmpty { return fromArray }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [CreateTaskItemArgs(name: trimmed, dueTime: dueTime, note: note)]
    }
}

public struct CreateTaskItemArgs: Codable {
    let name: String
    let dueTime: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case name
        case dueTime
        case due_time
        case note
    }

    public init(name: String, dueTime: String?, note: String?) {
        self.name = name
        self.dueTime = dueTime
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        dueTime = try container.decodeIfPresent(String.self, forKey: .dueTime)
            ?? container.decodeIfPresent(String.self, forKey: .due_time)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(dueTime, forKey: .dueTime)
        try container.encodeIfPresent(note, forKey: .note)
    }
}

public struct UpdateDeadlineArgs: Codable {
    let taskId: String
    let newDueTime: String

    enum CodingKeys: String, CodingKey {
        case taskId
        case task_id
        case newDueTime
        case new_due_time
    }

    public init(taskId: String, newDueTime: String) {
        self.taskId = taskId
        self.newDueTime = newDueTime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(String.self, forKey: .taskId)
            ?? container.decodeIfPresent(String.self, forKey: .task_id) {
            taskId = id
        } else if let id = try container.decodeIfPresent(Int64.self, forKey: .taskId)
            ?? container.decodeIfPresent(Int64.self, forKey: .task_id) {
            taskId = String(id)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .taskId,
                in: container,
                debugDescription: "taskId is required"
            )
        }
        newDueTime = try container.decodeIfPresent(String.self, forKey: .newDueTime)
            ?? container.decode(String.self, forKey: .new_due_time)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(taskId, forKey: .taskId)
        try container.encode(newDueTime, forKey: .newDueTime)
    }
}

public struct CreateHabitArgs: Codable {
    let name: String
    let period: String
    let timesPerPeriod: Int
    let goalType: String
    let totalTarget: Int?
    let habits: [CreateHabitItemArgs]?

    enum CodingKeys: String, CodingKey {
        case name
        case period
        case timesPerPeriod
        case times_per_period
        case goalType
        case goal_type
        case totalTarget
        case total_target
        case habits
    }

    public init(name: String, period: String, timesPerPeriod: Int, goalType: String, totalTarget: Int?, habits: [CreateHabitItemArgs]? = nil) {
        self.name = name
        self.period = period
        self.timesPerPeriod = timesPerPeriod
        self.goalType = goalType
        self.totalTarget = totalTarget
        self.habits = habits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedHabits = try container.decodeIfPresent([CreateHabitItemArgs].self, forKey: .habits)
        habits = decodedHabits
        if let first = decodedHabits?.first {
            name = first.name
            period = first.period
            timesPerPeriod = first.timesPerPeriod
            goalType = first.goalType
            totalTarget = first.totalTarget
        } else {
            name = try container.decode(String.self, forKey: .name)
            period = try container.decode(String.self, forKey: .period)
            timesPerPeriod = try container.decodeIfPresent(Int.self, forKey: .timesPerPeriod)
                ?? container.decode(Int.self, forKey: .times_per_period)
            goalType = try container.decodeIfPresent(String.self, forKey: .goalType)
                ?? container.decode(String.self, forKey: .goal_type)
            totalTarget = try container.decodeIfPresent(Int.self, forKey: .totalTarget)
                ?? container.decodeIfPresent(Int.self, forKey: .total_target)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(period, forKey: .period)
        try container.encode(timesPerPeriod, forKey: .timesPerPeriod)
        try container.encode(goalType, forKey: .goalType)
        try container.encodeIfPresent(totalTarget, forKey: .totalTarget)
        try container.encodeIfPresent(habits, forKey: .habits)
    }

    var normalizedItems: [CreateHabitItemArgs] {
        let fromArray = (habits ?? []).filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !fromArray.isEmpty { return fromArray }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [
            CreateHabitItemArgs(
                name: trimmed,
                period: period,
                timesPerPeriod: timesPerPeriod,
                goalType: goalType,
                totalTarget: totalTarget
            )
        ]
    }
}

public struct CreateHabitItemArgs: Codable {
    let name: String
    let period: String
    let timesPerPeriod: Int
    let goalType: String
    let totalTarget: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case period
        case timesPerPeriod
        case times_per_period
        case goalType
        case goal_type
        case totalTarget
        case total_target
    }

    public init(name: String, period: String, timesPerPeriod: Int, goalType: String, totalTarget: Int?) {
        self.name = name
        self.period = period
        self.timesPerPeriod = timesPerPeriod
        self.goalType = goalType
        self.totalTarget = totalTarget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        period = try container.decode(String.self, forKey: .period)
        timesPerPeriod = try container.decodeIfPresent(Int.self, forKey: .timesPerPeriod)
            ?? container.decode(Int.self, forKey: .times_per_period)
        goalType = try container.decodeIfPresent(String.self, forKey: .goalType)
            ?? container.decode(String.self, forKey: .goal_type)
        totalTarget = try container.decodeIfPresent(Int.self, forKey: .totalTarget)
            ?? container.decodeIfPresent(Int.self, forKey: .total_target)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(period, forKey: .period)
        try container.encode(timesPerPeriod, forKey: .timesPerPeriod)
        try container.encode(goalType, forKey: .goalType)
        try container.encodeIfPresent(totalTarget, forKey: .totalTarget)
    }
}

// MARK: - Tool Request / Result (App-side)

public struct AIToolRequest: Identifiable, Codable {
    public let id: String
    public let tool: String
    public let argsJson: String
    public let reason: String?
    public let executionMode: String?

    public init(
        id: String = UUID().uuidString,
        tool: String,
        argsJson: String,
        reason: String? = nil,
        executionMode: String? = nil
    ) {
        self.id = id
        self.tool = tool
        self.argsJson = argsJson
        self.reason = reason
        self.executionMode = executionMode
    }

    public init(
        id: String = UUID().uuidString,
        tool: String,
        args: ReadTasksArgs,
        reason: String? = nil,
        executionMode: String? = nil
    ) {
        self.init(
            id: id,
            tool: tool,
            argsJson: Self.encodeJSON(args) ?? "{}",
            reason: reason,
            executionMode: executionMode
        )
    }

    var args: ReadTasksArgs {
        readTasksArgs ?? ReadTasksArgs(timeRangeDays: 7, status: "OPEN", keywords: nil, limit: 20, sort: "DUE_ASC")
    }

    var readTasksArgs: ReadTasksArgs? { Self.decodeJSON(ReadTasksArgs.self, from: argsJson) }
    var readHabitsArgs: ReadHabitsArgs? { Self.decodeJSON(ReadHabitsArgs.self, from: argsJson) }
    var createTaskArgs: CreateTaskArgs? { Self.decodeJSON(CreateTaskArgs.self, from: argsJson) }
    var createTaskItems: [CreateTaskItemArgs] { createTaskArgs?.normalizedItems ?? [] }
    var updateDeadlineArgs: UpdateDeadlineArgs? { Self.decodeJSON(UpdateDeadlineArgs.self, from: argsJson) }
    var createHabitArgs: CreateHabitArgs? { Self.decodeJSON(CreateHabitArgs.self, from: argsJson) }
    var createHabitItems: [CreateHabitItemArgs] { createHabitArgs?.normalizedItems ?? [] }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public struct AIToolResult: Identifiable, Codable {
    public let id: String
    public let tool: String
    public let requestArgsJson: String
    public let resultJson: String
    public let displayMessage: String?
    public let generatedAt: Date

    public init(
        id: String = UUID().uuidString,
        tool: String,
        requestArgsJson: String,
        resultJson: String,
        displayMessage: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.tool = tool
        self.requestArgsJson = requestArgsJson
        self.resultJson = resultJson
        self.displayMessage = displayMessage
        self.generatedAt = generatedAt
    }

    var readTasksPayload: ReadTasksResultPayload? {
        guard let data = resultJson.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReadTasksResultPayload.self, from: data)
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
