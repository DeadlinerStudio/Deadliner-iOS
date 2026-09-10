// KMP is the sole runtime persistence authority.

#if canImport(Shared)
/// Type-erases the category KMP actor without retaining a SwiftData fallback.
private actor KMPCategoryRuntimeStore: CategoryPersistenceStore {
    private func store() async -> KMPTaskCategoryStore {
        await KMPPersistenceRuntime.shared.categoryStore()
    }

    func allCategories() async throws -> [TaskCategory] { try await store().allCategories() }
    func category(uid: String) async throws -> TaskCategory? { try await store().category(uid: uid) }
    func createCategory(name: String, iconKey: String, colorHex: String) async throws -> TaskCategory {
        try await store().createCategory(name: name, iconKey: iconKey, colorHex: colorHex)
    }
    func updateCategory(_ category: TaskCategory) async throws { try await store().updateCategory(category) }
    func deleteCategory(uid: String) async throws { try await store().deleteCategory(uid: uid) }
    func restorePresets() async throws { try await store().restorePresets() }
}

enum PersistenceStores {
    static let tasks: any KMPTaskUIStore = KMPTaskPresentationStore()
    static let habits: any KMPHabitUIStore = KMPHabitPresentationStore()
    static let categories: any CategoryPersistenceStore = KMPCategoryRuntimeStore()
    static let captures: any CapturePersistenceStore = KMPSharedCaptureStore()
    static let memories: any MemoryPersistenceStore = KMPSharedMemoryStore()
}
#endif
