//
//  ProPaywallView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/21.
//

import SwiftUI
import StoreKit
import UIKit

private enum PaywallPreviewMacro {
    #if PAYWALL_FORCE_FREE
    static let tierOverride: UserTier? = .free
    #else
    static let tierOverride: UserTier? = nil
    #endif
}

struct ProPaywallView: View {
    enum PresentationMode {
        case sheetUpsell
        case membershipCenter
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    
    @AppStorage("userTier") private var userTier: UserTier = .free
        
    @StateObject private var storeManager = StoreManager.shared
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var restoreResultMessage = ""
    @State private var showRestoreResult = false

    let presentationMode: PresentationMode

    init(presentationMode: PresentationMode = .sheetUpsell) {
        self.presentationMode = presentationMode
    }

    var body: some View {
        Group {
            if presentationMode == .sheetUpsell {
                NavigationStack {
                    paywallContent
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { dismiss() } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                        }
                }
            } else {
                paywallContent
                    .navigationTitle("会员中心")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert("恢复购买", isPresented: $showRestoreResult) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(restoreResultMessage)
        }
        .task {
            await storeManager.updatePurchasedProducts()
        }
    }

    private var paywallContent: some View {
        ZStack(alignment: .bottom) {
            paywallBackground

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    headerView
                        .padding(.top, 18)

                    if effectiveTier == .free {
                        HStack(spacing: 16) {
                            let geekProduct = storeManager.products.first(where: { $0.id == storeManager.geekProductID })

                            TierSelectionCard(
                                title: "极客版 (Geek)",
                                price: geekProduct?.displayPrice ?? "加载中",
                                period: "永久买断",
                                isSelected: true
                            ) {}
                        }
                        .padding(.horizontal, 24)
                    } else {
                        memberStatusCard
                            .padding(.horizontal, 24)
                    }

                    featuresList
                    developerLetterCard

                    Color.clear
                        .frame(height: 132)
                }
                .padding(.bottom, 22)
            }

            VStack(spacing: 10) {
                if effectiveTier == .free {
                    purchaseButton
                        .padding(.horizontal, 40)
                }

                floatingLegalCapsule
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 14)
        }
    }
    
    // MARK: - 视图拆分
    
    private var headerView: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.18), .pink.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.orange.opacity(0.14), radius: 20, x: 0, y: 8)

                Image(systemName: "crown.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }

            Text("Deadliner+")
                .font(.largeTitle)
                .fontWeight(.heavy)

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var memberStatusCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("当前会员：\(effectiveTier.displayName)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("会员权益已启用，可继续在此页恢复购买或查看权益说明。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.orange.opacity(0.035))
                )
        )
    }
    
    private var featuresList: some View {
        VStack(spacing: 24) {
            FeatureRow(
                icon: "lifi.logo.v1",
                color: .indigo,
                title: "Lifi AI（Rust 跨平台 Agent）",
                description: "Deadliner+ 的核心能力：基于 Rust 的跨平台通用 Agent，围绕任务流提供智能理解、拆解与建议。",
                systemIcon: false
            )
            FeatureRow(
                icon: "sparkles",
                color: .purple,
                title: "任务管理智能体与记忆能力",
                description: "围绕「收集 - 规划 - 执行 - 复盘」持续辅助，并逐步记住你的偏好与上下文，让 AI 越用越懂你。"
            )
            FeatureRow(
                icon: "icloud.fill",
                color: .cyan,
                title: "iCloud 与 WebDAV 同步",
                description: "解锁更完整的同步能力，按你的使用习惯自由选择。"
            )
            FeatureRow(
                icon: "chart.line.uptrend.xyaxis",
                color: .blue,
                title: "本地艾宾浩斯引擎",
                description: "解锁离线计算的科学记忆与复习日程规划功能。"
            )
            FeatureRow(
                icon: "paintbrush.fill",
                color: .orange,
                title: "高级视觉与交互",
                description: "解锁全部专属主题、交互光效与自定义 App 图标。"
            )
            FeatureRow(
                icon: "key.horizontal",
                color: .gray,
                title: "BYOK 私有接入",
                description: "填写你自己的模型 API Key（如 DeepSeek），本地优先，数据链路可控。"
            )
        }
        .padding(20)
        .frame(minHeight: 220, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.orange.opacity(0.025))
                )
        )
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 7)
    }
    
    // 开发者来信卡片
    private var developerLetterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                developerAvatar
                
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
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.orange.opacity(0.03))
                )
        )
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.04), radius: 14, x: 0, y: 8)
    }

    
    private var purchaseButton: some View {
        let geekProduct = storeManager.products.first(where: { $0.id == storeManager.geekProductID })

        return Button {
            Task { await purchaseSelectedTier() }
        } label: {
            HStack {
                if isPurchasing {
                    ProgressView()
                } else {
                    let buttonText = geekProduct != nil ? "支付 \(geekProduct!.displayPrice) 永久解锁" : "暂不可用..."
                    Text(buttonText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .tint(.purple)
        .buttonStyle(.glassProminent)
        .disabled(isPurchasing)
    }

    private var floatingLegalCapsule: some View {
        HStack(spacing: 0) {
            Button {
                restorePurchases()
            } label: {
                HStack(spacing: 6) {
                    Text("恢复购买")
                    if isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isRestoring)
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 14)

            Button("服务条款") {
                openPrivacyPolicy()
            }
            .frame(maxWidth: .infinity)
        }
        .font(.footnote)
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect()
    }

    // MARK: - 购买逻辑
    @MainActor
    private func purchaseSelectedTier() async {
        isPurchasing = true

        if let geekProduct = storeManager.products.first(where: { $0.id == storeManager.geekProductID }) {
            do {
                let success = try await storeManager.purchase(geekProduct)
                if success {
                    if presentationMode == .sheetUpsell {
                        dismiss()
                    }
                }
            } catch {
                print("❌ 购买失败: \(error)")
            }
        }
        
        isPurchasing = false
    }

    private var headerSubtitle: String {
        if effectiveTier == .free {
            return "加入赞助计划，解锁 Deadliner 的完整体验"
        }
        return "感谢支持独立开发，会员权益已处于可用状态"
    }

    private func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true

        Task {
            await storeManager.restorePurchases()
            await storeManager.updatePurchasedProducts()
            await MainActor.run {
                isRestoring = false
                restoreResultMessage = effectiveTier == .free
                    ? "已完成恢复校验，当前未找到可恢复的会员权益。"
                    : "恢复成功，当前会员权益已同步。"
                showRestoreResult = true
            }
        }
    }

    private func openPrivacyPolicy() {
        guard let url = URL(string: "https://www.aritxonly.top/privacy_ios") else { return }
        openURL(url)
    }

    private var effectiveTier: UserTier {
        PaywallPreviewMacro.tierOverride ?? userTier
    }

    private var paywallBackground: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: animatedMeshPoints(at: t),
                    colors: [
                        Color(uiColor: .systemBackground),
                        Color.orange.opacity(0.12),
                        Color.cyan.opacity(0.1),
                        Color.pink.opacity(0.08),
                        Color(uiColor: .secondarySystemBackground).opacity(0.96),
                        Color.blue.opacity(0.08),
                        Color(uiColor: .systemGroupedBackground),
                        Color.teal.opacity(0.07),
                        Color(uiColor: .systemBackground)
                    ],
                    background: Color(uiColor: .systemBackground),
                    smoothsColors: true
                )
                .ignoresSafeArea()
            }

            brandAtmosphereLayer
            contentReadabilityVeil
        }
        .ignoresSafeArea()
    }

    private func animatedMeshPoints(at time: TimeInterval) -> [SIMD2<Float>] {
        func clamp(_ value: Double) -> Float {
            Float(min(max(value, 0), 1))
        }

        let t = time

        return [
            .init(clamp(0.0), clamp(0.0)),
            .init(clamp(0.50 + 0.04 * sin(t * 0.22)), clamp(0.0)),
            .init(clamp(1.0), clamp(0.0)),

            .init(clamp(0.0), clamp(0.50 + 0.06 * sin(t * 0.18))),
            .init(
                clamp(0.50 + 0.08 * sin(t * 0.16)),
                clamp(0.50 + 0.08 * cos(t * 0.19))
            ),
            .init(clamp(1.0), clamp(0.50 + 0.05 * cos(t * 0.15))),

            .init(clamp(0.0), clamp(1.0)),
            .init(clamp(0.50 + 0.03 * cos(t * 0.17)), clamp(1.0)),
            .init(clamp(1.0), clamp(1.0))
        ]
    }

    private var brandAtmosphereLayer: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    floatingBrandIcon("IconPreview-DeadlinerDefault", time: t, x: 0.12, y: 0.17, size: 50, phase: 0.1, in: proxy.size)
                    floatingBrandIcon("IconPreview-DeadlinerSpring", time: t, x: 0.9, y: 0.2, size: 38, phase: 1.0, in: proxy.size)
                    floatingBrandIcon("IconPreview-DeadlinerSummer", time: t, x: 0.88, y: 0.66, size: 44, phase: 0.6, in: proxy.size)
                    floatingBrandIcon("IconPreview-DeadlinerAutumn", time: t, x: 0.14, y: 0.74, size: 42, phase: 1.7, in: proxy.size)
                    floatingBrandIcon("IconPreview-DeadlinerWinter", time: t, x: 0.52, y: 0.91, size: 34, phase: 2.2, in: proxy.size)

                    floatingBrandGlyph(system: "calendar.badge.clock", time: t, x: 0.5, y: 0.12, phase: 0.3, in: proxy.size)
                    floatingBrandGlyph(system: "repeat.circle", time: t, x: 0.84, y: 0.43, phase: 1.2, in: proxy.size)
                    floatingBrandGlyph(system: "iphone", time: t, x: 0.16, y: 0.45, phase: 2.0, in: proxy.size)
                    floatingBrandGlyph(system: "brain.head.profile", time: t, x: 0.26, y: 0.9, phase: 1.6, in: proxy.size)
                    floatingBrandGlyph(system: "icloud", time: t, x: 0.74, y: 0.9, phase: 2.6, in: proxy.size)

                    Image("lifi.logo.v1")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .foregroundStyle(.white.opacity(0.16))
                        .rotationEffect(.degrees(4 * sin(t * 0.25)))
                        .offset(
                            x: proxy.size.width * 0.02,
                            y: -proxy.size.height * 0.14 + 6 * cos(t * 0.3)
                        )
                        .blur(radius: 0.4)
                }
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func floatingBrandIcon(
        _ assetName: String,
        time: TimeInterval,
        x: CGFloat,
        y: CGFloat,
        size: CGFloat,
        phase: Double,
        in container: CGSize
    ) -> some View {
        let dx = CGFloat(8 * sin(time * 0.34 + phase))
        let dy = CGFloat(10 * cos(time * 0.28 + phase))
        let angle = 4 * sin(time * 0.20 + phase)

        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: size * 0.34, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            .opacity(0.22)
            .rotationEffect(.degrees(angle))
            .position(x: container.width * x + dx, y: container.height * y + dy)
    }

    @ViewBuilder
    private func floatingBrandGlyph(
        system: String,
        time: TimeInterval,
        x: CGFloat,
        y: CGFloat,
        phase: Double,
        in container: CGSize
    ) -> some View {
        let dx = CGFloat(6 * sin(time * 0.18 + phase))
        let dy = CGFloat(7 * cos(time * 0.14 + phase))

        Image(systemName: system)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .opacity(0.5)
        .position(x: container.width * x + dx, y: container.height * y + dy)
    }

    private var contentReadabilityVeil: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground).opacity(colorScheme == .dark ? 0.38 : 0.2),
                .clear,
                Color(uiColor: .systemBackground).opacity(colorScheme == .dark ? 0.30 : 0.16)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var developerAvatar: some View {
        if let name = developerAvatarAssetName {
            Image(name)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.2), .pink.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
        }
    }

    private var developerAvatarAssetName: String? {
        if UIImage(named: "avatar") != nil { return "avatar" }
        if UIImage(named: "Avatar") != nil { return "Avatar" }
        return nil
    }

}

// MARK: - 辅助组件：层级选择卡片
struct TierSelectionCard: View {
    let title: String
    let price: String
    let period: String
    let isSelected: Bool
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
                    .foregroundColor(.primary)
                
                Text(period)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(isSelected ? Color.orange.opacity(0.035) : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .shadow(color: isSelected ? .orange.opacity(0.16) : .clear, radius: 16, x: 0, y: 8)
    }
}

// MARK: - 辅助组件：卖点行
// (FeatureRow 代码保持不变)
struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    var systemIcon: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if systemIcon {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 32)
            } else {
                Image(icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 32)
            }

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
