//
//  TaskDetailPlanViewModel.swift
//  Deadliner
//
//  Created by Codex on 2026/4/18.
//

import Combine
import Foundation

@MainActor
final class TaskDetailPlanViewModel: ObservableObject {
  @Published private(set) var subTasks: [InnerTodo] = []
  @Published private(set) var isLoading = false
  @Published private(set) var isMutating = false

  let taskId: String

  private var loadGeneration = 0
  private let taskStore: any KMPTaskUIStore

  init(taskId: String, taskStore: (any KMPTaskUIStore)? = nil) {
    self.taskId = taskId
    self.taskStore = taskStore ?? PersistenceStores.tasks
  }

  func load() async throws {
    guard !isMutating else { return }
    loadGeneration += 1
    let generation = loadGeneration
    isLoading = true
    defer { if generation == loadGeneration { isLoading = false } }
    let item = try await task()
    guard !Task.isCancelled, generation == loadGeneration else { return }
    subTasks = item.subTasks
  }

  func addSubTask(content: String) async throws {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard !isMutating else { return }

    loadGeneration += 1
    isLoading = false
    isMutating = true
    defer { isMutating = false }

    var item = try await task()
    let nextSortOrder = (item.subTasks.map(\.sortOrder).max() ?? -1) + 1
    item.subTasks.append(
      InnerTodo(
        id: UUID().uuidString.lowercased(),
        content: trimmed,
        isCompleted: false,
        sortOrder: nextSortOrder,
        createdAt: Date().toLocalISOString(),
        updatedAt: Date().toLocalISOString()
      )
    )
    try await update(item)
    subTasks = item.subTasks
  }

  func toggleSubTask(_ subTask: InnerTodo) async throws {
    guard !isMutating else { return }

    loadGeneration += 1
    isLoading = false
    isMutating = true
    defer { isMutating = false }

    var item = try await task()
    guard let index = item.subTasks.firstIndex(where: { $0.id == subTask.id }) else {
      throw TaskDetailPlanError.subTaskNotFound
    }
    item.subTasks[index].isCompleted.toggle()
    item.subTasks[index].updatedAt = Date().toLocalISOString()
    try await update(item)
    subTasks = item.subTasks
  }

  func deleteSubTask(_ subTask: InnerTodo) async throws {
    guard !isMutating else { return }

    loadGeneration += 1
    isLoading = false
    isMutating = true
    defer { isMutating = false }

    let item = try await taskStore.deleteSubTask(taskId: taskId, subTaskId: subTask.id)
    subTasks = item.subTasks
  }

  func updateSubTaskContent(subTaskId: String, content: String) async throws {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard !isMutating else { return }

    loadGeneration += 1
    isLoading = false
    isMutating = true
    defer { isMutating = false }

    var item = try await task()
    guard let index = item.subTasks.firstIndex(where: { $0.id == subTaskId }) else {
      throw TaskDetailPlanError.subTaskNotFound
    }
    item.subTasks[index].content = trimmed
    item.subTasks[index].updatedAt = Date().toLocalISOString()
    try await update(item)
    subTasks = item.subTasks
  }

  private func task() async throws -> DDLItem {
    let item = try await taskStore.task(id: taskId)
    guard let item else {
      throw TaskDetailPlanError.taskNotFound
    }
    return item
  }

  private func update(_ item: DDLItem) async throws {
    try await taskStore.updateTask(item)
  }
}

private enum TaskDetailPlanError: LocalizedError {
  case taskNotFound
  case subTaskNotFound

  var errorDescription: String? {
    switch self {
    case .taskNotFound: "任务已不存在。"
    case .subTaskNotFound: "子任务已被删除，请刷新后重试。"
    }
  }
}
