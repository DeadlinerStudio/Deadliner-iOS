//
//  SyncDebugLog.swift
//  Deadliner
//

import Foundation

actor SyncDebugLog {
    static let shared = SyncDebugLog()

    private let fileName = "deadliner-sync.log"
    private let maxFileBytes = 512 * 1024
    private let keepFileBytes = 256 * 1024
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private init() {}

    static func log(_ message: String) {
        Task {
            await SyncDebugLog.shared.append(message)
        }
    }

    static func exportURL() async -> URL {
        await SyncDebugLog.shared.fileURL()
    }

    static func clear() async throws {
        try await SyncDebugLog.shared.truncate()
    }

    static func clearForNewLaunchSession() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("deadliner-sync.log")
        try? Data().write(to: url, options: .atomic)
    }

    private func fileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    private func append(_ message: String) {
        let line = "[\(isoFormatter.string(from: Date()))] \(message)\n"
        let data = Data(line.utf8)
        let url = fileURL()

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: data)
            return
        }

        do {
            pruneIfNeeded(url)
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Ignore file logging failures so they don't affect app behavior.
        }
    }

    private func pruneIfNeeded(_ url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? NSNumber else {
            return
        }
        guard fileSize.intValue > maxFileBytes else { return }

        do {
            let data = try Data(contentsOf: url)
            let keep = min(keepFileBytes, data.count)
            let tail = data.suffix(keep)
            try Data(tail).write(to: url, options: .atomic)
        } catch {
            // Keep best-effort behavior for logging path.
        }
    }

    private func truncate() throws {
        try Data().write(to: fileURL(), options: .atomic)
    }
}

actor AILog {
    static let shared = AILog()

    private let fileName = "deadliner-ai.log"
    private let maxFileBytes = 1024 * 1024
    private let keepFileBytes = 512 * 1024
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private init() {}

    static func log(_ message: String) {
        Task {
            await AILog.shared.append(message)
        }
    }

    static func exportURL() async -> URL {
        await AILog.shared.fileURL()
    }

    static func clear() async throws {
        try await AILog.shared.truncate()
    }

    static func clearForNewLaunchSession() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("deadliner-ai.log")
        try? Data().write(to: url, options: .atomic)
    }

    private func fileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    private func append(_ message: String) {
        let line = "[\(isoFormatter.string(from: Date()))] \(message)\n"
        let data = Data(line.utf8)
        let url = fileURL()

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: data)
            return
        }

        do {
            pruneIfNeeded(url)
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Ignore logging failures so they don't affect app behavior.
        }
    }

    private func pruneIfNeeded(_ url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? NSNumber else {
            return
        }
        guard fileSize.intValue > maxFileBytes else { return }

        do {
            let data = try Data(contentsOf: url)
            let keep = min(keepFileBytes, data.count)
            let tail = data.suffix(keep)
            try Data(tail).write(to: url, options: .atomic)
        } catch {
            // Keep best-effort behavior for logging path.
        }
    }

    private func truncate() throws {
        try Data().write(to: fileURL(), options: .atomic)
    }
}

actor IconDebugLog {
    static let shared = IconDebugLog()

    private let fileName = "deadliner-icon.log"
    private let maxFileBytes = 256 * 1024
    private let keepFileBytes = 128 * 1024
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private init() {}

    static func log(_ message: String) {
        Task {
            await IconDebugLog.shared.append(message)
        }
    }

    static func exportURL() async -> URL {
        await IconDebugLog.shared.fileURL()
    }

    static func clear() async throws {
        try await IconDebugLog.shared.truncate()
    }

    static func clearForNewLaunchSession() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("deadliner-icon.log")
        try? Data().write(to: url, options: .atomic)
    }

    private func fileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    private func append(_ message: String) {
        let line = "[\(isoFormatter.string(from: Date()))] \(message)\n"
        let data = Data(line.utf8)
        let url = fileURL()

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: data)
            return
        }

        do {
            pruneIfNeeded(url)
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Ignore file logging failures so they don't affect app behavior.
        }
    }

    private func pruneIfNeeded(_ url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? NSNumber else {
            return
        }
        guard fileSize.intValue > maxFileBytes else { return }

        do {
            let data = try Data(contentsOf: url)
            let keep = min(keepFileBytes, data.count)
            let tail = data.suffix(keep)
            try Data(tail).write(to: url, options: .atomic)
        } catch {
            // Keep best-effort behavior for logging path.
        }
    }

    private func truncate() throws {
        try Data().write(to: fileURL(), options: .atomic)
    }
}
