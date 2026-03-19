//
//  MemoryModels.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/22.
//

import Foundation
import Combine

struct MemoryFragment: Codable, Identifiable {
    var id = UUID()
    let content: String
    let category: String
    let timestamp: Date
    let importance: Int
}

final class MemoryBank: ObservableObject {
    static let shared = MemoryBank()

    @Published private(set) var fragments: [MemoryFragment] = []

    @Published private(set) var userProfile: String = ""
    @Published private(set) var revision: UInt64 = 0

    private let storageKey = "deadliner_local_memories"
    private let storageProfileKey = "deadliner_user_profile"
    private let storageRevisionKey = "deadliner_memory_revision"
    
    private let maxFragments = 60
    private let maxAgeDays = 120

    private init() {
        loadFromDisk()
        loadProfileFromDisk()
        loadRevisionFromDisk()
    }

    private func applyOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    func saveMemory(content: String, category: String = "Auto") {
        let newFrag = MemoryFragment(content: content, category: category, timestamp: Date(), importance: 3)
        guard !fragments.contains(where: { $0.content == content }) else { return }

        applyOnMain {
            self.fragments.append(newFrag)
            self.pruneMemories()
            self.bumpRevision()
            self.saveToDisk()
        }
    }

    func saveUserProfile(_ profile: String) {
        let trimmed = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        applyOnMain {
            self.userProfile = trimmed
            self.bumpRevision()
            self.saveProfileToDisk()
        }
    }
    
    func getLongTermContext(maxProfileChars: Int = 420, maxBullets: Int = 6, maxTotalChars: Int = 900) -> String {
        var parts: [String] = []

        let p = String(userProfile.prefix(maxProfileChars)).trimmingCharacters(in: .whitespacesAndNewlines)
        if !p.isEmpty {
            parts.append("【用户画像】\n\(p)")
        } else {
            parts.append("【用户画像】\n(暂无)")
        }

        if !fragments.isEmpty, maxBullets > 0 {
            let bullets = fragments.suffix(maxBullets).map { "- \($0.content)" }.joined(separator: "\n")
            parts.append("【近期用户偏好/事实】\n\(bullets)")
        }

        let joined = parts.joined(separator: "\n\n")
        return String(joined.prefix(maxTotalChars))
    }

    // MARK: - Local Persistence
    private func saveToDisk() {
        if let encoded = try? JSONEncoder().encode(fragments) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([MemoryFragment].self, from: data) {
            self.fragments = decoded
        }
    }

    private func saveProfileToDisk() {
        UserDefaults.standard.set(userProfile, forKey: storageProfileKey)
    }

    private func loadProfileFromDisk() {
        if let s = UserDefaults.standard.string(forKey: storageProfileKey) {
            self.userProfile = s
        }
    }

    private func saveRevisionToDisk() {
        UserDefaults.standard.set(revision, forKey: storageRevisionKey)
    }

    private func loadRevisionFromDisk() {
        self.revision = UInt64(UserDefaults.standard.integer(forKey: storageRevisionKey))
    }

    func clearAllMemories() {
        fragments.removeAll()
        userProfile = ""
        revision = 0
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: storageProfileKey)
        UserDefaults.standard.removeObject(forKey: storageRevisionKey)
    }
    
    // MARK: - Editing / Deleting

    func setUserProfileAllowEmpty(_ profile: String) {
        let trimmed = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        applyOnMain {
            self.userProfile = trimmed
            self.bumpRevision()
            self.saveProfileToDisk()
        }
    }

    func deleteFragment(id: UUID) {
        applyOnMain {
            self.fragments.removeAll { $0.id == id }
            self.bumpRevision()
            self.saveToDisk()
        }
    }

    func updateFragment(id: UUID, newContent: String, newCategory: String? = nil, newImportance: Int? = nil) {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        applyOnMain {
            guard let idx = self.fragments.firstIndex(where: { $0.id == id }) else { return }
            let old = self.fragments[idx]
            let updated = MemoryFragment(
                id: old.id,
                content: trimmed.isEmpty ? old.content : trimmed,
                category: newCategory ?? old.category,
                timestamp: old.timestamp,
                importance: newImportance ?? old.importance
            )
            self.fragments[idx] = updated
            self.bumpRevision()
            self.saveToDisk()
        }
    }

    func replaceAllFragments(_ newList: [MemoryFragment]) {
        applyOnMain {
            self.fragments = newList
            self.bumpRevision()
            self.saveToDisk()
        }
    }

    func exportSnapshotJson() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let snapshot = MemorySnapshotDTO(
            revision: revision,
            fragments: fragments,
            userProfile: userProfile
        )
        guard let data = try? encoder.encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"revision":0,"fragments":[],"userProfile":""}"#
        }
        return json
    }

    @discardableResult
    func applySnapshotJson(_ json: String) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = json.data(using: .utf8),
              let snapshot = try? decoder.decode(MemorySnapshotDTO.self, from: data) else {
            return false
        }

        if snapshot.revision < revision {
            return false
        }

        let applyState = {
            self.fragments = snapshot.fragments
            self.userProfile = snapshot.userProfile
            self.revision = snapshot.revision
            self.pruneMemories()
            self.saveToDisk()
            self.saveProfileToDisk()
            self.saveRevisionToDisk()
        }

        if Thread.isMainThread {
            applyState()
        } else {
            DispatchQueue.main.sync(execute: applyState)
        }

        return true
    }

    @discardableResult
    func applySyncPayloadJson(_ json: String) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = json.data(using: .utf8),
              let payload = try? decoder.decode(MemorySyncPayloadDTO.self, from: data),
              payload.baseRevision == revision else {
            return false
        }

        var updatedFragments = fragments
        var updatedProfile = userProfile

        for operation in payload.operations {
            switch operation {
            case .upsertFragment(let fragment):
                if let idx = updatedFragments.firstIndex(where: { $0.id == fragment.id }) {
                    updatedFragments[idx] = fragment
                } else {
                    updatedFragments.append(fragment)
                }
            case .deleteFragment(let fragmentID):
                updatedFragments.removeAll { $0.id == fragmentID }
            case .replaceUserProfile(let profile):
                updatedProfile = profile
            }
        }

        let applyState = {
            self.fragments = updatedFragments
            self.userProfile = updatedProfile
            self.revision = payload.nextRevision
            self.pruneMemories()
            self.saveToDisk()
            self.saveProfileToDisk()
            self.saveRevisionToDisk()
        }

        if Thread.isMainThread {
            applyState()
        } else {
            DispatchQueue.main.sync(execute: applyState)
        }

        return true
    }
    
    private func pruneMemories() {
        // 1) 先按时间过期淘汰
        let now = Date()
        let cutoff = now.addingTimeInterval(TimeInterval(-maxAgeDays) * 86400)
        fragments = fragments.filter { $0.timestamp >= cutoff }

        // 2) 超容量：优先删“低重要度 + 更旧”的
        if fragments.count > maxFragments {
            fragments.sort {
                if $0.importance != $1.importance { return $0.importance > $1.importance }
                return $0.timestamp > $1.timestamp
            }
            fragments = Array(fragments.prefix(maxFragments))
        }
    }

    private func bumpRevision() {
        revision += 1
        saveRevisionToDisk()
    }
}

private struct MemorySnapshotDTO: Codable {
    let revision: UInt64
    let fragments: [MemoryFragment]
    let userProfile: String
}

private struct MemorySyncPayloadDTO: Codable {
    let baseRevision: UInt64
    let nextRevision: UInt64
    let operations: [MemorySyncOperationDTO]
}

private enum MemorySyncOperationDTO: Codable {
    case upsertFragment(MemoryFragment)
    case deleteFragment(UUID)
    case replaceUserProfile(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case fragment
        case fragmentID
        case profile
    }

    private enum OperationType: String, Codable {
        case upsertFragment = "UpsertFragment"
        case deleteFragment = "DeleteFragment"
        case replaceUserProfile = "ReplaceUserProfile"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(OperationType.self, forKey: .type) {
        case .upsertFragment:
            self = .upsertFragment(try container.decode(MemoryFragment.self, forKey: .fragment))
        case .deleteFragment:
            self = .deleteFragment(try container.decode(UUID.self, forKey: .fragmentID))
        case .replaceUserProfile:
            self = .replaceUserProfile(try container.decode(String.self, forKey: .profile))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .upsertFragment(let fragment):
            try container.encode(OperationType.upsertFragment, forKey: .type)
            try container.encode(fragment, forKey: .fragment)
        case .deleteFragment(let fragmentID):
            try container.encode(OperationType.deleteFragment, forKey: .type)
            try container.encode(fragmentID, forKey: .fragmentID)
        case .replaceUserProfile(let profile):
            try container.encode(OperationType.replaceUserProfile, forKey: .type)
            try container.encode(profile, forKey: .profile)
        }
    }
}
