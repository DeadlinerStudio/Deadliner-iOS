//
//  DDLItemEntity+Mapping.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import Foundation

extension DDLItemEntity {
    func toDomain() -> DDLItem {
        let state = resolvedState()

        let subTasks: [InnerTodo]
        do {
            subTasks = try decodedSubTasks()
        } catch {
            preconditionFailure("Failed to decode subTasks for legacyId \(legacyId): \(error)")
        }

        return DDLItem(
            id: legacyId,
            name: name,
            startTime: startTime,
            endTime: endTime,
            state: state,
            completeTime: completeTime,
            note: note,
            isStared: isStared,
            subTasks: subTasks,
            type: DeadlineType(rawValue: typeRaw) ?? .task,
            habitCount: habitCount,
            habitTotalCount: habitTotalCount,
            calendarEvent: calendarEventId,
            timestamp: timestamp
        )
    }
}

extension DDLItemEntity {
    func apply(domain: DDLItem) {
        name = domain.name
        startTime = domain.startTime
        endTime = domain.endTime
        stateRaw = domain.state.rawValue
        isCompleted = domain.isCompleted
        completeTime = domain.completeTime
        note = domain.note
        isArchived = domain.isArchived
        isStared = domain.isStared
        do {
            subTasksJSON = try Self.encodeSubTasks(domain.subTasks)
        } catch {
            preconditionFailure("Failed to encode subTasks for legacyId \(legacyId): \(error)")
        }
        typeRaw = domain.type.rawValue
        habitCount = domain.habitCount
        habitTotalCount = domain.habitTotalCount
        calendarEventId = domain.calendarEvent
        timestamp = domain.timestamp
    }
}

extension DDLItemEntity {
    static func encodeSubTasks(_ subTasks: [InnerTodo]) throws -> Data {
        try JSONEncoder().encode(subTasks.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.id < rhs.id
        })
    }

    func decodedSubTasks() throws -> [InnerTodo] {
        guard let subTasksJSON else { return [] }
        return try JSONDecoder().decode([InnerTodo].self, from: subTasksJSON)
    }

    func currentState() -> DDLState? {
        guard let stateRaw else { return nil }
        return DDLState(rawValue: stateRaw)
    }

    func resolvedState() -> DDLState {
        if let state = currentState() {
            return state
        }
        if isArchived {
            return .archived
        }
        if isCompleted {
            return .completed
        }
        return .active
    }

    /// For habit carriers, derive archive state from habit.status as the single source of truth.
    func resolvedStateForSync() -> DDLState {
        guard typeRaw == DeadlineType.habit.rawValue else {
            return resolvedState()
        }
        guard let habit, let status = HabitStatus(rawValue: habit.statusRaw) else {
            return resolvedState()
        }
        return status == .archived ? .archived : .active
    }

    func habitAppliedSnapshotVersionRaw() -> (ts: String, ctr: Int, dev: String)? {
        guard let ts = habitAppliedVerTs,
              let ctr = habitAppliedVerCtr,
              let dev = habitAppliedVerDev,
              !ts.isEmpty,
              !dev.isEmpty else {
            return nil
        }
        return (ts: ts, ctr: ctr, dev: dev)
    }

    func setHabitAppliedSnapshotVersion(ts: String, ctr: Int, dev: String) {
        habitAppliedVerTs = ts
        habitAppliedVerCtr = ctr
        habitAppliedVerDev = dev
    }
}
