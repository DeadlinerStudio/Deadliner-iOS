//
//  CreateInspirationIntent.swift
//  Deadliner
//
//  Creates an inspiration from Shortcuts, Siri, or Spotlight without opening
//  the app UI. This file intentionally belongs only to the main app target.
//

import AppIntents
import Foundation

struct CreateInspirationIntent: AppIntent {
    static let title: LocalizedStringResource = "创建灵感"
    static let description = IntentDescription("把一段文字保存到 Deadliner 灵感箱。")
    static let openAppWhenRun = false

    @Parameter(
        title: "灵感内容",
        description: "要保存到 Deadliner 的想法。",
        requestValueDialog: "想到什么了？"
    )
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("将 \(\.$text) 保存为灵感")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let normalizedText = InspirationCaptureText.normalized(text) else {
            return .result(dialog: "灵感内容不能为空。")
        }

        do {
            try KMPSharedDatabaseBootstrap.prepareIfNeeded()
            try await PersistenceStores.captures.createCapture(
                CaptureInboxItem(text: normalizedText)
            )
            return .result(dialog: "已保存到 Deadliner 灵感。")
        } catch {
            return .result(dialog: "保存灵感失败：\(error.localizedDescription)")
        }
    }
}
