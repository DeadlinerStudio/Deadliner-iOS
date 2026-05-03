import XCTest
@testable import Deadliner

final class ToolCallExecutorBatchCompatTests: XCTestCase {
    private struct FailurePayload: Decodable {
        let ok: Bool
        let errorCode: String
        let message: String
    }

    private struct TaskWriteBackItem: Decodable {
        let id: Int64?
        let name: String
        let due: String
        let note: String
    }

    private struct HabitWriteBackItem: Decodable {
        let id: Int64?
        let name: String
        let period: String
        let timesPerPeriod: Int
        let goalType: String
        let totalTarget: Int?
    }

    private struct BatchSummary: Decodable {
        let total: Int
        let success: Int
        let failed: Int
    }

    private struct CreateTaskResultItem: Decodable {
        let ok: Bool
        let item: TaskWriteBackItem?
        let message: String?
    }

    private struct CreateHabitResultItem: Decodable {
        let ok: Bool
        let item: HabitWriteBackItem?
        let message: String?
    }

    private struct CreateTaskPayload: Decodable {
        let ok: Bool
        let task: TaskWriteBackItem?
        let createdTasks: [TaskWriteBackItem]
        let items: [CreateTaskResultItem]
        let summary: BatchSummary
        let pendingUserConfirmation: Bool
    }

    private struct CreateHabitPayload: Decodable {
        let ok: Bool
        let habit: HabitWriteBackItem?
        let createdHabits: [HabitWriteBackItem]
        let items: [CreateHabitResultItem]
        let summary: BatchSummary
        let pendingUserConfirmation: Bool
    }

    func testCreateTaskLegacySingleFormatSuccess() async throws {
        let result = await ToolCallExecutor.shared.execute(
            toolName: "create_task",
            argsJson: #"{"name":"写周报","dueTime":"2026-05-02 10:00","note":"发给团队"}"#
        )

        let payload = try decode(CreateTaskPayload.self, from: result.resultJson)
        XCTAssertTrue(payload.ok)
        XCTAssertEqual(payload.summary.success, 1)
        XCTAssertEqual(payload.summary.failed, 0)
        XCTAssertEqual(payload.task?.name, "写周报")
    }

    func testCreateTaskBatchNewFormatSuccess() async throws {
        let result = await ToolCallExecutor.shared.execute(
            toolName: "create_task",
            argsJson: #"{"tasks":[{"name":"任务A","dueTime":"2026-05-02 10:00"},{"name":"任务B","dueTime":"2026-05-03 11:00","note":"备注B"}]}"#
        )

        let payload = try decode(CreateTaskPayload.self, from: result.resultJson)
        XCTAssertTrue(payload.ok)
        XCTAssertEqual(payload.createdTasks.count, 2)
        XCTAssertEqual(payload.summary.success, 2)
        XCTAssertEqual(payload.summary.failed, 0)
    }

    func testCreateHabitLegacySingleFormatSuccess() async throws {
        let result = await ToolCallExecutor.shared.execute(
            toolName: "create_habit",
            argsJson: #"{"name":"晨跑","period":"DAILY","timesPerPeriod":1,"goalType":"PER_PERIOD"}"#
        )

        let payload = try decode(CreateHabitPayload.self, from: result.resultJson)
        XCTAssertTrue(payload.ok)
        XCTAssertEqual(payload.summary.success, 1)
        XCTAssertEqual(payload.habit?.name, "晨跑")
    }

    func testCreateHabitBatchNewFormatSuccess() async throws {
        let result = await ToolCallExecutor.shared.execute(
            toolName: "create_habit",
            argsJson: #"{"habits":[{"name":"早起","period":"DAILY","timesPerPeriod":1,"goalType":"PER_PERIOD"},{"name":"读书","period":"WEEKLY","timesPerPeriod":3,"goalType":"TOTAL","totalTarget":100}]}"#
        )

        let payload = try decode(CreateHabitPayload.self, from: result.resultJson)
        XCTAssertTrue(payload.ok)
        XCTAssertEqual(payload.createdHabits.count, 2)
        XCTAssertEqual(payload.summary.success, 2)
        XCTAssertEqual(payload.summary.failed, 0)
    }

    func testCreateTaskBatchPartialFailure() async throws {
        let result = await ToolCallExecutor.shared.execute(
            toolName: "create_task",
            argsJson: #"{"tasks":[{"name":"合法任务","dueTime":"2026-05-02 10:00"},{"name":"非法时间任务","dueTime":"bad-format"}]}"#
        )

        let payload = try decode(CreateTaskPayload.self, from: result.resultJson)
        XCTAssertTrue(payload.ok)
        XCTAssertEqual(payload.summary.total, 2)
        XCTAssertEqual(payload.summary.success, 1)
        XCTAssertEqual(payload.summary.failed, 1)
        XCTAssertEqual(payload.items.count, 2)
        XCTAssertFalse(payload.items[1].ok)
    }

    func testCreateTaskEmptyArrayInvalidArgs() async throws {
        let result = await ToolCallExecutor.shared.execute(
            toolName: "create_task",
            argsJson: #"{"tasks":[]}"#
        )

        let payload = try decode(FailurePayload.self, from: result.resultJson)
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.errorCode, "INVALID_ARGS")
    }

    func testCreateTaskDueTimeValidationStillWorks() async throws {
        let result = await ToolCallExecutor.shared.execute(
            toolName: "create_task",
            argsJson: #"{"name":"任务","dueTime":"not-a-date"}"#
        )

        let payload = try decode(CreateTaskPayload.self, from: result.resultJson)
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.summary.success, 0)
        XCTAssertEqual(payload.summary.failed, 1)
        XCTAssertEqual(payload.items.first?.message, "dueTime 格式无效，需为 yyyy-MM-dd HH:mm")
    }

    func testCreateHabitTotalGoalMissingTargetShouldFail() async throws {
        let result = await ToolCallExecutor.shared.execute(
            toolName: "create_habit",
            argsJson: #"{"name":"读书","period":"DAILY","timesPerPeriod":1,"goalType":"TOTAL"}"#
        )

        let payload = try decode(CreateHabitPayload.self, from: result.resultJson)
        XCTAssertFalse(payload.ok)
        XCTAssertEqual(payload.summary.success, 0)
        XCTAssertEqual(payload.summary.failed, 1)
        XCTAssertEqual(payload.items.first?.message, "goalType=TOTAL 时 totalTarget 必填")
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(type, from: data)
    }
}
