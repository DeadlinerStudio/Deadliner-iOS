//
//  AIPanelSheet.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/21.
//

import SwiftUI

struct DeadlinerAIPanel: View {
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("userTier") private var userTier: UserTier = .free
    
    @State private var apiKey: String = ""
    @State private var showPaywall = false
    @State private var isLoadingConfig = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoadingConfig {
                    ProgressView()
                } else if userTier == .free {
                    // 状态 1：未解锁，展示拦截引导页
                    lockedStateView
                } else if userTier == .geek && apiKey.isEmpty {
                    // 状态 2：Geek 版且未配置 API Key
                    missingKeyView
                } else {
                    // 状态 3：已就绪，调用剥离出来的核心工作区
                    AIFunctionView(userTier: userTier)
                }
            }
            .navigationTitle("Deadliner Claw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .task {
                await checkConfig()
            }
            .sheet(isPresented: $showPaywall) {
                ProPaywallView()
                    .presentationDetents([.large])
            }
            .onChange(of: userTier) { _ in
                Task { await checkConfig() }
            }
        }
    }

    // MARK: - States Views

    /// 状态 1：优雅的拦截引导页
    private var lockedStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "sparkles")
                .font(.system(size: 72))
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .symbolEffect(.variableColor, options: .repeating)
            
            VStack(spacing: 8) {
                Text("一句话，安排得明明白白")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Deadliner Claw 能够精准理解你的自然语言。只需随手输入“明天下午三点开会”或“每周跑三次步”，即可瞬间拆解并创建任务与习惯。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            Button {
                showPaywall = true
            } label: {
                Text("解锁 Deadliner+ 获取 AI 赋能")
                    .font(.title3)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: .red.opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    /// 状态 2：缺失 Key 的引导页
    private var missingKeyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.orange)
            
            Text("差最后一步！")
                .font(.title3)
                .fontWeight(.bold)
            
            Text("作为极客版用户，您采用了 BYOK 模式。请前往设置面板填入你的 DeepSeek API Key 以激活本地 AI 引擎。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                dismiss() // 关掉弹窗，让用户去设置里配
            } label: {
                Text("我知道了")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }

    @MainActor
    private func checkConfig() async {
        isLoadingConfig = true
        defer { isLoadingConfig = false }
        apiKey = await LocalValues.shared.getAIApiKey()
    }
}
