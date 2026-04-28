//
//  TaskDetailPlanViewModel.swift
//  Deadliner
//
//  Created by Codex on 2026/4/18.
//

import Foundation
import Combine

@MainActor
final class TaskDetailPlanViewModel: ObservableObject {
    @Published private(set) var subTasks: [InnerTodo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isMutating = false

    let taskId: Int64

    private let repository: TaskRepository

    init(taskId: Int64, repository: TaskRepository = .shared) {
        self.taskId = taskId
        self.repository = repository
    }

    func load() async throws {
        isLoading = true
        defer { isLoading = false }
        subTasks = try await repository.getSubTasks(ddlLegacyId: taskId)
    }

    func addSubTask(content: String) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isMutating else { return }

        isMutating = true
        defer { isMutating = false }

        let nextSortOrder = (subTasks.map(\.sortOrder).max() ?? -1) + 1
        _ = try await repository.insertSubTask(
            ddlLegacyId: taskId,
            content: trimmed,
            sortOrder: nextSortOrder
        )
        subTasks = try await repository.getSubTasks(ddlLegacyId: taskId)
    }

    func toggleSubTask(_ subTask: InnerTodo) async throws {
        guard !isMutating else { return }

        isMutating = true
        defer { isMutating = false }

        try await repository.toggleSubTask(ddlLegacyId: taskId, subTask: subTask)
        if let index = subTasks.firstIndex(where: { $0.id == subTask.id }) {
            subTasks[index].isCompleted.toggle()
            subTasks[index].updatedAt = Date().toLocalISOString()
        }
    }

    func deleteSubTask(_ subTask: InnerTodo) async throws {
        guard !isMutating else { return }

        isMutating = true
        defer { isMutating = false }

        try await repository.deleteSubTask(ddlLegacyId: taskId, subTaskId: subTask.id)
        subTasks.removeAll { $0.id == subTask.id }
    }

    func updateSubTaskContent(subTaskId: String, content: String) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isMutating else { return }

        isMutating = true
        defer { isMutating = false }

        try await repository.updateSubTaskContent(
            ddlLegacyId: taskId,
            subTaskId: subTaskId,
            content: trimmed
        )

        if let index = subTasks.firstIndex(where: { $0.id == subTaskId }) {
            subTasks[index].content = trimmed
            subTasks[index].updatedAt = Date().toLocalISOString()
        }
    }
}
