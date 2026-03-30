//
//  AccountAndSyncView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import SwiftUI

struct AccountAndSyncView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    @AppStorage("userTier") private var userTier: UserTier = .free
    
    @State private var cloudSyncEnabled = true
    @State private var syncProvider: SyncProvider = .webDAV
    @State private var loadedSyncProvider: SyncProvider = .webDAV
    @State private var webdavURL = ""
    @State private var webdavUser = ""
    @State private var webdavPass = ""

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String?
    @State private var showMessage = false
    
    @State private var showPaywall = false
    @State private var showLogShare = false
    @State private var logURL: URL?

    private var iCloudAvailable: Bool {
        userTier != .free
    }

    var body: some View {
        Form {
            if userTier == .free {
                PlusUpsellSection(showPaywall: $showPaywall)
            }
            
            Section {
                Toggle("启用云同步", isOn: $cloudSyncEnabled)
            } footer: {
                Text("关闭云同步后，所有数据将仅保存在本地设备。")
            }

            Section {
                Picker("同步方式", selection: $syncProvider) {
                    Text("WebDAV").tag(SyncProvider.webDAV)
                    Text("iCloud").tag(SyncProvider.iCloud)
                }
                .pickerStyle(.inline)

                if !iCloudAvailable {
                    HStack {
                        SettingsGradientSymbolIcon(systemName: "icloud.fill", palette: .ocean)
                        Text("iCloud 无缝同步")
                        Spacer()
                        GeekBadge()
                    }
                }
            } header: {
                Text("同步方式")
            } footer: {
                Text(iCloudAvailable
                     ? "iCloud 与 WebDAV 不能同时开启。切换同步方式后，需要重启 App 才会完全生效。"
                     : "当前可使用 WebDAV。升级 Geek 后可切换到 iCloud 无缝同步。")
            }

            Section {
                TextField("服务器 URL (https://...)", text: $webdavURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("用户名（可选）", text: $webdavUser)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("密码（可选）", text: $webdavPass)

                Button("清空 WebDAV 凭据", role: .destructive) {
                    Task { await clearWebDAV() }
                }
            } header: {
                Text("极客同步 (WebDAV)")
            }
            .disabled(syncProvider != .webDAV)
            .opacity(syncProvider == .webDAV ? 1 : 0.45)

            Section {
                HStack {
                    SettingsGradientSymbolIcon(systemName: "icloud.fill", palette: .ocean)
                    Text("iCloud 无缝同步")
                    Spacer()
                    if iCloudAvailable {
                        Text(syncProvider == .iCloud ? "已启用" : "未启用")
                            .foregroundStyle(.secondary)
                    } else {
                        GeekBadge()
                    }
                }
            } header: {
                Text("原生云服务")
            } footer: {
                Text(iCloudAvailable
                     ? (syncProvider == .iCloud
                        ? "当前已使用 iCloud 作为唯一云同步方式，WebDAV 不会同时运行。"
                        : "切换到 iCloud 后，将停用 WebDAV 同步引擎并改用系统原生云同步。")
                     : "Geek 可解锁 iCloud 无缝同步。")
            }
            
            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("保存配置")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving || isLoading)
            }

            Section {
                Button("导出同步日志") {
                    Task {
                        logURL = await SyncDebugLog.exportURL()
                        showLogShare = true
                    }
                }

                Button("清空同步日志", role: .destructive) {
                    Task {
                        try? await SyncDebugLog.clear()
                        message = "同步日志已清空"
                        showMessage = true
                    }
                }

                if let logURL {
                    HStack {
                        Text("日志文件")
                        Spacer()
                        Text(logURL.lastPathComponent)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("同步日志")
            } footer: {
                Text("问题出现后，导出 `deadliner-sync.log` 并反馈。")
            }
        }
        .navigationTitle("账号与云同步")
        .navigationBarTitleDisplayMode(.inline)
        .optionalTint(themeStore.switchTint)
        .task { await load() }
        .onChange(of: syncProvider) { newValue in
            guard newValue == .iCloud, !iCloudAvailable else { return }
            syncProvider = .webDAV
            showPaywall = true
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView().presentationDetents([.large])
        }
        .sheet(isPresented: $showLogShare) {
            if let logURL {
                ActivityView(activityItems: [logURL])
            }
        }
        .alert("提示", isPresented: $showMessage) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }


    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }

        cloudSyncEnabled = await LocalValues.shared.getCloudSyncEnabled()
        syncProvider = await LocalValues.shared.getSyncProvider()
        if !iCloudAvailable && syncProvider == .iCloud {
            syncProvider = .webDAV
        }
        loadedSyncProvider = syncProvider

        if let cfg = await LocalValues.shared.getWebDAVConfig() {
            webdavURL = cfg.url
            webdavUser = cfg.auth.user ?? ""
            webdavPass = cfg.auth.pass ?? ""
        }
    }

    @MainActor
    private func save() async {
        if !iCloudAvailable && syncProvider == .iCloud {
            syncProvider = .webDAV
        }

        let trimmedURL = webdavURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if cloudSyncEnabled && syncProvider == .webDAV && !trimmedURL.isEmpty && URL(string: trimmedURL) == nil {
            message = "WebDAV 服务器 URL 格式不正确"
            showMessage = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        await LocalValues.shared.setCloudSyncEnabled(cloudSyncEnabled)
        await LocalValues.shared.setSyncProvider(syncProvider)
        await LocalValues.shared.setWebDAVURL(trimmedURL.isEmpty ? nil : trimmedURL)
        await LocalValues.shared.setWebDAVAuth(user: webdavUser, pass: webdavPass)

        let providerChanged = syncProvider != loadedSyncProvider
        loadedSyncProvider = syncProvider
        message = providerChanged
            ? "同步设置已保存。已切换为 \(syncProvider.displayName)，重启 App 后会完全生效。"
            : "同步设置已保存"
        showMessage = true
    }
    
    @MainActor
    private func clearWebDAV() async {
        await LocalValues.shared.setWebDAVURL(nil)
        await LocalValues.shared.clearWebDAVAuth()
        webdavURL = ""
        webdavUser = ""
        webdavPass = ""
    }
}
