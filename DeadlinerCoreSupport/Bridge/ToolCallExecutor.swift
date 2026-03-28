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

    private struct TaskCandidate {
        let ddl: DDLItem
        let due: Date?
        let updatedAt: Date?
        let rankDate: Date?
    }

    nonisolated func normalizeToolName(_ toolName: String) -> String {
        switch toolName {
        case "read_tasks", "readTasks", "ReadTaskContext":
            return "readTasks"
        default:
            return toolName
        }
    }

    nonisolated func supports(_ toolName: String) -> Bool {
        normalizeToolName(toolName) == "readTasks"
    }

    func execute(toolName: String, args: ReadTasksArgs) async throws -> ReadTasksResultPayload {
        let normalized = normalizeToolName(toolName)
        switch normalized {
        case "readTasks":
            let ddlTasks = try await TaskRepository.shared.getDDLsByType(.task)
            print("[ToolCallExecutor] readTasks fetched \(ddlTasks.count) task items from repository")
            let payload = makeReadTasksPayload(from: ddlTasks, args: args)
            print("[ToolCallExecutor] readTasks returning \(payload.tasks.count) tasks. summary.count=\(payload.summary.count), overdue=\(payload.summary.overdue), dueSoon24h=\(payload.summary.dueSoon24h)")
            return payload
        default:
            throw AIError.parsingFailed
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
}
