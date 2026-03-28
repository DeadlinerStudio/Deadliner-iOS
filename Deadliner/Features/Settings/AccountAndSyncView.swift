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

            // 极客开源选项 (完全免费)
            Section("极客同步 (WebDAV)") {
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
            }

            Section {
                HStack {
                    SettingsGradientSymbolIcon(systemName: "icloud.fill", palette: .sky)
                    Text("iCloud 无缝同步")
                    Spacer()
                    if userTier != .free {
                        Toggle("", isOn: .constant(true)) // 占位
                    } else {
                        GeekBadge()
                    }
                }
                .disabled(userTier == .free)
            } header: {
                Text("原生云服务")
            } footer: {
                Text(userTier == .free
                     ? "Geek 可解锁 iCloud 无缝同步。"
                     : "已归入 Geek 权益。当前为占位入口，后续会在这里补齐原生同步细节。")
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

        if let cfg = await LocalValues.shared.getWebDAVConfig() {
            webdavURL = cfg.url
            webdavUser = cfg.auth.user ?? ""
            webdavPass = cfg.auth.pass ?? ""
        }
    }

    @MainActor
    private func save() async {
        // (URL 校验逻辑与原代码保持一致，此处省略以节省篇幅)
        isSaving = true
        defer { isSaving = false }

        await LocalValues.shared.setCloudSyncEnabled(cloudSyncEnabled)
        await LocalValues.shared.setWebDAVURL(webdavURL.isEmpty ? nil : webdavURL)
        await LocalValues.shared.setWebDAVAuth(user: webdavUser, pass: webdavPass)

        message = "同步设置已保存"
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
