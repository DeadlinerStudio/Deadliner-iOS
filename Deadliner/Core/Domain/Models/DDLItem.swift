//
//  DDLItem.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import Foundation

struct DDLItem: Identifiable, Equatable, Sendable {
    // 与历史“legacyId”对齐，作为领域层主键
    let id: Int64

    var name: String
    var startTime: String
    var endTime: String

    var state: DDLState
    var completeTime: String

    var note: String
    var isStared: Bool
    var subTasks: [InnerTodo]

    var type: DeadlineType

    var habitCount: Int
    var habitTotalCount: Int

    // 与 ArkTS 的 calendar_event 对齐
    var calendarEvent: Int64

    // 业务时间戳（你当前是字符串）
    var timestamp: String

    var isCompleted: Bool {
        state.isCompletedLike
    }

    var isArchived: Bool {
        state.isArchivedLike
    }

    // 可选：给 UI/Repo 用的便捷字段
    var progress: Double {
        guard habitTotalCount > 0 else { return 0 }
        return min(max(Double(habitCount) / Double(habitTotalCount), 0), 1)
    }

    mutating func transition(to newState: DDLState) throws {
        try DDLStateMachine.validateTransition(from: state, to: newState)
        state = newState
    }
}
