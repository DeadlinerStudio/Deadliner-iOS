//
//  MemoryModels.swift
//  Deadliner
//
//  KMP is the runtime authority for AI memory and profile data. UserDefaults
//  is read only once here to import installations created before the cutover.
//

import Combine
import Foundation
#if canImport(Shared)
import Shared
#endif

struct MemoryFragment: Codable, Identifiable {
    var id = UUID()
    let content: String
    let category: String
    let timestamp: Date
    let importance: Int
}

@MainActor
final class MemoryBank: ObservableObject {
    static let shared = MemoryBank()

    @Published private(set) var fragments: [MemoryFragment] = []
    @Published private(set) var userProfile = ""

    private let legacyFragmentsKey = "deadliner_local_memories"
    private let legacyProfileKey = "deadliner_user_profile"
    // v4 repeats the idempotent merge for devices marked complete before all
    // legacy defaults and Rust snapshot sources were reliably read. Existing
    // KMP fragments are preserved because imports are UID-based.
    private let migrationKey = "persistence.kmp.lifi-memory-import-v4"

    private init() {
        _Concurrency.Task { await bootstrap() }
    }

    func refresh() async {
        do {
            let persisted = try await PersistenceStores.memories.fragments()
            fragments = persisted.sorted { $0.timestamp > $1.timestamp }
            let database = await KMPPersistenceRuntime.shared.coreDatabase()
            userProfile = database.memory.getUserProfile()
        } catch {
            AILog.log("[KMP] Memory refresh failed: \(error.localizedDescription)")
        }
    }

    /// Ensures old local data is imported exactly once before KMP LiFi starts.
    func ensureKMPMemoryMigration() async {
        await bootstrap()
    }

    func saveMemory(content: String, category: String = "Auto") {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !fragments.contains(where: { $0.content == trimmed }) else { return }
        let fragment = MemoryFragment(content: trimmed, category: category, timestamp: Date(), importance: 3)
        fragments.append(fragment)
        _Concurrency.Task {
            do { try await PersistenceStores.memories.createMemory(fragment) }
            catch { await self.refresh() }
        }
    }

    func setUserProfileAllowEmpty(_ profile: String) {
        let trimmed = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        userProfile = trimmed
        _Concurrency.Task {
            let database = await KMPPersistenceRuntime.shared.coreDatabase()
            database.memory.updateUserProfile(profile: trimmed)
        }
    }

    func saveUserProfile(_ profile: String) {
        guard !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        setUserProfileAllowEmpty(profile)
    }

    /// Compatibility context for the still-local editor extraction helper.
    /// It reads only the KMP-backed projection held for SwiftUI; LiFi itself
    /// never consumes this value.
    func getLongTermContext(maxProfileChars: Int = 420, maxBullets: Int = 6, maxTotalChars: Int = 900) -> String {
        let profile = String(userProfile.prefix(maxProfileChars))
        let bullets = fragments.prefix(maxBullets).map { "- \($0.content)" }.joined(separator: "\n")
        let profileText = profile.isEmpty ? "(暂无)" : profile
        let context = "【用户画像】\n\(profileText)\n\n【近期用户偏好/事实】\n\(bullets)"
        return String(context.prefix(maxTotalChars))
    }

    func deleteFragment(id: UUID) {
        guard let fragment = fragments.first(where: { $0.id == id }) else { return }
        fragments.removeAll { $0.id == id }
        _Concurrency.Task {
            do { try await PersistenceStores.memories.deleteMemory(uid: fragment.id.uuidString, updatedAt: Date()) }
            catch { await self.refresh() }
        }
    }

    func upsertFragment(_ fragment: MemoryFragment) {
        if let index = fragments.firstIndex(where: { $0.id == fragment.id }) {
            fragments[index] = fragment
            _Concurrency.Task {
                do { try await PersistenceStores.memories.updateMemory(fragment) }
                catch { await self.refresh() }
            }
        } else {
            fragments.append(fragment)
            _Concurrency.Task {
                do { try await PersistenceStores.memories.createMemory(fragment) }
                catch { await self.refresh() }
            }
        }
    }

    func clearAllMemories() {
        let existing = fragments
        fragments.removeAll()
        userProfile = ""
        _Concurrency.Task {
            do {
                for fragment in existing {
                    try await PersistenceStores.memories.deleteMemory(uid: fragment.id.uuidString, updatedAt: Date())
                }
                let database = await KMPPersistenceRuntime.shared.coreDatabase()
                database.memory.updateUserProfile(profile: "")
            } catch {
                await self.refresh()
            }
        }
    }

    /// Updates the SwiftUI projection after a KMP callback. No snapshot is
    /// written back: the KMP LiFi adapter has already persisted the change.
    func applyKMPCommittedResult(addedMemories: [String], updatedProfile: String?, newRevision _: UInt64) {
        for content in addedMemories where !fragments.contains(where: { $0.content == content }) {
            fragments.append(MemoryFragment(content: content, category: "Auto", timestamp: Date(), importance: 3))
        }
        if let updatedProfile { userProfile = updatedProfile }
        _Concurrency.Task { await refresh() }
    }

    private func bootstrap() async {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            await refresh()
            return
        }

        let legacySnapshot = loadLegacySnapshot()

        do {
            let beforeImport = (try await PersistenceStores.memories.fragments()).count
            try await PersistenceStores.memories.importLegacyMemories(legacySnapshot.fragments)
            let database = await KMPPersistenceRuntime.shared.coreDatabase()
            let importedProfile: Bool
            if database.memory.getUserProfile().isEmpty,
               !legacySnapshot.profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                database.memory.updateUserProfile(profile: legacySnapshot.profile)
                importedProfile = true
            } else {
                importedProfile = false
            }
            let afterImport = (try await PersistenceStores.memories.fragments()).count
            AILog.log(
                "[KMP] Legacy memory import source=\(legacySnapshot.fragments.count) "
                    + "before=\(beforeImport) after=\(afterImport) profileImported=\(importedProfile)"
            )
            UserDefaults.standard.set(true, forKey: migrationKey)
            await refresh()
        } catch {
            AILog.log("[KMP] Legacy memory import failed: \(error.localizedDescription)")
        }
    }

    /// The pre-KMP app wrote MemoryBank to standard defaults. During the Rust
    /// LiFi period the same snapshot was also persisted under DeadlinerAI, so
    /// an upgrade must merge both sources rather than assuming one is current.
    private func loadLegacySnapshot() -> (fragments: [MemoryFragment], profile: String) {
        let defaults = [
            UserDefaults.standard,
            UserDefaults(suiteName: KMPSharedDatabaseLocation.appGroupID),
        ].compactMap { $0 }

        var fragments: [MemoryFragment] = []
        var knownIDs = Set<UUID>()
        var knownContents = Set<String>()
        var profiles: [String] = []

        func append(_ candidates: [MemoryFragment]) {
            for fragment in candidates {
                let content = fragment.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty,
                      knownIDs.insert(fragment.id).inserted,
                      knownContents.insert(content).inserted else {
                    continue
                }
                fragments.append(fragment)
            }
        }

        for store in defaults {
            if let data = store.data(forKey: legacyFragmentsKey) {
                append(Self.decodeLegacyFragments(from: data))
            }
            if let profile = store.string(forKey: legacyProfileKey),
               !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profiles.append(profile)
            }
        }

        for url in Self.legacyRustMemoryURLs() {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = Self.decodeLegacyRustSnapshot(from: data) else {
                continue
            }
            append(snapshot.fragments)
            if let profile = snapshot.profile,
               !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profiles.append(profile)
            }
        }

        AILog.log("[KMP] Legacy memory sources fragments=\(fragments.count) profiles=\(profiles.count)")
        return (fragments, profiles.first ?? "")
    }

    private static func decodeLegacyFragments(from data: Data) -> [MemoryFragment] {
        for decoder in legacyMemoryDecoders() {
            if let fragments = try? decoder.decode([MemoryFragment].self, from: data) {
                return fragments
            }
        }
        return []
    }

    private static func decodeLegacyRustSnapshot(from data: Data) -> LegacyRustMemorySnapshot? {
        for decoder in legacyMemoryDecoders() {
            if let snapshot = try? decoder.decode(LegacyRustMemorySnapshot.self, from: data) {
                return snapshot
            }
        }
        return nil
    }

    private static func legacyMemoryDecoders() -> [JSONDecoder] {
        let defaultsDecoder = JSONDecoder()
        let iso8601Decoder = JSONDecoder()
        iso8601Decoder.dateDecodingStrategy = .iso8601
        return [defaultsDecoder, iso8601Decoder]
    }

    private static func legacyRustMemoryURLs() -> [URL] {
        let fileManager = FileManager.default
        let roots = [
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
        ].compactMap { $0 }
        return roots.map { $0.appendingPathComponent("DeadlinerAI/memories.json") }
    }
}

private struct LegacyRustMemorySnapshot: Decodable {
    let fragments: [MemoryFragment]
    let profile: String?

    private enum CodingKeys: String, CodingKey {
        case fragments
        case userProfile
        case user_profile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fragments = try container.decodeIfPresent([MemoryFragment].self, forKey: .fragments) ?? []
        let camelCaseProfile = try container.decodeIfPresent(String.self, forKey: .userProfile)
        let snakeCaseProfile = try container.decodeIfPresent(String.self, forKey: .user_profile)
        profile = camelCaseProfile ?? snakeCaseProfile
    }
}
