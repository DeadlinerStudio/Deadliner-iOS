//
//  SyncDebugLog.swift
//  Deadliner
//

import Foundation

actor SyncDebugLog {
    static let shared = SyncDebugLog()

    private let fileName = "deadliner-sync.log"
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
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Ignore file logging failures so they don't affect app behavior.
        }
    }

    private func truncate() throws {
        try Data().write(to: fileURL(), options: .atomic)
    }
}
