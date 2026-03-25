//
//  AISettingsView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/21.
//

import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    // 直接读取全局状态，取代之前传进来的 isProUser
    @AppStorage("userTier") private var userTier: UserTier = .free
    @AppStorage("settings.ai.enabled") private var aiEnabled: Bool = true
    
    @State private var useHostedAI = true // 新增：是否使用托管 AI
    @State private var apiKey = ""
    @State private var baseUrl = ""
    @State private var model = ""
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showToast = false
    @State private var showPaywall = false // 控制付费墙

    var body: some View {
        Form {
            // 只要不是 Pro (Free 和 Geek)，都提示可以升级到最高阶
            if userTier != .pro {
                PlusUpsellSection(showPaywall: $showPaywall)
            }
            
            Section {
                Toggle("启用 AI 功能", isOn: $aiEnabled)
                    .disabled(userTier == .free)
            } footer: {
                if userTier == .free {
                    Text("免费版暂不支持关闭 AI 功能。极客版及以上可自由切换。")
                } else {
                    Text("关闭后，主页底栏和任务编辑器中的 AI 相关入口将隐藏。")
                }
            }
            
            // MARK: - 官方托管服务 (Pro 专属)
            Section {
                HStack {
                    settingsLabel("使用官方托管 AI 服务", systemImage: "server.rack")
                    Spacer()
                    if userTier == .pro {
                        Toggle("", isOn: $useHostedAI)
                    } else {
                        ProBadge()
                    }
                }
                .disabled(userTier != .pro)
            } footer: {
                Text(userTier == .pro
                     ? "开启后，将直接使用官方的高速 DeepSeek 节点进行自然语言解析，无需自行配置。"
                     : "Pro 会员专属。无需折腾 API Key，开箱即用的高速 AI 体验。")
            }
            
            // MARK: - 极客配置 (Geek / 关闭托管的 Pro / 免费用户只能看)
            if !(userTier == .pro && useHostedAI) {
                Section("API 配置 (自带密钥 BYOK)") {
                    SecureField("API Key (sk-...)", text: $apiKey)
                    TextField("Base URL", text: $baseUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    TextField("Model ID (如 deepseek-chat)", text: $model)
                        .textInputAutocapitalization(.never)
                }
                .disabled(userTier == .free) // 免费用户不可编辑
                
                Section("说明") {
                    Text("采用自带密钥 (BYOK) 模式，您的 API Key 仅保存在本地设备，不会上传至任何第三方服务器。极客版及以上可用。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            
            if userTier != .free {
                Section {
                    Button {
                        Task { await saveAIConfig() }
                    } label: {
                        if isLoading {
                            HStack {
                                Text("正在验证...")
                                ProgressView()
                            }
                        } else {
                            Text("保存并验证 AI 设置")
                        }
                    }
                    .disabled(isLoading)
                } footer: {
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("Deadliner Claw")
        .navigationBarTitleDisplayMode(.inline)
        .optionalTint(themeStore.switchTint)
        .sheet(isPresented: $showPaywall) {
            ProPaywallView().presentationDetents([.large])
        }
        .task {
            if userTier != .free { await loadAIConfig() }
        }
        .alert("已保存", isPresented: $showToast) {
            Button("好的", role: .cancel) {}
        }
    }
    
    @MainActor
    private func loadAIConfig() async {
        apiKey = await LocalValues.shared.getAIApiKey()
        baseUrl = await LocalValues.shared.getAIBaseUrl()
        model = await LocalValues.shared.getAIModel()
        useHostedAI = await LocalValues.shared.getAIUseHosted()
    }
    
    @MainActor
    private func saveAIConfig() async {
        isLoading = true
        errorMessage = nil
        
        do {
            if userTier == .pro && useHostedAI {
                // 托管模式，暂时默认配置正确（或在此调用官方验证接口）
                await LocalValues.shared.setAIUseHosted(true)
                await LocalValues.shared.setAIConfigured(true)
            } else {
                // 自定义模式，必须验证
                try await AIService.shared.validateConfig(
                    apiKey: apiKey,
                    baseUrl: baseUrl,
                    modelId: model
                )
                
                await LocalValues.shared.setAIApiKey(apiKey)
                await LocalValues.shared.setAIBaseUrl(baseUrl)
                await LocalValues.shared.setAIModel(model)
                await LocalValues.shared.setAIUseHosted(false)
                await LocalValues.shared.setAIConfigured(true)
            }
            showToast = true
        } catch {
            errorMessage = "验证失败：\(error.localizedDescription)\n请检查 API Key、Base URL 和模型名称是否正确。"
        }
        
        isLoading = false
    }

    private func settingsLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(themeStore.accentColor)
                .frame(width: 22)

            Text(title)
                .foregroundStyle(.primary)
        }
    }
}
