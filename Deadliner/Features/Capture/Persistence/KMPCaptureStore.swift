//
//  KMPCaptureStore.swift
//  Deadliner
//
//  KMP-backed Capture persistence. SwiftUI UUIDs remain presentation-only;
//  KMP `uid` is the persistence and sync identity.
//

#if canImport(Shared)
import Foundation
import Shared

actor KMPCaptureStore: CapturePersistenceStore {
    private let database: DeadlinerDatabase

    init(database: DeadlinerDatabase) {
        self.database = database
    }

    func unconsumedItems() async throws -> [CaptureInboxItem] {
        database.captures.listUnconsumed()
            .filter { !$0.isDeleted }
            .compactMap(CaptureInboxItem.init(kmpValue:))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func createCapture(_ item: CaptureInboxItem) async throws {
        database.captures.create(item: item.kmpValue)
        trace("create", uid: item.uid)
        await publishChange()
    }

    func updateCapture(_ item: CaptureInboxItem) async throws {
        database.captures.update(item: item.kmpValue)
        trace("update", uid: item.uid)
        await publishChange()
    }

    func deleteCapture(uid: String, updatedAt: Date) async throws {
        database.captures.delete(uid: uid, updatedAt: updatedAt.toLocalISOString())
        trace("delete", uid: uid)
        await publishChange()
    }

    func importLegacyCaptures(_ items: [CaptureInboxItem]) async throws {
        for item in items {
            if database.captures.find(uid: item.uid) == nil {
                database.captures.create(item: item.kmpValue)
            }
        }
        if !items.isEmpty {
            AppLog.event(
                "persistence.capture.import",
                domain: .persistence,
                context: ["count": "\(items.count)"]
            )
            await publishChange()
        }
    }

    private func publishChange() async {
        await MainActor.run {
            PersistenceChangePublisher.publish(.init(resourceKinds: [.capture]))
        }
    }

    private func trace(_ operation: String, uid: String) {
        AppLog.event(
            "persistence.capture.\(operation)",
            domain: .persistence,
            context: ["uid": uid]
        )
    }
}

actor KMPSharedCaptureStore: CapturePersistenceStore {
    private func store() async -> KMPCaptureStore {
        await KMPPersistenceRuntime.shared.captureStore()
    }

    func unconsumedItems() async throws -> [CaptureInboxItem] {
        let captureStore = await store()
        return try await captureStore.unconsumedItems()
    }

    func createCapture(_ item: CaptureInboxItem) async throws {
        let captureStore = await store()
        try await captureStore.createCapture(item)
    }

    func updateCapture(_ item: CaptureInboxItem) async throws {
        let captureStore = await store()
        try await captureStore.updateCapture(item)
    }

    func deleteCapture(uid: String, updatedAt: Date) async throws {
        let captureStore = await store()
        try await captureStore.deleteCapture(uid: uid, updatedAt: updatedAt)
    }

    func importLegacyCaptures(_ items: [CaptureInboxItem]) async throws {
        let captureStore = await store()
        try await captureStore.importLegacyCaptures(items)
    }
}

private extension CaptureInboxItem {
    init?(kmpValue: Shared.CaptureItem) {
        guard let createdAt = Date(kmpISO8601: kmpValue.createdAt),
              let updatedAt = Date(kmpISO8601: kmpValue.updatedAt) else {
            return nil
        }
        self.init(uid: kmpValue.uid, text: kmpValue.text, createdAt: createdAt, updatedAt: updatedAt)
    }

    var kmpValue: Shared.CaptureItem {
        Shared.CaptureItem(
            uid: uid,
            text: text,
            source: .manual,
            createdAt: createdAt.toLocalISOString(),
            updatedAt: updatedAt.toLocalISOString(),
            isConsumed: false,
            isDeleted: false
        )
    }
}

private extension Date {
    init?(kmpISO8601 value: String) {
        if let date = ISO8601DateFormatter().date(from: value) {
            self = date
            return
        }
        // SwiftData-era captures were saved as local wall-clock time without an offset.
        // Preserve that meaning while importing them into the KMP-backed inbox.
        guard let date = DateFormatter.kmpLegacyLocalDateTime.date(from: value) else { return nil }
        self = date
    }
}

private extension DateFormatter {
    static let kmpLegacyLocalDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}
#endif
