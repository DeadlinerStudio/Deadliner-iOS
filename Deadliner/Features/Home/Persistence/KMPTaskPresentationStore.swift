//
//  KMPTaskPresentationStore.swift
//  Deadliner
//
//  UID-first Task UI store backed directly by the KMP aggregate.
//

#if canImport(Shared)
import Foundation
import Shared

enum KMPTaskPresentationError: LocalizedError {
    case missingTask(String)
    case invalidAction(DDLStateAction)
    case timerRequiresResolution(String)

    var errorDescription: String? {
        switch self {
        case let .missingTask(uid):
            return "KMP task \(uid) no longer exists."
        case .invalidAction:
            return "The requested task action is not valid for its current KMP state."
        case .timerRequiresResolution:
            return "请先在专注计时页结束当前计时。"
        }
    }
}

@MainActor
final class KMPTaskPresentationStore: KMPTaskUIStore {
    func createTask(_ params: TaskInsertParams) async throws -> String {
        let uid = UUID().uuidString.lowercased()
        let now = Date().toLocalISOString()
        let task = Task_(
            uid: uid,
            title: params.name,
            note: params.note,
            startAt: params.startTime.emptyToNil,
            dueAt: params.endTime.emptyToNil,
            state: params.state.kmpTaskState,
            completedAt: params.completeTime.emptyToNil,
            categoryUid: params.categoryUID,
            isStarred: params.isStared,
            calendarEventId: params.calendarEventId.map { KotlinLong(value: $0) },
            createdAt: now,
            updatedAt: now,
            isDeleted: false,
            subtasks: params.subTasks.map { $0.kmpValue(taskUID: uid, now: now) }
        )
        let store = await KMPPersistenceRuntime.shared.taskStore()
        await store.create(task)
        trace("create", uid: uid)
        return uid
    }

    func task(id: String) async throws -> DDLItem? {
        let store = await KMPPersistenceRuntime.shared.taskStore()
        guard let task = await store.task(uid: id), !task.isDeleted else { return nil }
        return task.ddlProjection()
    }

    func allTasks() async throws -> [DDLItem] {
        let store = await KMPPersistenceRuntime.shared.taskStore()
        return await store.allTasks().map { $0.ddlProjection() }
    }

    func tasks(of type: DeadlineType) async throws -> [DDLItem] {
        guard type == .task else { return [] }
        return try await allTasks()
    }

    func updateTask(_ item: DDLItem) async throws {
        let store = await KMPPersistenceRuntime.shared.taskStore()
        guard let existing = await store.task(uid: item.id), !existing.isDeleted else {
            throw KMPTaskPresentationError.missingTask(item.id)
        }
        guard existing.state == item.state.kmpTaskState else {
            throw KMPTaskPresentationError.invalidAction(.restoreActive)
        }
        let result = await store.update(item.kmpValue(createdAt: existing.createdAt))
        guard result.outcome != .timerRequiresResolution else {
            FocusTimerPresentationModel.shared.message = "请先结束当前专注，再改变任务状态。"
            FocusTimerPresentationModel.shared.openRequested = true
            throw KMPTaskPresentationError.timerRequiresResolution(item.id)
        }
        guard result.outcome == .applied else {
            throw KMPTaskPresentationError.invalidAction(.restoreActive)
        }
        trace("update", uid: item.id)
    }

    func performTaskAction(id: String, action: DDLStateAction) async throws -> DDLItem {
        let store = await KMPPersistenceRuntime.shared.taskStore()
        let result = await store.perform(
            action: action.kmpTaskAction,
            taskUID: id,
            occurredAt: Date().toLocalISOString()
        )
        if result.outcome == .timerRequiresResolution {
            let applied = await FocusTimerPresentationModel.shared.confirmTargetChange(uid: id, habit: false, delete: false, action: action.kmpTaskAction)
            guard applied else { throw CancellationError() }
            guard let task = await store.task(uid: id) else { throw KMPTaskPresentationError.missingTask(id) }
            return task.ddlProjection()
        }
        guard result.outcome == .applied, let task = result.task else {
            throw KMPTaskPresentationError.invalidAction(action)
        }
        trace("action", uid: id)
        return task.ddlProjection()
    }

    func deleteTask(id: String) async throws {
        let store = await KMPPersistenceRuntime.shared.taskStore()
        let result = await store.delete(uid: id, updatedAt: Date().toLocalISOString())
        if result.outcome == .timerRequiresResolution {
            guard await FocusTimerPresentationModel.shared.confirmTargetChange(uid: id, habit: false, delete: true) else { throw CancellationError() }
            return
        }
        guard result.outcome == .applied else {
            throw KMPTaskPresentationError.missingTask(id)
        }
        trace("delete", uid: id)
    }

    private func trace(_ operation: String, uid: String) {
        AppLog.event(
            "kmp.ui.task.\(operation)",
            domain: .kmp,
            context: ["uid": uid]
        )
    }
}

extension Task_ {
    func ddlProjection() -> DDLItem {
        DDLItem(
            id: uid,
            name: title,
            startTime: startAt ?? "",
            endTime: dueAt ?? "",
            state: state.ddlState,
            completeTime: completedAt ?? "",
            note: note,
            isStared: isStarred,
            subTasks: subtasks.filter { !$0.isDeleted }.map(\.ddlProjection),
            type: .task,
            habitCount: 0,
            habitTotalCount: 0,
            calendarEvent: calendarEventId?.int64Value ?? 0,
            timestamp: updatedAt,
            categoryUID: categoryUid
        )
    }
}

private extension TaskSubtask {
    var ddlProjection: InnerTodo {
        InnerTodo(
            id: uid,
            content: content,
            isCompleted: isCompleted,
            sortOrder: Int(sortOrder),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension DDLItem {
    func kmpValue(createdAt: String) -> Task_ {
        let now = Date().toLocalISOString()
        return Task_(
            uid: id,
            title: name,
            note: note,
            startAt: startTime.emptyToNil,
            dueAt: endTime.emptyToNil,
            state: state.kmpTaskState,
            completedAt: completeTime.emptyToNil,
            categoryUid: categoryUID,
            isStarred: isStared,
            calendarEventId: calendarEvent == 0 ? nil : KotlinLong(value: calendarEvent),
            createdAt: createdAt,
            updatedAt: now,
            isDeleted: false,
            subtasks: subTasks.map { $0.kmpValue(taskUID: id, now: now) }
        )
    }
}

extension InnerTodo {
    func kmpValue(taskUID: String, now: String) -> TaskSubtask {
        TaskSubtask(
            uid: id,
            taskUid: taskUID,
            content: content,
            isCompleted: isCompleted,
            sortOrder: Int32(sortOrder),
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            isDeleted: false
        )
    }
}

extension DDLState {
    var kmpTaskState: TaskState {
        switch self {
        case .active: .active
        case .completed: .completed
        case .archived: .archived
        case .abandoned: .abandoned
        case .abandonedArchived: .abandonedArchived
        }
    }
}

extension DDLStateAction {
    var kmpTaskAction: TaskAction {
        switch self {
        case .markComplete: .markComplete
        case .markArchive: .markArchive
        case .markGiveUp: .markGiveUp
        case .restoreActive: .restoreActive
        case .unarchive: .unarchive
        }
    }
}

private extension TaskState {
    var ddlState: DDLState {
        if self == .completed { return .completed }
        if self == .archived { return .archived }
        if self == .abandoned { return .abandoned }
        if self == .abandonedArchived { return .abandonedArchived }
        return .active
    }
}

private extension String {
    var emptyToNil: String? { isEmpty ? nil : self }
}
#endif
