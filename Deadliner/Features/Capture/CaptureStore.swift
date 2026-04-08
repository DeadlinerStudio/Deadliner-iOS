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
    @Published private(set) var items: [CaptureInboxItem] = []

    private let defaults: UserDefaults
    private let storageKey = "capture.inbox.items"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func addItem(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        items.insert(CaptureInboxItem(text: trimmed), at: 0)
        persist()
    }

    func updateItem(id: UUID, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        items[index].text = trimmed
        items[index].updatedAt = Date()
        persist()
    }

    func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func deleteItems(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        persist()
    }

    func consumeItem(id: UUID) {
        deleteItem(id: id)
    }

    func consumeItems(ids: Set<UUID>) {
        deleteItems(ids: ids)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else {
            items = []
            return
        }

        do {
            items = try decoder.decode([CaptureInboxItem].self, from: data)
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            items = []
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(items)
            defaults.set(data, forKey: storageKey)
        } catch {
            print("CaptureStore persist failed: \(error)")
        }
    }
}
