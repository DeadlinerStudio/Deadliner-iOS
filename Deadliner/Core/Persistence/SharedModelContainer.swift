//
//  SharedModelContainer.swift
//  Deadliner
//

import SwiftData
import Foundation

public enum SharedModelContainer {
    public static let appGroupId = "group.top.aritxonly.deadliner.group"
    public static let iCloudContainerId = "iCloud.top.aritxonly.deadliner"

    private static let cloudSyncEnabledKey = "settings.cloud_sync_enabled"
    private static let syncProviderKey = "settings.sync_provider"
    private static let iCloudSyncProviderRawValue = "icloud"

    private static var shouldUseICloudSync: Bool {
        let defaults = UserDefaults.standard
        let cloudSyncEnabled = defaults.object(forKey: cloudSyncEnabledKey) as? Bool ?? true
        let rawProvider = defaults.string(forKey: syncProviderKey) ?? "webdav"
        return cloudSyncEnabled && rawProvider == iCloudSyncProviderRawValue
    }

    public static let shared: ModelContainer = {
        let schema = Schema([
            DDLItemEntity.self,
            SubTaskEntity.self,
            HabitEntity.self,
            HabitRecordEntity.self,
            SyncStateEntity.self
        ])

        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = shouldUseICloudSync
            ? .private(iCloudContainerId)
            : .none

        let config: ModelConfiguration
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            let sqliteURL = groupURL.appendingPathComponent("default.store")
            config = ModelConfiguration(
                "DeadlinerModel",
                schema: schema,
                url: sqliteURL,
                cloudKitDatabase: cloudKitDatabase
            )
        } else {
            config = ModelConfiguration(
                "DeadlinerModel",
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .none,
                cloudKitDatabase: cloudKitDatabase
            )
        }

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}
