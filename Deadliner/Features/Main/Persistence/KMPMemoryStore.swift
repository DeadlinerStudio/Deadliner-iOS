//
//  KMPMemoryStore.swift
//  Deadliner
//
//  KMP-backed memory fragment persistence.
//

#if canImport(Shared)
import Foundation
import Shared

actor KMPMemoryStore: MemoryPersistenceStore {
    private let database: DeadlinerDatabase

    init(database: DeadlinerDatabase) {
        self.database = database
    }

    func fragments() async throws -> [MemoryFragment] {
        database.memory.list()
            .filter { !$0.isDeleted }
            .compactMap(MemoryFragment.init(kmpValue:))
            .sorted { $0.timestamp > $1.timestamp }
    }

    func createMemory(_ fragment: MemoryFragment) async throws {
        database.memory.create(fragment: fragment.kmpValue)
        trace("create", uid: fragment.id.uuidString)
        await publishChange()
    }

    func updateMemory(_ fragment: MemoryFragment) async throws {
        database.memory.update(fragment: fragment.kmpValue)
        trace("update", uid: fragment.id.uuidString)
        await publishChange()
    }

    func deleteMemory(uid: String, updatedAt: Date) async throws {
        database.memory.delete(uid: uid, updatedAt: updatedAt.toLocalISOString())
        trace("delete", uid: uid)
        await publishChange()
    }

    func importLegacyMemories(_ fragments: [MemoryFragment]) async throws {
        for fragment in fragments {
            if database.memory.find(uid: fragment.id.uuidString) == nil {
                database.memory.create(fragment: fragment.kmpValue)
            }
        }
        if !fragments.isEmpty {
            AppLog.event(
                "persistence.memory.import",
                domain: .persistence,
                context: ["count": "\(fragments.count)"]
            )
            await publishChange()
        }
    }

    private func publishChange() async {
        await MainActor.run {
            PersistenceChangePublisher.publish(.init(resourceKinds: [.memory]))
        }
    }

    private func trace(_ operation: String, uid: String) {
        AppLog.event(
            "persistence.memory.\(operation)",
            domain: .persistence,
            context: ["uid": uid]
        )
    }
}

actor KMPSharedMemoryStore: MemoryPersistenceStore {
    private func store() async -> KMPMemoryStore {
        await KMPPersistenceRuntime.shared.memoryStore()
    }

    func fragments() async throws -> [MemoryFragment] {
        let memoryStore = await store()
        return try await memoryStore.fragments()
    }

    func createMemory(_ fragment: MemoryFragment) async throws {
        let memoryStore = await store()
        try await memoryStore.createMemory(fragment)
    }

    func updateMemory(_ fragment: MemoryFragment) async throws {
        let memoryStore = await store()
        try await memoryStore.updateMemory(fragment)
    }

    func deleteMemory(uid: String, updatedAt: Date) async throws {
        let memoryStore = await store()
        try await memoryStore.deleteMemory(uid: uid, updatedAt: updatedAt)
    }

    func importLegacyMemories(_ fragments: [MemoryFragment]) async throws {
        let memoryStore = await store()
        try await memoryStore.importLegacyMemories(fragments)
    }
}

private extension MemoryFragment {
    init?(kmpValue: Shared.MemoryFragment) {
        guard let timestamp = ISO8601DateFormatter().date(from: kmpValue.createdAt),
              let id = UUID(uuidString: kmpValue.uid) else { return nil }
        self.init(
            id: id,
            content: kmpValue.content,
            category: kmpValue.category,
            timestamp: timestamp,
            importance: Int(kmpValue.importance)
        )
    }

    var kmpValue: Shared.MemoryFragment {
        Shared.MemoryFragment(
            uid: id.uuidString,
            content: content,
            category: category,
            createdAt: timestamp.toLocalISOString(),
            importance: Int32(importance),
            updatedAt: timestamp.toLocalISOString(),
            isDeleted: false
        )
    }
}
#endif
