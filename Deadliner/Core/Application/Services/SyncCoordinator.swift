//
//  SyncCoordinator.swift
//  Deadliner
//

import Foundation
import WidgetKit
import os
#if canImport(Shared)
import Shared
#endif

actor SyncCoordinator {
    static let shared = SyncCoordinator()
    private static let taskStatusControlKind = "com.aritxonly.Deadliner.DeadlinerTaskStatusControl"

    private let logger = Logger(subsystem: "Deadliner", category: "SyncCoordinator")

    private var isSyncing = false

    private init() {}

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

    private func syncProvider() async -> SyncProvider {
        await LocalValues.shared.getSyncProvider()
    }

    private func makeSyncService() async -> (any SyncService)? {
        #if canImport(Shared)
        let database = await KMPPersistenceRuntime.shared.coreDatabase()
        let provider = await syncProvider()
        switch provider {
        case .webDAV:
            guard let cfg = await webDAVConfig() else { return nil }
            return KMPCloudSyncService(
                database: database,
                provider: .webDAV(
                    url: cfg.url,
                    username: cfg.user,
                    password: cfg.pass
                )
            )
        case .iCloud:
            #if canImport(CryptoKit)
            return KMPCloudSyncService(
                database: database,
                provider: .iCloud
            )
            #else
            return nil
            #endif
        }
        #else
        return nil
        #endif
    }

    private static let allPersistenceResources: Set<PersistenceResourceKind> = [
        .task, .taskSubtask, .habit, .habitRecord, .habitSchedule,
        .category, .capture, .memory, .userProfile
    ]

    private func publishDataChanged(
        resources: Set<PersistenceResourceKind> = SyncCoordinator.allPersistenceResources
    ) async {
        await MainActor.run {
            PersistenceChangePublisher.publish(.init(resourceKinds: resources, origin: .syncReplay))
        }
    }

    /// Installs platform-owned credentials/provider into KMP. Repository mutations are the only
    /// automatic trigger; native code retains `syncNow()` solely for explicit pull-to-refresh.
    func configureAutomaticSync() async {
        #if canImport(Shared)
        let database = await KMPPersistenceRuntime.shared.coreDatabase()
        guard await cloudSyncEnabled(), !(await inBasicMode()) else {
            database.disableAutomaticSync()
            return
        }
        let completion: (WebDavChangeLogSyncOutcome) -> Void = { outcome in
            _Concurrency.Task<Void, Never> {
                await SyncCoordinator.shared.handleAutomaticOutcome(outcome)
            }
        }
        switch await syncProvider() {
        case .webDAV:
            guard let cfg = await webDAVConfig() else {
                database.disableAutomaticSync()
                return
            }
            database.configureAutomaticWebDavSync(
                configuration: WebDavTransportConfiguration(
                    baseUrl: cfg.url,
                    credentials: WebDavCredentials(username: cfg.user, password: cfg.pass),
                    requestTimeoutMillis: 15_000
                ),
                onComplete: completion
            )
        case .iCloud:
            #if canImport(CryptoKit)
            database.configureAutomaticTransportSync(
                transport: ICloudSyncBlobTransport(),
                onComplete: completion
            )
            #else
            database.disableAutomaticSync()
            #endif
        }
        #endif
    }

    func syncNow() async -> Bool {
        guard await cloudSyncEnabled() else {
            AppLog.event("sync.manual.skipped", domain: .sync, level: .warning, context: ["reason": "disabled"])
            return false
        }
        if isSyncing {
            AppLog.event("sync.manual.skipped", domain: .sync, level: .warning, context: ["reason": "already-running"])
            return false
        }

        isSyncing = true
        defer {
            isSyncing = false
        }

        guard let syncService = await makeSyncService() else {
            AppLog.event("sync.manual.skipped", domain: .sync, level: .error, context: ["reason": "service-unavailable"])
            return false
        }
        let startedAt = Date()
        AppLog.event("sync.started", domain: .sync, context: ["trigger": "manual"])
        let result = await syncService.syncOnce()
        AppLog.event(
            "sync.finished",
            domain: .sync,
            level: result.success ? .info : .error,
            context: [
                "trigger": "manual",
                "success": "\(result.success)",
                "localChanges": "\(result.hasLocalChanges)",
                "durationMs": "\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
            ]
        )

        if result.hasLocalChanges {
            await handleLocalChanges()
        }
        return result.success
    }

    private func handleAutomaticOutcome(_ outcome: WebDavChangeLogSyncOutcome) async {
        AppLog.event(
            "sync.finished",
            domain: .sync,
            level: outcome.succeeded ? .info : .error,
            context: [
                "trigger": "kmp-repository",
                "success": "\(outcome.succeeded)",
                "remoteApplied": "\(outcome.remoteApplied)"
            ]
        )
        if outcome.succeeded, outcome.remoteApplied > 0 {
            await handleLocalChanges(resources: persistenceResources(for: outcome))
        }
    }

    private func persistenceResources(
        for outcome: WebDavChangeLogSyncOutcome
    ) -> Set<PersistenceResourceKind> {
        var resources: Set<PersistenceResourceKind> = []
        if outcome.appliedResources.contains(.category) { resources.insert(.category) }
        if outcome.appliedResources.contains(.task) {
            resources.formUnion([.task, .taskSubtask])
        }
        if outcome.appliedResources.contains(.habit) {
            resources.formUnion([.habit, .habitRecord, .habitSchedule])
        }
        if outcome.appliedResources.contains(.capture) { resources.insert(.capture) }
        if outcome.appliedResources.contains(.memory) { resources.insert(.memory) }
        if outcome.appliedResources.contains(.profile) { resources.insert(.userProfile) }
        return resources.isEmpty ? Self.allPersistenceResources : resources
    }

    private func handleLocalChanges(
        resources: Set<PersistenceResourceKind> = SyncCoordinator.allPersistenceResources
    ) async {
        AppLog.event("sync.apply-local-changes", domain: .sync)
        await publishDataChanged(resources: resources)
        ControlCenter.shared.reloadControls(ofKind: Self.taskStatusControlKind)

        await KMPTaskReminderScheduler.shared.scheduleRefresh()
        await KMPHabitReminderScheduler.shared.scheduleRefresh()
    }

}
