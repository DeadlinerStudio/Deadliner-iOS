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

    private var configuredSignature: [String]?
    private var lifecycleRevision = 0
    private var networkRevision = 0
    private var configurationRevision = 0

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

    /// Installs credentials once per configuration. Scheduling policy is owned by KMP.
    func configureAutomaticSync() async {
        #if canImport(Shared)
        configurationRevision += 1
        let revision = configurationRevision
        let database = await KMPPersistenceRuntime.shared.coreDatabase()
        guard await cloudSyncEnabled(), !(await inBasicMode()) else {
            guard revision == configurationRevision else { return }
            configuredSignature = nil
            database.disableAutomaticSync()
            SyncBackgroundDriver.schedule(enabled: false)
            return
        }
        let completion: (WebDavChangeLogSyncOutcome) -> Void = { outcome in
            _Concurrency.Task<Void, Never> {
                await SyncCoordinator.shared.handleAutomaticOutcome(outcome)
            }
        }
        switch await syncProvider() {
        case .webDAV:
            guard let cfg = await webDAVConfig(), !cfg.url.isEmpty else {
                guard revision == configurationRevision else { return }
                configuredSignature = nil
                database.disableAutomaticSync()
                SyncBackgroundDriver.schedule(enabled: false)
                return
            }
            guard revision == configurationRevision else { return }
            let signature = ["webdav", cfg.url, cfg.user ?? "", cfg.pass ?? ""]
            guard configuredSignature != signature else {
                SyncBackgroundDriver.schedule(enabled: true)
                return
            }
            configuredSignature = signature
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
            guard revision == configurationRevision else { return }
            guard configuredSignature != ["icloud"] else {
                SyncBackgroundDriver.schedule(enabled: true)
                return
            }
            configuredSignature = ["icloud"]
            database.configureAutomaticTransportSync(
                transport: ICloudSyncBlobTransport(),
                onComplete: completion
            )
            #else
            database.disableAutomaticSync()
            #endif
        }
        SyncBackgroundDriver.startNetworkObservation()
        SyncBackgroundDriver.schedule(enabled: configuredSignature != nil)
        #endif
    }

    func setForeground(_ active: Bool) async {
        #if canImport(Shared)
        lifecycleRevision += 1
        let revision = lifecycleRevision
        if active { await configureAutomaticSync() }
        let database = await KMPPersistenceRuntime.shared.coreDatabase()
        guard revision == lifecycleRevision else { return }
        database.setSyncForeground(active: active)
        if !active { SyncBackgroundDriver.schedule(enabled: configuredSignature != nil) }
        #endif
    }

    func setNetworkAvailable(_ available: Bool) async {
        #if canImport(Shared)
        networkRevision += 1
        let revision = networkRevision
        let database = await KMPPersistenceRuntime.shared.coreDatabase()
        guard revision == networkRevision else { return }
        database.setSyncNetworkAvailable(available: available)
        #endif
    }

    func syncNow() async -> Bool {
        #if canImport(Shared)
        await configureAutomaticSync()
        let database = await KMPPersistenceRuntime.shared.coreDatabase()
        do { return try await database.requestSync(trigger: .manual).succeeded }
        catch { return false }
        #else
        return false
        #endif
    }

    /// Called after a background request, before relinquishing its OS execution window.
    func finishBackgroundSync(_ outcome: WebDavChangeLogSyncOutcome) async {
        if outcome.succeeded, outcome.remoteApplied > 0 {
            await handleLocalChanges(resources: persistenceResources(for: outcome))
        }
    }

    private func handleAutomaticOutcome(_ outcome: WebDavChangeLogSyncOutcome) async {
        AppLog.event(
            "sync.finished",
            domain: .sync,
            level: outcome.succeeded ? .info : .error,
            context: [
                "trigger": "kmp-coordinator",
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
