//
//  LocalValues.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import Foundation

enum SyncProvider: String, CaseIterable, Sendable {
    case webDAV = "webdav"
    case iCloud = "icloud"

    var displayName: String {
        switch self {
        case .webDAV:
            return "WebDAV"
        case .iCloud:
            return "iCloud"
        }
    }
}

actor LocalValues {
    static let shared = LocalValues()

    private let defaults = UserDefaults.standard

    private init() {
        registerDefaults()
    }

    // MARK: - Keys

    private enum Key {
        static let cloudSyncEnabled = "settings.cloud_sync_enabled"
        static let syncProvider = "settings.sync_provider"
        static let basicMode = "settings.basic_mode"
        static let autoArchiveDays = "settings.auto_archive_days"

        static let webdavURL = "settings.webdav.url"
        static let webdavUser = "settings.webdav.user"
        static let webdavPass = "settings.webdav.pass"

        static let aiApiKey = "settings.ai.api_key"
        static let aiBaseUrl = "settings.ai.base_url"
        static let aiModel = "settings.ai.model"
        static let aiUseHosted = "settings.ai.use_hosted"
        static let aiConfigured = "settings.ai.is_configured"
        static let aiEnabled = "settings.ai.enabled"
        
        static let progressDir = "settings.progress.dir"
        static let overviewCardOrder = "settings.overview.card_order"
        static let trendCardOrder = "settings.trend.card_order"
        
        static let monthlyAnalysis = "settings.ai.monthly_analysis"
        static let lastAnalyzedMonth = "settings.ai.last_analyzed_month"
    }

    // MARK: - DTO

    struct WebDAVAuth: Sendable {
        let user: String?
        let pass: String?
    }

    struct WebDAVConfig: Sendable {
        let url: String
        let auth: WebDAVAuth
    }

    // MARK: - Defaults

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.cloudSyncEnabled: true,
            Key.syncProvider: SyncProvider.webDAV.rawValue,
            Key.basicMode: false,
            Key.autoArchiveDays: 7,
            Key.aiBaseUrl: "https://api.deepseek.com",
            Key.aiModel: "deepseek-chat",
            Key.aiUseHosted: false,
            Key.aiConfigured: false,
            Key.aiEnabled: true,
            Key.progressDir: false
        ])
    }

    // MARK: - Cloud Sync

    func getCloudSyncEnabled() -> Bool {
        defaults.bool(forKey: Key.cloudSyncEnabled)
    }

    func setCloudSyncEnabled(_ value: Bool) {
        defaults.set(value, forKey: Key.cloudSyncEnabled)
    }

    func getSyncProvider() -> SyncProvider {
        guard let raw = defaults.string(forKey: Key.syncProvider),
              let provider = SyncProvider(rawValue: raw) else {
            return .webDAV
        }
        return provider
    }

    func setSyncProvider(_ provider: SyncProvider) {
        defaults.set(provider.rawValue, forKey: Key.syncProvider)
    }

    // MARK: - Basic Mode

    func getBasicMode() -> Bool {
        defaults.bool(forKey: Key.basicMode)
    }

    func setBasicMode(_ value: Bool) {
        defaults.set(value, forKey: Key.basicMode)
    }

    // MARK: - Auto Archive

    func getAutoArchiveDays() -> Int {
        let v = defaults.integer(forKey: Key.autoArchiveDays)
        return max(0, v) // 防御：不允许负数
    }

    func setAutoArchiveDays(_ days: Int) {
        defaults.set(max(0, days), forKey: Key.autoArchiveDays)
    }

    // MARK: - WebDAV

    func getWebDAVURL() -> String? {
        let s = defaults.string(forKey: Key.webdavURL)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }

    func setWebDAVURL(_ url: String?) {
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = trimmed, !t.isEmpty {
            defaults.set(t, forKey: Key.webdavURL)
        } else {
            defaults.removeObject(forKey: Key.webdavURL)
        }
    }

    func getWebDAVAuth() -> WebDAVAuth {
        .init(
            user: defaults.string(forKey: Key.webdavUser),
            pass: defaults.string(forKey: Key.webdavPass)
        )
    }

    func setWebDAVAuth(user: String?, pass: String?) {
        if let user, !user.isEmpty {
            defaults.set(user, forKey: Key.webdavUser)
        } else {
            defaults.removeObject(forKey: Key.webdavUser)
        }

        if let pass, !pass.isEmpty {
            defaults.set(pass, forKey: Key.webdavPass)
        } else {
            defaults.removeObject(forKey: Key.webdavPass)
        }
    }

    func clearWebDAVAuth() {
        defaults.removeObject(forKey: Key.webdavUser)
        defaults.removeObject(forKey: Key.webdavPass)
    }

    func getWebDAVConfig() -> WebDAVConfig? {
        guard let url = getWebDAVURL() else { return nil }
        let auth = getWebDAVAuth()
        return .init(url: url, auth: auth)
    }
    
    func getAIApiKey() -> String {
        defaults.string(forKey: Key.aiApiKey) ?? ""
    }

    func setAIApiKey(_ key: String) {
        defaults.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.aiApiKey)
    }

    func getAIBaseUrl() -> String {
        defaults.string(forKey: Key.aiBaseUrl) ?? "https://api.deepseek.com"
    }

    func setAIBaseUrl(_ url: String) {
        defaults.set(url.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.aiBaseUrl)
    }

    func getAIModel() -> String {
        defaults.string(forKey: Key.aiModel) ?? "deepseek-chat"
    }

    func setAIModel(_ model: String) {
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.aiModel)
    }
    
    func getAIUseHosted() -> Bool {
        defaults.bool(forKey: Key.aiUseHosted)
    }
    
    func setAIUseHosted(_ use: Bool) {
        defaults.set(use, forKey: Key.aiUseHosted)
    }
    
    func getAIConfigured() -> Bool {
        defaults.bool(forKey: Key.aiConfigured)
    }
    
    func setAIConfigured(_ configured: Bool) {
        defaults.set(configured, forKey: Key.aiConfigured)
    }
    
    func getAIEnabled() -> Bool {
        defaults.bool(forKey: Key.aiEnabled)
    }
    
    func setAIEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.aiEnabled)
    }
    
    func getProgressDir() -> Bool {
        defaults.bool(forKey: Key.progressDir)
    }
    
    func setProgressDir(_ enable: Bool) {
        defaults.set(enable, forKey: Key.progressDir)
    }

    func getOverviewCardOrder() -> [String] {
        defaults.stringArray(forKey: Key.overviewCardOrder) ?? []
    }

    func setOverviewCardOrder(_ order: [String]) {
        defaults.set(order, forKey: Key.overviewCardOrder)
    }

    func getTrendCardOrder() -> [String] {
        defaults.stringArray(forKey: Key.trendCardOrder) ?? []
    }

    func setTrendCardOrder(_ order: [String]) {
        defaults.set(order, forKey: Key.trendCardOrder)
    }

    func getMonthlyAnalysis() -> String? {
        defaults.string(forKey: Key.monthlyAnalysis)
    }

    func setMonthlyAnalysis(_ json: String) {
        defaults.set(json, forKey: Key.monthlyAnalysis)
    }

    func getLastAnalyzedMonth() -> String {
        defaults.string(forKey: Key.lastAnalyzedMonth) ?? ""
    }

    func setLastAnalyzedMonth(_ month: String) {
        defaults.set(month, forKey: Key.lastAnalyzedMonth)
    }

    // MARK: - Debug / Maintenance

    func resetAllSettings() {
        let keys: [String] = [
            Key.cloudSyncEnabled,
            Key.basicMode,
            Key.autoArchiveDays,
            Key.webdavURL,
            Key.webdavUser,
            Key.webdavPass,
            Key.aiApiKey,
            Key.aiBaseUrl,
            Key.aiModel,
            Key.aiUseHosted,
            Key.aiConfigured,
            Key.aiEnabled,
            Key.progressDir
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
        registerDefaults()
    }
}
