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

    private static func makeConfiguration(
        schema: Schema,
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase,
        isStoredInMemoryOnly: Bool = false
    ) -> ModelConfiguration {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            let sqliteURL = groupURL.appendingPathComponent("default.store")
            return ModelConfiguration(
                "DeadlinerModel",
                schema: schema,
                url: sqliteURL,
                cloudKitDatabase: cloudKitDatabase
            )
        }

        return ModelConfiguration(
            "DeadlinerModel",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            groupContainer: .none,
            cloudKitDatabase: cloudKitDatabase
        )
    }

    public static let shared: ModelContainer = {
        let schema = Schema([
            DDLItemEntity.self,
            SubTaskEntity.self,
            HabitEntity.self,
            HabitRecordEntity.self,
            SyncStateEntity.self
        ])

        let useICloudSync = shouldUseICloudSync
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = useICloudSync
            ? .private(iCloudContainerId)
            : .none

        do {
            let config = makeConfiguration(schema: schema, cloudKitDatabase: cloudKitDatabase)
            return try ModelContainer(for: schema, configurations: [config])
        } catch let firstError {
            NSLog("[SharedModelContainer] Primary container init failed. useICloudSync=%{public}@, error=%{public}@",
                  useICloudSync ? "true" : "false",
                  String(describing: firstError))

            if useICloudSync {
                do {
                    let fallbackConfig = makeConfiguration(schema: schema, cloudKitDatabase: .none)
                    let fallback = try ModelContainer(for: schema, configurations: [fallbackConfig])
                    UserDefaults.standard.set("webdav", forKey: syncProviderKey)
                    UserDefaults.standard.set(false, forKey: cloudSyncEnabledKey)
                    NSLog("[SharedModelContainer] Fallback to local store succeeded; iCloud sync disabled.")
                    return fallback
                } catch let fallbackError {
                    NSLog("[SharedModelContainer] Local fallback init failed. error=%{public}@",
                          String(describing: fallbackError))
                }
            }

            do {
                let memoryConfig = makeConfiguration(
                    schema: schema,
                    cloudKitDatabase: .none,
                    isStoredInMemoryOnly: true
                )
                NSLog("[SharedModelContainer] Falling back to in-memory store.")
                return try ModelContainer(for: schema, configurations: [memoryConfig])
            } catch let memoryError {
                fatalError("Could not create any ModelContainer. firstError=\(firstError), memoryError=\(memoryError)")
            }
        }
    }()
}
