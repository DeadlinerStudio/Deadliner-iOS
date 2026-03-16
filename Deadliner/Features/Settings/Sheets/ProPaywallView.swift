//
//  ProPaywallView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/21.
//

import SwiftUI

struct ProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("userTier") private var userTier: UserTier = .free
        
    @StateObject private var storeManager = StoreManager.shared
    @State private var selectedTier: UserTier = .geek
    @State private var isPurchasing = false
    
    private let isProDisabled = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // MARK: - 1. 顶部常驻 Header
                headerView
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                
                // MARK: - 2. 中间可滑动区域
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // 方案选择卡片
                        HStack(spacing: 16) {
                            let geekProduct = storeManager.products.first(where: { $0.id == storeManager.geekProductID })
                            
                            TierSelectionCard(
                                title: "极客版 (Geek)",
                                price: geekProduct?.displayPrice ?? "￥28",
                                period: "永久买断",
                                isSelected: selectedTier == .geek
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTier = .geek
                                }
                            }
                            
                            TierSelectionCard(
                                title: "托管版 (Pro)",
                                price: "￥6",
                                period: "每月",
                                isSelected: selectedTier == .pro,
                                badge: "施工中",
                                isDisabled: isProDisabled
                            ) {
                                if !isProDisabled {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedTier = .pro
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                        // 动态权益列表
                        featuresList
                        
                        if selectedTier == .pro && isProDisabled {
                            VStack(spacing: 8) {
                                Image(systemName: "hammer.fill")
                                    .font(.title)
                                    .foregroundColor(.orange)
                                Text("Pro 功能正在施工中")
                                    .font(.headline)
                                Text("托管版暂不支持购买，敬请期待。")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal, 24)
                        }
                        
                        // MARK: 新增：开发者的一封信
                        developerLetterCard
                    }
                    .padding(.bottom, 24)
                }
                
                // MARK: - 3. 底部常驻购买区
                footerView
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
    
    // MARK: - 视图拆分
    
    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)

            Text("Deadliner+")
                .font(.largeTitle)
                .fontWeight(.heavy)

            Text("加入赞助计划，选择最适合你的效率方案")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var featuresList: some View {
        VStack(spacing: 24) {
            if selectedTier == .geek {
                FeatureRow(icon: "key.horizontal", color: .purple, title: "自带密钥 (BYOK) AI", description: "填入自定义 DeepSeek API Key，本地直连，数据绝对私密。")
                FeatureRow(icon: "chart.line.uptrend.xyaxis", color: .blue, title: "本地艾宾浩斯引擎", description: "解锁离线计算的科学记忆与复习日程规划功能。")
                FeatureRow(icon: "paintbrush.fill", color: .orange, title: "高级视觉与交互", description: "解锁全部专属主题、交互光效与自定义 App 图标。")
            } else {
                FeatureRow(icon: "sparkles", color: .purple, title: "开箱即用的 AI 助手", description: "无需配置 Key，零门槛使用官方服务器高速接口拆解任务。")
                FeatureRow(icon: "icloud.fill", color: .cyan, title: "iCloud 无缝同步", description: "原生级云同步体验，免去 WebDAV 的折腾。")
                FeatureRow(icon: "plus.diamond.fill", color: .orange, title: "包含极客版全部特权", description: "自动享有艾宾浩斯复习、高级视觉等全部核心功能。")
            }
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 220, alignment: .top)
    }
    
    // 开发者来信卡片
    private var developerLetterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image("avatar")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                
                Text("致 iOS 用户的一封信")
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
            
            Text("""
            “让工具回归工具，让工具普惠众人。” 这是我写下 Deadliner 第一行代码时的初衷。
            
            在此我郑重承诺：所有无需服务器成本的基础功能（含 WebDAV 同步），在 iOS 端同样且永远免费。基础体验不该是 VIP 的特权，效率也不该被价格定义。
            
            但由于苹果生态每年存在 688 元的开发者年费要求，为了让 Deadliner 能在 App Store 存活下去并持续迭代，我推出了附加高级进阶功能的 Deadliner+ 计划。
            
            你的每一次付费，都是在帮独立开发者分担这 688 元的“苹果税”，也是对开源社区的直接支持。代码是开源的，心意是免费的。感谢你的赞助！
            """)
            .font(.footnote)
            .foregroundColor(.secondary)
            .lineSpacing(4)
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    
    // 底部常驻购买区
    private var footerView: some View {
        VStack(spacing: 12) {
            let geekProduct = storeManager.products.first(where: { $0.id == storeManager.geekProductID })
            
            Button {
                Task { await purchaseSelectedTier() }
            } label: {
                HStack {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        let buttonText: String = {
                            if selectedTier == .geek {
                                return geekProduct != nil ? "支付 \(geekProduct!.displayPrice) 永久解锁" : "支付 ￥28.00 永久解锁"
                            } else {
                                return isProDisabled ? "暂不可用" : "￥6.00 / 月 立即订阅"
                            }
                        }()
                        Text(buttonText)
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: selectedTier == .geek ? [.blue, .cyan] : (isProDisabled && selectedTier == .pro ? [.gray, .gray.opacity(0.8)] : [.orange, .red]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(.white)
                // 关键点：使用 Capsule() 实现两端完全半圆，等同于 cornerRadius(48)
                .clipShape(Capsule())
                .shadow(color: (selectedTier == .geek ? Color.blue : (isProDisabled && selectedTier == .pro ? Color.gray : Color.red)).opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .disabled(isPurchasing || (isProDisabled && selectedTier == .pro))

            // 恢复购买与协议
            HStack(spacing: 16) {
                Button("恢复购买") {
                    Task { await storeManager.restorePurchases() }
                }
                Text("|").foregroundColor(.secondary.opacity(0.5))
                Button("服务条款") {
                    // TODO: 打开隐私协议
                }
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .background(
            Color(uiColor: .systemBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - 购买逻辑
    @MainActor
    private func purchaseSelectedTier() async {
        isPurchasing = true
        
        if selectedTier == .geek {
            if let geekProduct = storeManager.products.first(where: { $0.id == storeManager.geekProductID }) {
                do {
                    let success = try await storeManager.purchase(geekProduct)
                    if success {
                        dismiss()
                    }
                } catch {
                    print("❌ 购买失败: \(error)")
                }
            }
        }
        
        isPurchasing = false
    }
}

// MARK: - 辅助组件：层级选择卡片
struct TierSelectionCard: View {
    let title: String
    let price: String
    let period: String
    let isSelected: Bool
    var badge: String? = nil
    var isDisabled: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            // 内部统一对齐
            VStack(spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Text(price)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(isDisabled ? .secondary : .primary)
                
                Text(period)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24) // 统一的高度间距
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color(uiColor: .secondarySystemBackground) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? (isDisabled ? Color.gray : (badge != nil ? Color.orange : Color.blue)) : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .opacity(isDisabled && !isSelected ? 0.6 : 1.0)
            // 关键点：使用 overlay(alignment: .top) 把角标悬浮在边框上，脱离 VStack 的文档流，不会改变卡片自身的高度
            .overlay(alignment: .top) {
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(y: -12) // 向上偏移出一半
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 辅助组件：卖点行
// (FeatureRow 代码保持不变)
struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
