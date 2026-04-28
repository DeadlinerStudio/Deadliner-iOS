//
//  ToolCallExecutor.swift
//  Deadliner
//
//  Created by Codex on 2026/3/19.
//

import Foundation

actor ToolCallExecutor {
    static let shared = ToolCallExecutor()

    private init() {}

    struct ToolExecutionResult {
        let normalizedToolName: String
        let resultJson: String
        let displayMessage: String?
    }

    private struct TaskCandidate {
        let ddl: DDLItem
        let due: Date?
        let updatedAt: Date?
        let rankDate: Date?
    }

    nonisolated func normalizeToolName(_ toolName: String) -> String {
        ToolAdapterRuleBook.shared
            .canonicalName(for: toolName)
            ?? toolName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func supports(_ toolName: String) -> Bool {
        ToolAdapterRuleBook.shared.rule(for: toolName) != nil
    }

    func execute(toolName: String, argsJson: String) async -> ToolExecutionResult {
        guard let rule = ToolAdapterRuleBook.shared.rule(for: toolName) else {
            let normalized = normalizeToolName(toolName)
            return makeFailureResult(tool: normalized, code: "UNSUPPORTED_TOOL", message: "暂不支持工具 \(normalized)")
        }

        let normalized = rule.name
        do {
            switch rule.handler {
            case "read_tasks":
                let args = decodeArgs(ReadTasksArgs.self, from: argsJson)
                    ?? ReadTasksArgs(timeRangeDays: 7, status: "OPEN", keywords: nil, limit: 20, sort: "DUE_ASC")
                let ddlTasks = try await TaskRepository.shared.getDDLsByType(.task)
                print("[ToolCallExecutor] read_tasks fetched \(ddlTasks.count) task items from repository")
                let payload = makeReadTasksPayload(from: ddlTasks, args: args)
                let resultJson = try encodeResult(payload)
                let message = "已读取任务 \(payload.summary.count) 条（逾期 \(payload.summary.overdue)，24h 内 \(payload.summary.dueSoon24h)）"
                return ToolExecutionResult(normalizedToolName: normalized, resultJson: resultJson, displayMessage: message)

            case "create_task":
                guard let args = decodeArgs(CreateTaskArgs.self, from: argsJson) else {
                    return makeFailureResult(tool: normalized, code: "INVALID_ARGS", message: "create_task 缺少必要参数")
                }
                let payload = CreateTaskResultPayload(
                    ok: true,
                    task: TaskWriteBackItem(id: nil, name: args.name, due: args.dueTime ?? "", note: args.note ?? ""),
                    pendingUserConfirmation: true
                )
                let resultJson = try encodeResult(payload)
                return ToolExecutionResult(
                    normalizedToolName: normalized,
                    resultJson: resultJson,
                    displayMessage: "已生成任务草案，请确认添加：\(args.name)"
                )

            case "update_deadline":
                guard let args = decodeArgs(UpdateDeadlineArgs.self, from: argsJson),
                      let taskId = Int64(args.taskId) else {
                    return makeFailureResult(tool: normalized, code: "INVALID_ARGS", message: "update_deadline 需要 taskId 与 newDueTime")
                }
                guard var task = try await TaskRepository.shared.getDDLById(taskId) else {
                    return makeFailureResult(tool: normalized, code: "TASK_NOT_FOUND", message: "未找到任务 \(taskId)")
                }
                guard let parsed = DeadlineDateParser.parseAIGeneratedDate(args.newDueTime)
                    ?? DeadlineDateParser.safeParseOptional(args.newDueTime) else {
                    return makeFailureResult(tool: normalized, code: "INVALID_DATE", message: "newDueTime 无法解析")
                }

                task.endTime = parsed.toLocalISOString()
                try await TaskRepository.shared.updateDDL(task)

                let payload = UpdateDeadlineResultPayload(
                    ok: true,
                    task: TaskWriteBackItem(id: task.id, name: task.name, due: task.endTime, note: task.note)
                )
                let resultJson = try encodeResult(payload)
                return ToolExecutionResult(normalizedToolName: normalized, resultJson: resultJson, displayMessage: "已更新截止时间：\(task.name)")

            case "read_habits":
                let args = decodeArgs(ReadHabitsArgs.self, from: argsJson) ?? ReadHabitsArgs(keywords: nil)
                let allHabits = try await HabitRepository.shared.getAllHabits()
                let keywords = (args.keywords ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                let filtered = allHabits.filter { habit in
                    guard !keywords.isEmpty else { return true }
                    let hay = "\(habit.name) \(habit.description ?? "")".lowercased()
                    return keywords.allSatisfy { hay.contains($0) }
                }
                let payload = ReadHabitsResultPayload(
                    habits: filtered.map {
                        HabitDigestItem(
                            id: $0.id,
                            name: $0.name,
                            period: $0.period.rawValue,
                            timesPerPeriod: $0.timesPerPeriod,
                            goalType: $0.goalType.rawValue,
                            totalTarget: $0.totalTarget,
                            status: $0.status.rawValue
                        )
                    },
                    summary: HabitSummary(
                        count: filtered.count,
                        active: filtered.filter { $0.status == .active }.count,
                        archived: filtered.filter { $0.status == .archived }.count
                    )
                )
                let resultJson = try encodeResult(payload)
                return ToolExecutionResult(
                    normalizedToolName: normalized,
                    resultJson: resultJson,
                    displayMessage: "已读取习惯 \(payload.summary.count) 条"
                )

            case "create_habit":
                guard let args = decodeArgs(CreateHabitArgs.self, from: argsJson) else {
                    return makeFailureResult(tool: normalized, code: "INVALID_ARGS", message: "create_habit 缺少必要参数")
                }

                let period = HabitPeriod(rawValue: args.period.uppercased()) ?? .daily
                let normalizedGoalType = normalizeHabitGoalType(args.goalType)
                let goalType = HabitGoalType(rawValue: normalizedGoalType) ?? .perPeriod

                let payload = CreateHabitResultPayload(
                    ok: true,
                    habit: HabitWriteBackItem(
                        id: nil,
                        name: args.name,
                        period: period.rawValue,
                        timesPerPeriod: max(1, args.timesPerPeriod),
                        goalType: goalType.rawValue,
                        totalTarget: goalType == .total ? args.totalTarget : nil
                    ),
                    pendingUserConfirmation: true
                )
                let resultJson = try encodeResult(payload)
                return ToolExecutionResult(
                    normalizedToolName: normalized,
                    resultJson: resultJson,
                    displayMessage: "已生成习惯草案，请确认添加：\(args.name)"
                )

            default:
                return makeFailureResult(
                    tool: normalized,
                    code: "UNIMPLEMENTED_HANDLER",
                    message: "工具规则已声明但未实现 handler=\(rule.handler)"
                )
            }
        } catch {
            return makeFailureResult(tool: normalized, code: "TOOL_EXECUTION_FAILED", message: error.localizedDescription)
        }
    }

    private func makeReadTasksPayload(from items: [DDLItem], args: ReadTasksArgs) -> ReadTasksResultPayload {
        let now = Date()
        let days = args.timeRangeDays ?? 7
        let start = now.addingTimeInterval(TimeInterval(-days) * 86400)
        let end = now.addingTimeInterval(TimeInterval(days) * 86400)

        let keywords = (args.keywords ?? []).map { $0.lowercased() }
        let wantStatus = (args.status ?? "OPEN").uppercased()

        var filtered: [TaskCandidate] = []

        for t in items {
            if t.isArchived { continue }
            if wantStatus == "OPEN" && t.isCompleted { continue }
            if wantStatus == "DONE" && !t.isCompleted { continue }

            if !keywords.isEmpty {
                let hay = "\(t.name) \(t.note)".lowercased()
                let matched = keywords.allSatisfy { hay.contains($0) }
                if !matched { continue }
            }

            let due = parseLocalDate(t.endTime)
            let updatedAt = parseLocalDate(t.timestamp) ?? parseLocalDate(t.startTime)

            let matchesTimeWindow: Bool
            if let due {
                matchesTimeWindow = due >= start && due <= end
            } else if let updatedAt {
                matchesTimeWindow = updatedAt >= start
            } else {
                matchesTimeWindow = keywords.isEmpty
            }

            if !matchesTimeWindow { continue }

            filtered.append(TaskCandidate(
                ddl: t,
                due: due,
                updatedAt: updatedAt,
                rankDate: due ?? updatedAt
            ))
        }

        let sort = (args.sort ?? "DUE_ASC").uppercased()
        if sort == "UPDATED_DESC" {
            filtered.sort { lhs, rhs in
                let left = lhs.updatedAt ?? lhs.due ?? .distantPast
                let right = rhs.updatedAt ?? rhs.due ?? .distantPast
                if left != right { return left > right }
                return lhs.ddl.id > rhs.ddl.id
            }
        } else {
            filtered.sort { lhs, rhs in
                let left = lhs.due ?? lhs.updatedAt ?? .distantFuture
                let right = rhs.due ?? rhs.updatedAt ?? .distantFuture
                if left != right { return left < right }
                return lhs.ddl.id < rhs.ddl.id
            }
        }

        if filtered.isEmpty && keywords.isEmpty {
            filtered = items.compactMap { item in
                if item.isArchived { return nil }
                if wantStatus == "OPEN" && item.isCompleted { return nil }
                if wantStatus == "DONE" && !item.isCompleted { return nil }

                let due = parseLocalDate(item.endTime)
                let updatedAt = parseLocalDate(item.timestamp) ?? parseLocalDate(item.startTime)
                return TaskCandidate(
                    ddl: item,
                    due: due,
                    updatedAt: updatedAt,
                    rankDate: due ?? updatedAt
                )
            }

            filtered.sort { lhs, rhs in
                let left = lhs.rankDate ?? .distantFuture
                let right = rhs.rankDate ?? .distantFuture
                if left != right { return left < right }
                return lhs.ddl.id < rhs.ddl.id
            }
        }

        let limit = args.limit ?? 20
        if filtered.count > limit {
            filtered = Array(filtered.prefix(limit))
        }

        var overdue = 0
        var dueSoon24h = 0
        for candidate in filtered {
            guard let due = candidate.due else { continue }
            if due < now { overdue += 1 }
            if due >= now && due <= now.addingTimeInterval(86400) { dueSoon24h += 1 }
        }

        let digest: [TaskDigestItem] = filtered.map { candidate in
            let ddl = candidate.ddl
            return TaskDigestItem(
                id: ddl.id,
                name: ddl.name,
                due: candidate.due?.toLocalISOString() ?? "",
                status: ddl.isCompleted ? "DONE" : "OPEN",
                notePreview: String(ddl.note.prefix(40))
            )
        }

        return ReadTasksResultPayload(
            tasks: digest,
            summary: TaskSummary(count: digest.count, overdue: overdue, dueSoon24h: dueSoon24h)
        )
    }

    private func parseLocalDate(_ value: String) -> Date? {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return DeadlineDateParser.safeParseOptional(value) ?? DeadlineDateParser.parseAIGeneratedDate(value)
    }

    private func normalizeHabitGoalType(_ raw: String) -> String {
        switch raw.uppercased() {
        case "COUNT", "PERIOD", "PER_PERIOD":
            return HabitGoalType.perPeriod.rawValue
        case "TOTAL":
            return HabitGoalType.total.rawValue
        default:
            return HabitGoalType.perPeriod.rawValue
        }
    }

    private func decodeArgs<T: Decodable>(_ type: T.Type, from argsJson: String) -> T? {
        guard let data = argsJson.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encodeResult<T: Encodable>(_ payload: T) throws -> String {
        let data = try JSONEncoder().encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw AIError.parsingFailed
        }
        return json
    }

    private func makeFailureResult(tool: String, code: String, message: String) -> ToolExecutionResult {
        let payload = ToolFailurePayload(ok: false, errorCode: code, message: message)
        let json = (try? encodeResult(payload)) ?? "{\"ok\":false,\"errorCode\":\"\(code)\",\"message\":\"\(message)\"}"
        return ToolExecutionResult(
            normalizedToolName: tool,
            resultJson: json,
            displayMessage: "工具执行失败（\(tool)）"
        )
    }
}

private struct ToolFailurePayload: Codable {
    let ok: Bool
    let errorCode: String
    let message: String
}

private struct TaskWriteBackItem: Codable {
    let id: Int64?
    let name: String
    let due: String
    let note: String
}

private struct CreateTaskResultPayload: Codable {
    let ok: Bool
    let task: TaskWriteBackItem
    let pendingUserConfirmation: Bool
}

private struct UpdateDeadlineResultPayload: Codable {
    let ok: Bool
    let task: TaskWriteBackItem
}

private struct ReadHabitsResultPayload: Codable {
    let habits: [HabitDigestItem]
    let summary: HabitSummary
}

private struct HabitDigestItem: Codable {
    let id: Int64
    let name: String
    let period: String
    let timesPerPeriod: Int
    let goalType: String
    let totalTarget: Int?
    let status: String
}

private struct HabitSummary: Codable {
    let count: Int
    let active: Int
    let archived: Int
}

private struct HabitWriteBackItem: Codable {
    let id: Int64?
    let name: String
    let period: String
    let timesPerPeriod: Int
    let goalType: String
    let totalTarget: Int?
}

private struct CreateHabitResultPayload: Codable {
    let ok: Bool
    let habit: HabitWriteBackItem
    let pendingUserConfirmation: Bool
}

private struct ToolAdapterRule: Codable {
    let name: String
    let aliases: [String]
    let handler: String
}

private struct ToolAdapterRuleFile: Codable {
    let version: Int
    let rules: [ToolAdapterRule]
}

private final class ToolAdapterRuleBook {
    static let shared = ToolAdapterRuleBook()

    private let rules: [ToolAdapterRule]
    private let aliasToName: [String: String]

    private init() {
        let resolved = Self.loadRules()
        rules = resolved

        var map: [String: String] = [:]
        for rule in resolved {
            map[rule.name] = rule.name
            for alias in rule.aliases {
                map[alias] = rule.name
            }
        }
        aliasToName = map
    }

    func canonicalName(for input: String) -> String? {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return aliasToName[key]
    }

    func rule(for input: String) -> ToolAdapterRule? {
        guard let name = canonicalName(for: input) else { return nil }
        return rules.first { $0.name == name }
    }

    private static func loadRules() -> [ToolAdapterRule] {
        do {
            let url = try ensureRulesFile()
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(ToolAdapterRuleFile.self, from: data)
            guard !decoded.rules.isEmpty else { return defaultRules }
            return decoded.rules
        } catch {
            return defaultRules
        }
    }

    private static func ensureRulesFile() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DeadlinerAI", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileURL = dir.appendingPathComponent("tool_adapter_rules.json", isDirectory: false)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try JSONEncoder().encode(ToolAdapterRuleFile(version: 1, rules: defaultRules))
            try data.write(to: fileURL, options: .atomic)
        }
        return fileURL
    }

    private static let defaultRules: [ToolAdapterRule] = [
        .init(name: "read_tasks", aliases: ["readTasks", "ReadTaskContext"], handler: "read_tasks"),
        .init(name: "create_task", aliases: ["createTask"], handler: "create_task"),
        .init(name: "update_deadline", aliases: ["updateDeadline"], handler: "update_deadline"),
        .init(name: "read_habits", aliases: ["readHabits", "ReadHabitContext"], handler: "read_habits"),
        .init(name: "create_habit", aliases: ["createHabit"], handler: "create_habit")
    ]
}
