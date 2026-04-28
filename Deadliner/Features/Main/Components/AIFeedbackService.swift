//
//  AIFeedbackService.swift
//  Deadliner
//

import Foundation

enum AIFeedbackService {
    struct Context {
        let appVersion: String
        let buildNumber: String
        let timestamp: String
        let timezone: String
        let locale: String
        let lastCoreEventSummary: String
        let sessionSummary: String
        let memoryFragmentsCount: Int
        let memoryProfile: String
        let transcriptLines: [String]
        let coreLastFinishJson: String?
        let coreLastMemorySyncJson: String?
    }

    static func makeShareItems(context: Context) async -> [Any] {
        var items: [Any] = []

        if let reportURL = await writeReportFile(context: context) {
            items.append(reportURL)
        }

        let aiLogURL = await AILog.exportURL()
        if FileManager.default.fileExists(atPath: aiLogURL.path) {
            items.append(aiLogURL)
        }

        let syncLogURL = await SyncDebugLog.exportURL()
        if FileManager.default.fileExists(atPath: syncLogURL.path) {
            items.append(syncLogURL)
        }

        if items.isEmpty {
            items.append("Deadliner AI Feedback")
        }
        return items
    }

    private static func writeReportFile(context: Context) async -> URL? {
        let aiLogSnippet = await readAILogTail(maxChars: 12000)
        let report = buildReport(context: context, aiLogSnippet: aiLogSnippet)
        let fileName = "deadliner-ai-feedback-\(safeFileDate()).txt"

        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent(fileName)
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func buildReport(context: Context, aiLogSnippet: String) -> String {
        let memoryProfile = context.memoryProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = context.transcriptLines.joined(separator: "\n")
        let finishJson = (context.coreLastFinishJson?.isEmpty == false) ? context.coreLastFinishJson! : "(empty)"
        let memoryJson = (context.coreLastMemorySyncJson?.isEmpty == false) ? context.coreLastMemorySyncJson! : "(empty)"

        return """
        Deadliner AI Feedback Report

        AppVersion: \(context.appVersion) (\(context.buildNumber))
        Timestamp: \(context.timestamp)
        Timezone: \(context.timezone)
        Locale: \(context.locale)

        LastCoreEvent: \(context.lastCoreEventSummary)
        SessionSummary: \(context.sessionSummary)

        MemoryFragmentsCount: \(context.memoryFragmentsCount)
        MemoryProfile: \(memoryProfile.isEmpty ? "(empty)" : memoryProfile)

        CoreLastFinishJson:
        \(finishJson)

        CoreLastMemorySyncJson:
        \(memoryJson)

        AILogTail:
        \(aiLogSnippet.isEmpty ? "(empty)" : aiLogSnippet)

        RecentTranscript:
        \(lines.isEmpty ? "(empty)" : lines)
        """
    }

    private static func readAILogTail(maxChars: Int) async -> String {
        let url = await AILog.exportURL()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        if content.count <= maxChars {
            return content
        }
        let tail = content.suffix(maxChars)
        return String(tail)
    }

    private static func safeFileDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
