//
//  CaptureStore.swift
//  Deadliner
//
//  Created by Codex on 2026/4/5.
//

import Combine
import Foundation

@MainActor
final class CaptureStore: ObservableObject {
    static let shared = CaptureStore()

    @Published private(set) var items: [CaptureInboxItem] = []

    private let storageKey = "capture.inbox.items"
    // v3 replays the idempotent merge for upgrades previously marked complete
    // before the legacy defaults reader was repaired. Existing KMP captures
    // are preserved because the importer only creates missing UIDs.
    private let migrationKey = "persistence.kmp.capture-import-v3"
    private let decoder = JSONDecoder()
    private var bootstrapTask: _Concurrency.Task<Void, Never>?

    init() {
        let shouldImportLegacy = !UserDefaults.standard.bool(forKey: migrationKey)
        let legacySnapshot = Self.loadLegacyItems(storageKey: storageKey, decoder: decoder)
        let legacyItems = shouldImportLegacy ? legacySnapshot : []
        SyncDebugLog.log(
            "[KMP][Capture] bootstrap marker=\(shouldImportLegacy ? "missing" : "present") "
                + "legacyItems=\(legacySnapshot.count) importItems=\(legacyItems.count)"
        )
        bootstrapTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                let beforeImport = try await PersistenceStores.captures.unconsumedItems().count
                try await PersistenceStores.captures.importLegacyCaptures(legacyItems)
                let afterImport = try await PersistenceStores.captures.unconsumedItems().count
                SyncDebugLog.log(
                    "[KMP][Capture] legacy import source=\(legacyItems.count) "
                        + "before=\(beforeImport) after=\(afterImport)"
                )
                if shouldImportLegacy {
                    UserDefaults.standard.set(true, forKey: migrationKey)
                }
                await reload()
                // The Watch bridge may have created its first snapshot before
                // this asynchronous KMP read completed. Publish only after the
                // in-memory projection is ready so it sends the loaded ideas.
                PersistenceChangePublisher.publish(.init(resourceKinds: [.capture]))
            } catch {
                print("CaptureStore KMP bootstrap failed: \(error)")
            }
        }
    }

    /// Used at launch so an upgraded installation repairs its capture data
    /// before a Watch or a lazily-created inspiration tab reads an empty list.
    func ensureKMPMigration() async {
        await bootstrapTask?.value
    }

    func addItem(text: String) {
        guard let trimmed = InspirationCaptureText.normalized(text) else { return }

        let item = CaptureInboxItem(text: trimmed)
        items.insert(item, at: 0)
        persistCreate(item)
    }

    func updateItem(id: UUID, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        items[index].text = trimmed
        items[index].updatedAt = Date()
        persistUpdate(items[index])
    }

    func deleteItem(uid: String) {
        items.removeAll { $0.uid == uid }
        persistDelete(uid: uid)
    }

    func deleteItems(uids: Set<String>) {
        guard !uids.isEmpty else { return }
        items.removeAll { uids.contains($0.uid) }
        for uid in uids {
            persistDelete(uid: uid)
        }
    }

    func consumeItem(uid: String) {
        deleteItem(uid: uid)
    }

    func consumeItems(uids: Set<String>) {
        deleteItems(uids: uids)
    }

    func reload() async {
        do {
            items = try await PersistenceStores.captures.unconsumedItems()
            SyncDebugLog.log("[KMP][Capture] reload items=\(items.count)")
        } catch {
            SyncDebugLog.log("[KMP][Capture] reload failed: \(error.localizedDescription)")
            print("CaptureStore KMP reload failed: \(error)")
        }
    }

    private func persistCreate(_ item: CaptureInboxItem) {
        Task {
            do {
                try await PersistenceStores.captures.createCapture(item)
            } catch {
                print("CaptureStore KMP create failed: \(error)")
                await reload()
            }
        }
    }

    private func persistUpdate(_ item: CaptureInboxItem) {
        Task {
            do {
                try await PersistenceStores.captures.updateCapture(item)
            } catch {
                print("CaptureStore KMP update failed: \(error)")
                await reload()
            }
        }
    }

    private func persistDelete(uid: String) {
        Task {
            do {
                try await PersistenceStores.captures.deleteCapture(uid: uid, updatedAt: Date())
            } catch {
                print("CaptureStore KMP delete failed: \(error)")
                await reload()
            }
        }
    }

    private static func loadLegacyItems(storageKey: String, decoder: JSONDecoder) -> [CaptureInboxItem] {
        let stores = [
            UserDefaults(suiteName: KMPSharedDatabaseLocation.appGroupID),
            UserDefaults.standard,
        ]

        var itemsByUID: [String: CaptureInboxItem] = [:]
        for defaults in stores {
            guard let data = defaults?.data(forKey: storageKey),
                  let items = try? decoder.decode([CaptureInboxItem].self, from: data) else {
                continue
            }
            for item in items {
                guard let existing = itemsByUID[item.uid] else {
                    itemsByUID[item.uid] = item
                    continue
                }
                if item.updatedAt > existing.updatedAt {
                    itemsByUID[item.uid] = item
                }
            }
        }
        return itemsByUID.values.sorted { $0.updatedAt > $1.updatedAt }
    }
}
