//
//  AISettingsView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/21.
//

import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    @AppStorage("userTier") private var userTier: UserTier = .free
    @AppStorage("settings.ai.enabled") private var aiEnabled: Bool = true
    @AppStorage("settings.ai.auto_approve_read_tasks") private var autoApproveReadTasks: Bool = false
    @AppStorage("settings.ai.silent_task_add") private var silentTaskAdd: Bool = true
    @AppStorage("settings.ai.hide_thinking_process") private var hideThinkingProcess: Bool = false
    
    @State private var apiKey = ""
    @State private var baseUrl = ""
    @State private var model = ""
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showToast = false
    @State private var showPaywall = false // 控制付费墙

    var body: some View {
        Form {
            if userTier == .free {
                PlusUpsellSection(showPaywall: $showPaywall)
            }
            
            Section {
                Toggle("启用 AI 功能", isOn: $aiEnabled)
                    .disabled(userTier == .free)
            } footer: {
                if userTier == .free {
                    Text("免费版暂不支持关闭 AI 功能。Geek 可自由切换。")
                } else {
                    Text("关闭后，主页底栏和任务编辑器中的 AI 相关入口将隐藏。")
                }
            }

            Section {
                Toggle("自动确认读取任务列表", isOn: $autoApproveReadTasks)
                Toggle("静默添加任务", isOn: $silentTaskAdd)
                Toggle("隐藏思考过程", isOn: $hideThinkingProcess)
            } header: {
                Text("交互偏好")
            } footer: {
                Text("开启静默添加后，识别到的新任务会直接写入；任务按钮会变为“撤回任务”。关闭后会保留手动确认。")
            }
            
            Section("API 配置 (BYOK)") {
                SecureField("API Key (sk-...)", text: $apiKey)
                TextField("Base URL", text: $baseUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                TextField("Model ID (如 deepseek-chat)", text: $model)
                    .textInputAutocapitalization(.never)
            }
            .disabled(userTier == .free)
            
            Section("说明") {
                Text("Lifi AI 现统一采用自带密钥 (BYOK) 模式。您的 API Key 仅保存在本地设备，不会上传至任何第三方服务器。Geek 可用。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
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
        .navigationTitle("Lifi AI")
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
    }
    
    @MainActor
    private func saveAIConfig() async {
        isLoading = true
        errorMessage = nil
        
        do {
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
            showToast = true
        } catch {
            errorMessage = "验证失败：\(error.localizedDescription)\n请检查 API Key、Base URL 和模型名称是否正确。"
        }
        
        isLoading = false
    }
}
