//
//  KMPTaskStore.swift
//  Deadliner
//
//  UID-first Task/Subtask access backed by DeadlinerCore.
//

#if canImport(Shared)
import Foundation
import Shared

actor KMPTaskStore: KMPTaskPersistenceStore {
    private let database: DeadlinerDatabase

    init(database: DeadlinerDatabase) {
        self.database = database
    }

    func allTasks() -> [Task_] {
        database.tasks.list().filter { !$0.isDeleted }
    }

    func task(uid: String) -> Task_? {
        database.tasks.find(uid: uid)
    }

    func create(_ task: Task_) async {
        database.tasks.create(task: task)
        trace("create", uid: task.uid)
        await publishChange(resources: [.task, .taskSubtask])
        await KMPTaskReminderScheduler.shared.scheduleRefresh()
    }

    func update(_ task: Task_) async {
        database.tasks.update(task: task)
        trace("update", uid: task.uid)
        await publishChange(resources: [.task, .taskSubtask])
        await KMPTaskReminderScheduler.shared.scheduleRefresh()
    }

    func perform(action: TaskAction, taskUID: String, occurredAt: String) async -> TaskActionResult {
        let result = database.tasks.applyAction(uid: taskUID, action: action, occurredAt: occurredAt)
        if result.outcome == .applied {
            trace("action", uid: taskUID, extra: ["action": "\(action)"])
            await publishChange(resources: [.task, .taskSubtask])
            await KMPTaskReminderScheduler.shared.scheduleRefresh()
        } else {
            trace(
                "action-rejected",
                uid: taskUID,
                extra: ["action": "\(action)", "outcome": "\(result.outcome)"]
            )
        }
        return result
    }

    func delete(uid: String, updatedAt: String) async {
        database.tasks.delete(uid: uid, updatedAt: updatedAt)
        trace("delete", uid: uid)
        await publishChange(resources: [.task, .taskSubtask])
        await KMPTaskReminderScheduler.shared.scheduleRefresh()
    }

    private func publishChange(resources: Set<PersistenceResourceKind>) async {
        await MainActor.run {
            PersistenceChangePublisher.publish(.init(resourceKinds: resources))
        }
    }

    private func trace(_ operation: String, uid: String, extra: [String: String] = [:]) {
        var context = extra
        context["uid"] = uid
        AppLog.event("persistence.task.\(operation)", domain: .persistence, context: context)
    }
}
#endif
