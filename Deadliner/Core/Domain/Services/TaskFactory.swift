//
//  TaskFactory.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/28.
//

import SwiftUI

func makeDDLInsertParams(from task: AITask) throws -> DDLInsertParams {
    let startDate = Date()
    let startISO = startDate.toLocalISOString()

    // endTime：优先用 AI 给的；否则 = 当前时间 + 1h
    let endDate: Date = {
        if let rawDue = task.dueTime,
           let parsed = DeadlineDateParser.parseAIGeneratedDate(rawDue) {
            return parsed
        }
        return startDate.addingTimeInterval(3600)
    }()
    
    let finalEndDate = max(endDate, startDate.addingTimeInterval(60))

    return DDLInsertParams(
        name: task.name,
        startTime: startISO,
        endTime: finalEndDate.toLocalISOString(),
        state: .active,
        completeTime: "",
        note: task.note ?? "",
        isStared: false,
        subTasks: [],
        type: .task,
        calendarEventId: nil
    )
}
