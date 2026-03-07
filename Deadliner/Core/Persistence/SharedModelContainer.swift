//
//  SharedModelContainer.swift
//  Deadliner
//

import SwiftData
import Foundation

public enum SharedModelContainer {
    public static let appGroupId = "group.com.aritx.deadliner" // ⚠️ 请确保在 Xcode 中添加了此 App Group

    public static let shared: ModelContainer = {
        let schema = Schema([
            DDLItemEntity.self,
            SubTaskEntity.self,
            HabitEntity.self,
            HabitRecordEntity.self,
            SyncStateEntity.self
        ])
        
        // 尝试使用 App Group 共享路径
        let config: ModelConfiguration
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            let sqliteURL = groupURL.appendingPathComponent("default.store")
            config = ModelConfiguration(schema: schema, url: sqliteURL)
        } else {
            // Fallback to default
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}
