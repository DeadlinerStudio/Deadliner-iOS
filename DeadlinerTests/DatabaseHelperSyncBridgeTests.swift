//
//  DatabaseHelperSyncBridgeTests.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import XCTest
import SwiftData
@testable import Deadliner

final class DatabaseHelperSyncBridgeTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        try awaitInit()
    }

    private func awaitInit() throws {
        let exp = expectation(description: "init db")
        Task {
            do {
                try await DatabaseHelper.shared.initIfNeeded(container: container)
                exp.fulfill()
            } catch {
                XCTFail("init failed: \(error)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testInsertDDLFromSnapshotAndFindByUID() throws {
        let doc = SnapshotDoc(
            id: 42,
            name: "Task A",
            start_time: "2026-02-16T10:00:00",
            end_time: "2026-02-17T10:00:00",
            is_completed: 0,
            complete_time: "",
            note: "n",
            is_archived: 0,
            is_stared: 1,
            type: "task",
            habit_count: 0,
            habit_total_count: 0,
            calendar_event: -1,
            timestamp: "2026-02-16T10:00:00"
        )

        let exp = expectation(description: "insert")
        Task {
            do {
                try await DatabaseHelper.shared.insertDDLFromSnapshot(
                    uid: "DEV123:42",
                    doc: doc,
                    verTs: "2026-02-16T10:00:00Z",
                    verCtr: 0,
                    verDev: "DEV123"
                )
                let found = try await DatabaseHelper.shared.findDDLByUID("DEV123:42")
                XCTAssertNotNil(found)
                XCTAssertEqual(found?.legacyId, 42)
                XCTAssertEqual(found?.name, "Task A")
                XCTAssertEqual(found?.isTombstoned, false)
                exp.fulfill()
            } catch {
                XCTFail("failed: \(error)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testApplyTombstone() throws {
        let exp = expectation(description: "tombstone")
        Task {
            do {
                let id = try await DatabaseHelper.shared.insertDDL(.init(
                    name: "To Delete",
                    startTime: "2026-02-16T10:00:00",
                    endTime: "2026-02-16T12:00:00",
                    state: .active,
                    completeTime: "",
                    note: "",
                    isStared: false,
                    subTasks: [],
                    type: .task,
                    calendarEventId: nil
                ))

                try await DatabaseHelper.shared.applyTombstone(
                    legacyId: id,
                    verTs: "2026-02-16T11:00:00Z",
                    verCtr: 1,
                    verDev: "D1"
                )

                let all = try await DatabaseHelper.shared.getAllDDLsIncludingDeletedForSync()
                let target = all.first(where: { $0.legacyId == id })
                XCTAssertEqual(target?.isTombstoned, true)
                XCTAssertEqual(target?.isArchived, true)
                exp.fulfill()
            } catch {
                XCTFail("failed: \(error)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testOverwriteDDLFromSnapshot() throws {
        let exp = expectation(description: "overwrite")
        Task {
            do {
                let id = try await DatabaseHelper.shared.insertDDL(.init(
                    name: "Old",
                    startTime: "2026-02-16T09:00:00",
                    endTime: "2026-02-16T10:00:00",
                    state: .active,
                    completeTime: "",
                    note: "old",
                    isStared: false,
                    subTasks: [],
                    type: .task,
                    calendarEventId: nil
                ))

                let doc = SnapshotDoc(
                    id: id,
                    name: "New Name",
                    start_time: "2026-02-16T09:00:00",
                    end_time: "2026-02-18T10:00:00",
                    is_completed: 1,
                    complete_time: "2026-02-16T12:00:00",
                    note: "new",
                    is_archived: 1,
                    is_stared: 1,
                    type: "task",
                    habit_count: 2,
                    habit_total_count: 7,
                    calendar_event: 99,
                    timestamp: "2026-02-16T12:00:00"
                )

                try await DatabaseHelper.shared.overwriteDDLFromSnapshot(
                    legacyId: id,
                    doc: doc,
                    verTs: "2026-02-16T12:00:00Z",
                    verCtr: 2,
                    verDev: "D2"
                )

                let all = try await DatabaseHelper.shared.getAllDDLsIncludingDeletedForSync()
                let target = all.first(where: { $0.legacyId == id })
                XCTAssertEqual(target?.name, "New Name")
                XCTAssertEqual(target?.isCompleted, true)
                XCTAssertEqual(target?.calendarEventId, 99)
                XCTAssertEqual(target?.verCtr, 2)
                exp.fulfill()
            } catch {
                XCTFail("failed: \(error)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testInsertDDLFromSnapshotV2PersistsStateAndSubTasks() throws {
        let exp = expectation(description: "insert v2")
        Task {
            do {
                let doc = SnapshotV2Doc(
                    id: 88,
                    name: "Task V2",
                    start_time: "2026-03-23T10:00:00",
                    end_time: "2026-03-24T10:00:00",
                    state: DDLState.abandoned.rawValue,
                    complete_time: "",
                    note: "v2",
                    is_stared: 1,
                    type: "task",
                    habit_count: 0,
                    habit_total_count: 0,
                    calendar_event: -1,
                    timestamp: "2026-03-23T10:00:00",
                    sub_tasks: [
                        .init(
                            id: "sub-1",
                            content: "Nested item",
                            is_completed: 1,
                            sort_order: 0,
                            created_at: "2026-03-23T10:00:00Z",
                            updated_at: "2026-03-23T11:00:00Z"
                        )
                    ]
                )

                try await DatabaseHelper.shared.insertDDLFromSnapshotV2(
                    uid: "DEV123:88",
                    doc: doc,
                    verTs: "2026-03-23T12:00:00Z",
                    verCtr: 0,
                    verDev: "DEV123"
                )

                let found = try await DatabaseHelper.shared.findDDLByUID("DEV123:88")
                XCTAssertNotNil(found)
                XCTAssertEqual(found?.resolvedState(), .abandoned)
                XCTAssertEqual(try found?.decodedSubTasks().count, 1)
                XCTAssertEqual(try found?.decodedSubTasks().first?.content, "Nested item")
                exp.fulfill()
            } catch {
                XCTFail("failed: \(error)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testInsertDDLFromSnapshotV2RejectsInvalidState() throws {
        let exp = expectation(description: "invalid v2 state")
        Task {
            do {
                let doc = SnapshotV2Doc(
                    id: 99,
                    name: "Broken Task",
                    start_time: "2026-03-23T10:00:00",
                    end_time: "2026-03-24T10:00:00",
                    state: "unknown-state",
                    complete_time: "",
                    note: "",
                    is_stared: 0,
                    type: "task",
                    habit_count: 0,
                    habit_total_count: 0,
                    calendar_event: -1,
                    timestamp: "2026-03-23T10:00:00",
                    sub_tasks: []
                )

                do {
                    try await DatabaseHelper.shared.insertDDLFromSnapshotV2(
                        uid: "DEV123:99",
                        doc: doc,
                        verTs: "2026-03-23T12:00:00Z",
                        verCtr: 0,
                        verDev: "DEV123"
                    )
                    XCTFail("Expected invalid state error")
                } catch DBError.invalidData(let message) {
                    XCTAssertTrue(message.contains("Invalid V2 state"))
                }
                exp.fulfill()
            } catch {
                XCTFail("failed: \(error)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testUpsertHabitFromSnapshotV2PersistsPayload() throws {
        let exp = expectation(description: "upsert habit snapshot")
        Task {
            do {
                try await DatabaseHelper.shared.insertDDLFromSnapshotV2(
                    uid: "DEV123:H1",
                    doc: .init(
                        id: 101,
                        name: "Habit Carrier",
                        start_time: "2026-03-24T08:00:00",
                        end_time: "2026-03-24T09:00:00",
                        state: DDLState.active.rawValue,
                        complete_time: "",
                        note: "",
                        is_stared: 0,
                        type: DeadlineType.habit.rawValue,
                        habit_count: 0,
                        habit_total_count: 0,
                        calendar_event: -1,
                        timestamp: "2026-03-24T08:00:00",
                        sub_tasks: []
                    ),
                    verTs: "2026-03-24T08:00:00Z",
                    verCtr: 0,
                    verDev: "DEV123"
                )

                let habit = try await DatabaseHelper.shared.upsertHabitFromSnapshotV2(
                    ddlUID: "DEV123:H1",
                    payload: .init(
                        name: "Read",
                        description: "15m",
                        color: 1,
                        icon_key: "book",
                        period: HabitPeriod.daily.rawValue,
                        times_per_period: 1,
                        goal_type: HabitGoalType.perPeriod.rawValue,
                        total_target: nil,
                        created_at: "2026-03-24T08:00:00Z",
                        updated_at: "2026-03-24T09:00:00Z",
                        status: HabitStatus.active.rawValue,
                        sort_order: 2,
                        alarm_time: "21:00"
                    )
                )

                XCTAssertEqual(habit.name, "Read")
                XCTAssertEqual(habit.periodRaw, HabitPeriod.daily.rawValue)
                XCTAssertEqual(habit.goalTypeRaw, HabitGoalType.perPeriod.rawValue)
                XCTAssertEqual(habit.ddl?.uid, "DEV123:H1")
                exp.fulfill()
            } catch {
                XCTFail("failed: \(error)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testUpsertHabitFromSnapshotV2RejectsInvalidPayload() throws {
        let exp = expectation(description: "invalid habit payload")
        Task {
            do {
                try await DatabaseHelper.shared.insertDDLFromSnapshotV2(
                    uid: "DEV123:H2",
                    doc: .init(
                        id: 102,
                        name: "Habit Carrier 2",
                        start_time: "2026-03-24T08:00:00",
                        end_time: "2026-03-24T09:00:00",
                        state: DDLState.active.rawValue,
                        complete_time: "",
                        note: "",
                        is_stared: 0,
                        type: DeadlineType.habit.rawValue,
                        habit_count: 0,
                        habit_total_count: 0,
                        calendar_event: -1,
                        timestamp: "2026-03-24T08:00:00",
                        sub_tasks: []
                    ),
                    verTs: "2026-03-24T08:00:00Z",
                    verCtr: 0,
                    verDev: "DEV123"
                )

                do {
                    _ = try await DatabaseHelper.shared.upsertHabitFromSnapshotV2(
                        ddlUID: "DEV123:H2",
                        payload: .init(
                            name: "Broken",
                            description: nil,
                            color: nil,
                            icon_key: nil,
                            period: "BROKEN",
                            times_per_period: 1,
                            goal_type: HabitGoalType.perPeriod.rawValue,
                            total_target: nil,
                            created_at: "2026-03-24T08:00:00Z",
                            updated_at: "2026-03-24T09:00:00Z",
                            status: HabitStatus.active.rawValue,
                            sort_order: 0,
                            alarm_time: nil
                        )
                    )
                    XCTFail("Expected invalid habit payload")
                } catch DBError.invalidData(let message) {
                    XCTAssertTrue(message.contains("period"))
                }

                exp.fulfill()
            } catch {
                XCTFail("failed: \(error)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testReplaceHabitRecordsFromSnapshotV2RejectsInvalidRecordStatus() throws {
        let exp = expectation(description: "invalid habit record payload")
        Task {
            do {
                try await DatabaseHelper.shared.insertDDLFromSnapshotV2(
                    uid: "DEV123:H3",
                    doc: .init(
                        id: 103,
                        name: "Habit Carrier 3",
                        start_time: "2026-03-24T08:00:00",
                        end_time: "2026-03-24T09:00:00",
                        state: DDLState.active.rawValue,
                        complete_time: "",
                        note: "",
                        is_stared: 0,
                        type: DeadlineType.habit.rawValue,
                        habit_count: 0,
                        habit_total_count: 0,
                        calendar_event: -1,
                        timestamp: "2026-03-24T08:00:00",
                        sub_tasks: []
                    ),
                    verTs: "2026-03-24T08:00:00Z",
                    verCtr: 0,
                    verDev: "DEV123"
                )
                let habit = try await DatabaseHelper.shared.upsertHabitFromSnapshotV2(
                    ddlUID: "DEV123:H3",
                    payload: .init(
                        name: "Read",
                        description: nil,
                        color: nil,
                        icon_key: nil,
                        period: HabitPeriod.daily.rawValue,
                        times_per_period: 1,
                        goal_type: HabitGoalType.perPeriod.rawValue,
                        total_target: nil,
                        created_at: "2026-03-24T08:00:00Z",
                        updated_at: "2026-03-24T09:00:00Z",
                        status: HabitStatus.active.rawValue,
                        sort_order: 0,
                        alarm_time: nil
                    )
                )

                do {
                    try await DatabaseHelper.shared.replaceHabitRecordsFromSnapshotV2(
                        habitLegacyId: habit.legacyId,
                        records: [
                            .init(
                                date: "2026-03-24",
                                count: 1,
                                status: "BROKEN",
                                created_at: "2026-03-24T08:00:00Z"
                            )
                        ]
                    )
                    XCTFail("Expected invalid habit record payload")
                } catch DBError.invalidData(let message) {
                    XCTAssertTrue(message.contains("record status"))
                }

                exp.fulfill()
            } catch {
                XCTFail("failed: \(error)")
            }
        }
        wait(for: [exp], timeout: 2.0)
    }
}
