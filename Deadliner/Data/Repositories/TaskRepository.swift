//
//  TaskRepository.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import Foundation
import SwiftData
import os
import WidgetKit

actor TaskRepository {
    static let shared = TaskRepository(db: .shared)
    private static let taskStatusControlKind = "com.aritxonly.Deadliner.DeadlinerTaskStatusControl"

    private let db: DatabaseHelper
    
    private let logger = Logger(subsystem: "Deadliner", category: "TaskRepository")

    private init(db: DatabaseHelper) {
        self.db = db
    }

    private func refreshWidgetsAndControls() {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadControls(ofKind: Self.taskStatusControlKind)
    }

    // MARK: - Init

    func initializeIfNeeded(container: ModelContainer) async throws {
        try await db.initIfNeeded(container: container)
    }

    // MARK: - Public Manual Sync

    @discardableResult
    func syncNow() async -> Bool {
        return await SyncCoordinator.shared.syncNow()
    }

    // MARK: - DDL CRUD

    @discardableResult
    func insertDDL(_ params: DDLInsertParams) async throws -> Int64 {
        let id = try await db.insertDDL(params)
        if let newItem = try await db.getDDLById(id) {
            NotificationManager.shared.scheduleTaskNotification(for: newItem)
        }
        await SyncCoordinator.shared.scheduleSync()
        NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        refreshWidgetsAndControls()
        return id
    }

    func updateDDL(_ item: DDLItem) async throws {
        try await db.updateDDL(legacyId: item.id) { e in
            e.apply(domain: item)
        }
        NotificationManager.shared.scheduleTaskNotification(for: item)
        await SyncCoordinator.shared.scheduleSync()
        NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        refreshWidgetsAndControls()
    }

    func deleteDDL(_ item: DDLItem) async throws {
        logger.info("deleteDDL(item) id=\(item.id, privacy: .public)")
        NotificationManager.shared.cancelTaskNotification(for: item.id)
        try await db.deleteDDL(legacyId: item.id)
        await SyncCoordinator.shared.scheduleSync()
        NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        refreshWidgetsAndControls()
    }

    func deleteDDL(_ id: Int64) async throws {
        logger.info("deleteDDL(id) id=\(id, privacy: .public)")
        NotificationManager.shared.cancelTaskNotification(for: id)
        try await db.deleteDDL(legacyId: id)
        await SyncCoordinator.shared.scheduleSync()
        NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        refreshWidgetsAndControls()
    }

    func getAllDDLs() async throws -> [DDLItem] {
        try await db.getAllDDLs()
    }

    func getDDLsByType(_ type: DeadlineType) async throws -> [DDLItem] {
        try await db.getDDLsByType(type)
    }

    func getDDLById(_ id: Int64) async throws -> DDLItem? {
        try await db.getDDLById(id)
    }

    // MARK: - SubTask

    @discardableResult
    func insertSubTask(
        ddlLegacyId: Int64,
        content: String,
        sortOrder: Int
    ) async throws -> Int64 {
        let id = try await db.insertSubTask(
            .init(
                ddlLegacyId: ddlLegacyId,
                content: content,
                isCompleted: false,
                sortOrder: sortOrder
            )
        )
        await SyncCoordinator.shared.scheduleSync()
        NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        refreshWidgetsAndControls()
        return id
    }

    func getSubTasks(ddlLegacyId: Int64) async throws -> [InnerTodo] {
        try await db.getSubTasksByDDL(ddlLegacyId: ddlLegacyId)
    }

    func toggleSubTask(ddlLegacyId: Int64, subTask: InnerTodo) async throws {
        try await db.updateSubTaskStatus(
            ddlLegacyId: ddlLegacyId,
            subTaskId: subTask.id,
            isCompleted: !subTask.isCompleted
        )
        await SyncCoordinator.shared.scheduleSync()
        NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        refreshWidgetsAndControls()
    }

    func updateSubTaskContent(ddlLegacyId: Int64, subTaskId: String, content: String) async throws {
        try await db.updateSubTaskContent(
            ddlLegacyId: ddlLegacyId,
            subTaskId: subTaskId,
            content: content
        )
        await SyncCoordinator.shared.scheduleSync()
        NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        refreshWidgetsAndControls()
    }

    func deleteSubTask(ddlLegacyId: Int64, subTaskId: String) async throws {
        try await db.deleteSubTask(ddlLegacyId: ddlLegacyId, subTaskId: subTaskId)
        await SyncCoordinator.shared.scheduleSync()
        NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        refreshWidgetsAndControls()
    }

    // MARK: - Auto Archive (minimal)

    func checkAndAutoArchive(days: Int) async {
        guard days > 0 else { return }
        do {
            let archived = try await db.autoArchiveDDLs(days: days)
            if archived > 0 {
                await SyncCoordinator.shared.scheduleSync()
                // TODO: 后续可加通知/UI刷新
            }
        } catch {
            // 可按需加日志
        }
    }
    
    func runDatabaseRepair() async {
        do {
            let deleted = try await db.repairDuplicateData()
            logger.info("DB Repair finished, removed \(deleted) duplicates.")
        } catch {
            logger.error("DB Repair failed: \(error.localizedDescription)")
        }
    }
}
