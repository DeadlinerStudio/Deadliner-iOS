//
//  SettingsView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import SwiftUI
import PhotosUI

struct SettingsView: View {
    // 使用统一的枚举状态管理
    @AppStorage("userTier") private var userTier: UserTier = .free
    @AppStorage("userName") private var userName: String = "用户"
    @StateObject private var avatarManager = AvatarManager.shared
    @State private var showProPaywall = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedUIImage: UIImage?
    @State private var showCropper = false
    @State private var showNameAlert = false
    @State private var tempName = ""

    var body: some View {
        List {
            // MARK: - 1. 用户信息模块
            VStack(spacing: 4) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Group {
                        if let avatar = avatarManager.avatarImage {
                            avatar
                                .resizable()
                        } else {
                            Image(systemName: "person.crop.circle")
                                .resizable()
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    if let newItem {
                        Task {
                            if let data = try? await newItem.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                selectedUIImage = uiImage
                                showCropper = true
                                selectedPhotoItem = nil // 重置以允许再次选择同一张图
                            }
                        }
                    }
                }
                .fullScreenCover(isPresented: $showCropper) {
                    if let uiImage = selectedUIImage {
                        ImageCropper(image: uiImage) { croppedImage in
                            avatarManager.saveAvatar(uiImage: croppedImage)
                        }
                    }
                }
                
                Button {
                    tempName = userName
                    showNameAlert = true
                } label: {
                    HStack(spacing: 8) {
                        Text(userName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Image(systemName: "pencil.circle.fill")
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                .padding(.vertical, 12)
                .alert("修改昵称", isPresented: $showNameAlert) {
                    TextField("输入新的昵称", text: $tempName)
                    Button("取消", role: .cancel) { }
                    Button("确定") {
                        if !tempName.trimmingCharacters(in: .whitespaces).isEmpty {
                            userName = tempName
                        }
                    }
                }
                
                // 动态徽章展示
                Text(userTier.displayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(userTier == .free ? .secondary : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Group {
                            switch userTier {
                            case .free:
                                Color.gray.opacity(0.15)
                            case .geek:
                                LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                            case .pro:
                                LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                            }
                        }
                    )
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            
            // MARK: - 2. Deadliner+ 引导横幅
            if userTier == .free {
                PlusUpsellSection(showPaywall: $showProPaywall)
            }

            // MARK: - 3. 通用与基础设置
            Section("通用") {
                NavigationLink(destination: BehaviorAndDisplayView()) {
                    Label("行为、交互与显示", systemImage: "hand.tap")
                }
                
                // 云同步：如果是 Pro 用户，里面会多出一个 iCloud 选项
                NavigationLink(destination: AccountAndSyncView()) {
                    HStack {
                        Label("账号与云同步", systemImage: "cloud")
                    }
                }
            }

            // MARK: - 4. 效率引擎
            Section("效率引擎") {
                // AI 助手：这是 Deadliner+ 的核心卖点。Free 用户看到 Plus，Geek 用户看到 Pro（吸引他们升级免配置）
                NavigationLink(destination: AISettingsView()) {
                    HStack {
                        Label("Deadliner Claw", systemImage: "sparkles")
                        Spacer()
                        if userTier == .free {
                            PlusBadge()
                        } else if userTier == .geek {
                            ProBadge()
                        }
                    }
                }
            }

            // MARK: - 5. 外观与个性化
            // 个性化：只要是 Deadliner+ 计划（Geek 或 Pro）都能解锁
            Section("个性化") {
                NavigationLink(destination: Text("主题设置开发中...")) {
                    HStack {
                        Label("App 主题", systemImage: "paintbrush")
                        Spacer()
                        if userTier == .free { PlusBadge() }
                    }
                }
                NavigationLink(destination: IconSettingsView()) {
                    HStack {
                        Label("自定义图标", systemImage: "app.dashed")
                        Spacer()
                        if userTier == .free { PlusBadge() }
                    }
                }
            }

            // MARK: - 6. 其他
            Section("关于") {
                HStack {
                    Label("版本信息", systemImage: "info.circle")
                    Spacer()
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                    Text("\(version) (\(build))")
                        .foregroundColor(.secondary)
                }
                
                Link(destination: URL(string: "https://github.com/AritxOnly/Deadliner-iOS/blob/main/LICENSE")!) {
                    Label("开源协议 (GPLv3)", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showProPaywall) {
            ProPaywallView()
                .presentationDetents([.large])
        }
    }
    
    // 测试用快捷方法
    private func toggleUserTierForTesting() {
        switch userTier {
        case .free: userTier = .geek
        case .geek: userTier = .pro
        case .pro: userTier = .free
        }
    }
}
