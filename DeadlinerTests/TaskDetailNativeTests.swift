import Foundation
import Shared
import Testing

@testable import Deadliner

@MainActor
struct TaskDetailNativeTests {
  /// Exercise the Swift adapter against the shipped XCFramework and an isolated real database.
  @Test func commandBridgePersistsDeletionAndUsesCorePreview() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databasePath = directory.appendingPathComponent("detail.sqlite").path
    let database = DeadlinerDatabase.companion.create(
      factory: IosDatabaseDriverFactory(databasePath: databasePath))
    let store = KMPTaskStore(database: database)
    let item = DDLItem(
      id: UUID().uuidString, name: "Native detail command fixture",
      startTime: "2026-10-20T09:00:00", endTime: "2026-10-22T09:00:00", state: .active,
      completeTime: "", note: "", isStared: false,
      subTasks: [
        InnerTodo(id: "remove-me", content: "删除后不应恢复"), InnerTodo(id: "keep-me", content: "保留"),
      ],
      type: .task, habitCount: 0, habitTotalCount: 0, calendarEvent: 0,
      timestamp: "2026-10-20T09:00:00")
    await store.create(item.kmpValue(createdAt: item.timestamp))
    let removed = await store.deleteSubtask(taskUID: item.id, subtaskUID: "remove-me")
    #expect(removed.outcome == .applied)
    let expected = TaskDeadlineShift.shared.postponed(
      raw: item.endTime,
      delay: TaskDeadlineDelay(amount: 3, unit: .hours))
    let postponed = await store.postpone(taskUID: item.id, amount: 3, inHours: true)
    #expect(postponed.outcome == .applied)
    #expect(postponed.task?.dueAt == expected)
    let nextPreview = TaskDeadlineShift.shared.postponed(
      raw: expected,
      delay: TaskDeadlineDelay(amount: 1, unit: .days))
    let next = await store.postpone(taskUID: item.id, amount: 1, inHours: false)
    #expect(next.task?.dueAt == nextPreview)
    let invalid = await store.postpone(taskUID: item.id, amount: 169, inHours: true)
    #expect(invalid.outcome == .invalidDelay)
    let persisted = await store.task(uid: item.id)
    #expect(persisted?.dueAt == nextPreview)
    database.close()
    let reopened = DeadlinerDatabase.companion.create(
      factory: IosDatabaseDriverFactory(databasePath: databasePath))
    defer { reopened.close() }
    let restored = try #require(reopened.tasks.find(uid: item.id))
    #expect(restored.subtasks.map(\.uid) == ["keep-me"])
    #expect(restored.dueAt == nextPreview)
  }

  @Test func seedIsolatedDetailFixture() async throws {
    guard
      ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "DeadlinerDetailValidation"
    else { return }
    let store = PersistenceStores.tasks
    for existing in try await store.allTasks() where existing.name == "详情对齐验证" {
      try await store.deleteTask(id: existing.id)
    }
    let category = try await PersistenceStores.categories.createCategory(
      name: "原型验证", iconKey: "education", colorHex: "#8B5CF6")
    try await store.createTask(
      TaskInsertParams(
        name: "详情对齐验证",
        startTime: "2026-10-20T09:00:00", endTime: "2026-10-28T09:00:00", state: .active,
        completeTime: "", note: "检查独立玻璃按钮、计划编辑与延期预览。", isStared: false,
        subTasks: [
          InnerTodo(content: "核对材料"), InnerTodo(content: "已完成计划", isCompleted: true, sortOrder: 1),
        ],
        calendarEventId: nil, categoryUID: category.uid))
    UserDefaults.standard.set(true, forKey: OnboardingStorageKey.hasSeen)
    UserDefaults.standard.set(false, forKey: OnboardingStorageKey.showOnNextLaunch)
    UserDefaults.standard.set(HomeStyleOption.rich.rawValue, forKey: "settings.home.style")
  }
}
