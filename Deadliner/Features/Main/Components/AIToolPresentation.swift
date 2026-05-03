//
//  AIToolPresentation.swift
//  Deadliner
//

import Foundation

enum AIToolPresentation {
    static func collaborationMessage(for agentName: String, phase: String, fallbackMessage: String?) -> String {
        if let fallbackMessage, !fallbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallbackMessage
        }

        switch agentName {
        case "Supervisor":
            switch phase {
            case "routing":
                return "总控代理正在分析请求并分派子任务"
            case "memory":
                return "总控代理正在整理本轮记忆更新"
            default:
                return "总控代理正在协调整体流程"
            }
        case "TaskAgent":
            switch phase {
            case "routing":
                return "任务代理已接手，准备分析时间与待办"
            case "tool_wait":
                return "任务代理正在等待本地任务工具结果"
            default:
                return "任务代理正在整理待办与时间信息"
            }
        case "HabitAgent":
            switch phase {
            case "routing":
                return "习惯代理已接手，准备分析周期性行为"
            case "tool_wait":
                return "习惯代理正在等待工具结果"
            default:
                return "习惯代理正在分析周期性行为"
            }
        case "ChatAgent":
            switch phase {
            case "routing":
                return "聊天代理已接手，准备组织回复"
            case "memory":
                return "聊天代理正在整理回复相关记忆"
            default:
                return "聊天代理正在组织回复与记忆"
            }
        default:
            return "\(agentName) 正在\(phase)阶段协作处理中"
        }
    }

    static func toolCollaborationMessage(for toolName: String) -> String {
        switch toolName {
        case "read_tasks", "readTasks", "ReadTaskContext":
            return "任务代理请求读取本地任务列表"
        case "create_task", "createTask":
            return "任务代理请求创建新任务"
        case "update_deadline", "updateDeadline":
            return "任务代理请求更新任务截止时间"
        case "read_habits", "readHabits", "ReadHabitContext":
            return "习惯代理请求读取本地习惯列表"
        case "create_habit", "createHabit":
            return "习惯代理请求创建新习惯"
        default:
            return "\(toolName) 工具正在参与协作"
        }
    }

    static func toolRequestTitle(for tool: String) -> String {
        switch ToolCallExecutor.shared.normalizeToolName(tool) {
        case "read_tasks":
            return "需要读取任务列表"
        case "create_task":
            return "需要创建任务"
        case "update_deadline":
            return "需要调整任务截止时间"
        case "read_habits":
            return "需要读取习惯列表"
        case "create_habit":
            return "需要创建习惯"
        default:
            return "需要执行本地工具"
        }
    }

    static func toolRequestDefaultReason(for tool: String) -> String {
        switch ToolCallExecutor.shared.normalizeToolName(tool) {
        case "read_tasks":
            return "为了回答你的问题，我需要查看你近期的任务。"
        case "create_task":
            return "为了完成你的请求，我需要在本地创建一个新任务。"
        case "update_deadline":
            return "为了完成你的请求，我需要修改现有任务的截止时间。"
        case "read_habits":
            return "为了回答你的问题，我需要查看你当前的习惯设置。"
        case "create_habit":
            return "为了完成你的请求，我需要在本地创建一个新习惯。"
        default:
            return "为了继续回答，我需要执行一次本地工具调用。"
        }
    }

    static func toolRequestScopeSummary(_ req: AIToolRequest) -> String? {
        switch ToolCallExecutor.shared.normalizeToolName(req.tool) {
        case "read_tasks":
            guard let args = req.readTasksArgs else { return nil }
            let days = args.timeRangeDays ?? 7
            let status = args.status ?? "OPEN"
            let keywords = (args.keywords ?? []).joined(separator: "、")
            return "范围：未来 \(days) 天 · 状态：\(status)\(keywords.isEmpty ? "" : " · 关键词：\(keywords)")"
        case "create_task":
            let items = req.createTaskItems
            guard !items.isEmpty else { return nil }
            if items.count == 1 {
                let due = items[0].dueTime?.isEmpty == false ? items[0].dueTime! : "未指定"
                return "任务：\(items[0].name) · 截止：\(due)"
            }
            return "批量任务：共 \(items.count) 条"
        case "update_deadline":
            guard let args = req.updateDeadlineArgs else { return nil }
            return "任务ID：\(args.taskId) · 新截止：\(args.newDueTime)"
        case "read_habits":
            let keywords = (req.readHabitsArgs?.keywords ?? []).joined(separator: "、")
            return keywords.isEmpty ? "范围：全部习惯" : "关键词：\(keywords)"
        case "create_habit":
            let items = req.createHabitItems
            guard !items.isEmpty else { return nil }
            if items.count == 1 {
                return "习惯：\(items[0].name) · 周期：\(items[0].period) / \(items[0].timesPerPeriod) 次"
            }
            return "批量习惯：共 \(items.count) 条"
        default:
            return nil
        }
    }

    static func toolResultDisplayText(_ res: AIToolResult) -> String {
        if let custom = res.displayMessage, !custom.isEmpty {
            return custom
        }
        if let readTasks = res.readTasksPayload {
            let summary = readTasks.summary
            return "已读取任务：\(summary.count) 条（逾期 \(summary.overdue)，24h 内 \(summary.dueSoon24h)）"
        }
        return "工具执行完成：\(ToolCallExecutor.shared.normalizeToolName(res.tool))"
    }

    static func shouldAutoApproveToolRequest(_ req: AIToolRequest) -> Bool {
        let mode = (req.executionMode ?? "").uppercased()
        if mode == "AUTO" {
            return true
        }
        let normalized = ToolCallExecutor.shared.normalizeToolName(req.tool)
        return normalized == "create_task" || normalized == "create_habit"
    }
}
