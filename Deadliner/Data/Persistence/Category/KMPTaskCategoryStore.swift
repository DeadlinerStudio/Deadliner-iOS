//
//  KMPTaskCategoryStore.swift
//  Deadliner
//
//  Category adapter backed by DeadlinerCore's SQLDelight store.
//

#if canImport(Shared)
import Foundation
import Shared

actor KMPTaskCategoryStore: CategoryPersistenceStore {
    private let database: DeadlinerDatabase

    init(database: DeadlinerDatabase) {
        self.database = database
    }

    func allCategories() async throws -> [TaskCategory] {
        database.categories.list()
            .filter { !$0.isDeleted }
            .map(TaskCategory.init)
            .sorted(by: Self.areInPresentationOrder)
    }

    func category(uid: String) async throws -> TaskCategory? {
        guard let category = database.categories.find(uid: uid), !category.isDeleted else {
            return nil
        }
        return TaskCategory(category)
    }

    func createCategory(name: String, iconKey: String, colorHex: String) async throws -> TaskCategory {
        let timestamp = Self.timestamp()
        let category = TaskCategory(
            uid: UUID().uuidString.lowercased(),
            name: name,
            iconKey: CategoryPresentationSupport.semanticIconKey(iconKey),
            colorHex: CategoryPresentationSupport.normalizedColorHex(colorHex),
            isPreset: false,
            sortOrder: nextSortOrder(),
            createdAt: timestamp,
            updatedAt: timestamp
        )
        database.categories.create(category: category.kmpValue)
        trace("create", uid: category.uid)
        await publishChange()
        return category
    }

    func updateCategory(_ category: TaskCategory) async throws {
        database.categories.update(category: category.kmpValue)
        trace("update", uid: category.uid)
        await publishChange()
    }

    func deleteCategory(uid: String) async throws {
        database.categories.softDelete(uid: uid, updatedAt: Self.timestamp())
        trace("delete", uid: uid)
        await publishChange()
    }

    func restorePresets() async throws {
        _ = database.categories.restorePresets()
        trace("restore_presets", uid: "all")
        await publishChange()
    }

    private func nextSortOrder() -> Int {
        let highestSortOrder = database.categories.list()
            .filter { !$0.isDeleted }
            .map { Int($0.sortOrder) }
            .max() ?? 0
        return highestSortOrder + 10
    }

    private func publishChange() async {
        await MainActor.run {
            PersistenceChangePublisher.publish(.init(resourceKinds: [.category]))
        }
    }

    private func trace(_ operation: String, uid: String) {
        AppLog.event(
            "persistence.category.\(operation)",
            domain: .persistence,
            context: ["uid": uid]
        )
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func areInPresentationOrder(_ lhs: TaskCategory, _ rhs: TaskCategory) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        return lhs.uid < rhs.uid
    }
}

private extension TaskCategory {
    init(_ category: Category_) {
        self.init(
            uid: category.uid,
            name: category.name,
            iconKey: CategoryPresentationSupport.semanticIconKey(category.iconKey),
            colorHex: CategoryPresentationSupport.normalizedColorHex(category.colorHex),
            isPreset: category.isPreset,
            sortOrder: Int(category.sortOrder),
            createdAt: category.createdAt,
            updatedAt: category.updatedAt
        )
    }

    var kmpValue: Category_ {
        Category_(
            uid: uid,
            name: name,
            iconKey: CategoryPresentationSupport.semanticIconKey(iconKey),
            colorHex: CategoryPresentationSupport.normalizedColorHex(colorHex),
            isPreset: isPreset,
            sortOrder: Int32(sortOrder),
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: false
        )
    }
}
#endif
