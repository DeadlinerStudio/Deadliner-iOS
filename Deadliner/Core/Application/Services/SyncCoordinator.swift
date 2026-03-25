//
//  SyncCoordinator.swift
//  Deadliner
//

import Foundation
import WidgetKit
import os

actor SyncCoordinator {
    static let shared = SyncCoordinator(db: .shared)

    private let db: DatabaseHelper
    private let logger = Logger(subsystem: "Deadliner", category: "SyncCoordinator")

    private var syncDebounceTask: Task<Void, Never>?
    private let syncDelayNs: UInt64 = 400_000_000
    private var isSyncing = false
    private var hasPendingSync = false

    private init(db: DatabaseHelper) {
        self.db = db
    }

    private func inBasicMode() async -> Bool {
        await LocalValues.shared.getBasicMode()
    }

    private func cloudSyncEnabled() async -> Bool {
        await LocalValues.shared.getCloudSyncEnabled()
    }

    private func webDAVConfig() async -> (url: String, user: String?, pass: String?)? {
        guard let cfg = await LocalValues.shared.getWebDAVConfig() else { return nil }
        return (cfg.url, cfg.auth.user, cfg.auth.pass)
    }

    private func makeSyncService() async -> (any SyncService)? {
        guard let cfg = await webDAVConfig() else { return nil }
        let web = WebDAVClient(baseURL: cfg.url, username: cfg.user, password: cfg.pass)
        return SyncServiceFactory.make(db: db, web: web, impl: .v2)
    }

    func scheduleSync() async {
        syncDebounceTask?.cancel()
        syncDebounceTask = nil

        guard await cloudSyncEnabled() else { return }

        syncDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: self.syncDelayNs)
                await self.performSync()
            } catch {
                // cancelled
            }
        }
    }

    func syncNow() async -> Bool {
        syncDebounceTask?.cancel()
        syncDebounceTask = nil

        if isSyncing {
            return false
        }

        isSyncing = true
        defer {
            isSyncing = false
        }

        guard let syncService = await makeSyncService() else { return false }
        let result = await syncService.syncOnce()

        if result.hasLocalChanges {
            await handleLocalChanges()
        }

        if hasPendingSync {
            hasPendingSync = false
            await performSync()
        }

        return result.success
    }

    private func performSync() async {
        if await inBasicMode() { return }

        if isSyncing {
            hasPendingSync = true
            return
        }

        isSyncing = true
        hasPendingSync = false

        defer {
            isSyncing = false
        }

        guard let syncService = await makeSyncService() else { return }
        let result = await syncService.syncOnce()

        if result.hasLocalChanges {
            await handleLocalChanges()
        }

        if hasPendingSync {
            hasPendingSync = false
            await performSync()
        }
    }

    private func handleLocalChanges() async {
        NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        WidgetCenter.shared.reloadAllTimelines()

        do {
            let allTasks = try await db.getDDLsByType(.task)
            NotificationManager.shared.refreshAllTaskNotifications(tasks: allTasks)
            HabitRepository.shared.scheduleReminderRefresh()
        } catch {
            logger.error("Failed to refresh local state after sync: \(error.localizedDescription)")
        }
    }
}
