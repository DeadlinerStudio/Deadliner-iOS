//
//  SyncServiceV2Tests.swift
//  DeadlinerTests
//

import XCTest
@testable import Deadliner

final class SyncServiceV2Tests: XCTestCase {

    func testProjectStateToV1DowngradesAbandonedToArchived() throws {
        let service = SyncServiceV2(
            db: DatabaseHelper.shared,
            web: WebDAVClient(baseURL: "https://example.com")
        )

        let projected = service.projectStateToV1(.abandoned)
        XCTAssertEqual(projected, .archived)
    }

    func testProjectV2RootToV1MapsStateAndDropsSubTasks() throws {
        let service = SyncServiceV2(
            db: DatabaseHelper.shared,
            web: WebDAVClient(baseURL: "https://example.com")
        )

        let root = SnapshotV2Root(
            version: .init(ts: "2026-03-23T00:00:00Z", dev: "D1"),
            items: [
                SnapshotV2Item(
                    uid: "D1:1",
                    ver: .init(ts: "2026-03-23T00:00:00Z", ctr: 0, dev: "D1"),
                    deleted: false,
                    doc: .init(
                        id: 1,
                        name: "Abandoned Task",
                        start_time: "2026-03-23T08:00:00",
                        end_time: "2026-03-23T10:00:00",
                        state: DDLState.abandoned.rawValue,
                        complete_time: "",
                        note: "n",
                        is_stared: 0,
                        type: "task",
                        habit_count: 0,
                        habit_total_count: 0,
                        calendar_event: -1,
                        timestamp: "2026-03-23T08:00:00",
                        sub_tasks: [
                            .init(
                                id: "s1",
                                content: "child",
                                is_completed: 1,
                                sort_order: 0,
                                created_at: nil,
                                updated_at: nil
                            )
                        ]
                    )
                )
            ]
        )

        let projected = try service.projectV2RootToV1(root)
        guard let item = projected.items.first, let doc = item.doc else {
            return XCTFail("Expected projected V1 item")
        }

        XCTAssertEqual(doc.is_completed, 1)
        XCTAssertEqual(doc.is_archived, 1)
        XCTAssertEqual(doc.name, "Abandoned Task")
    }
}
