//
//  ThemeSettingsView.swift
//  Deadliner
//
//  Created by Codex on 2026/3/22.
//

import SwiftUI

struct ThemeSettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    @AppStorage("userTier") private var userTier: UserTier = .free
    @State private var showPaywall = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        Form {
            Section {
                previewCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                Toggle("启用顶部光效 Overlay", isOn: overlayEnabledBinding)

                Toggle("AI 使用强调色三色方案", isOn: aiAccentPaletteBinding)
                    .disabled(!themeStore.overlayEnabled || userTier == .free)
            } header: {
                Text("顶部 Overlay")
            } footer: {
                Text(userTier == .free
                     ? "这一项对所有用户开放。关闭后，首页顶栏不会显示任何光效。"
                     : "关闭后，首页顶栏不会显示任何光效。开启后，无 AI 时始终使用你这套强调色三色映射；有 AI 时默认使用品牌 AI 光效，但你可以切回强调色三色方案。")
            }

            Section {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ThemeAccentOption.allCases) { option in
                        accentCell(option)
                    }
                }
                .padding(.vertical, 8)
                .disabled(userTier == .free)
            } header: {
                Text("强调色")
            } footer: {
                Text("Geek 及以上可用。默认主题保持蓝色 accent，同时保留系统默认开关轨道色和你当前的右下角自定义按钮色。选择任意 Apple 颜色后，accent、开关轨道和右下角按钮会一起切换。")
            }

        }
        .navigationTitle("App 主题")
        .navigationBarTitleDisplayMode(.inline)
        .optionalTint(themeStore.switchTint)
        .sheet(isPresented: $showPaywall) {
            ProPaywallView().presentationDetents([.large])
        }
    }

    private var overlayEnabledBinding: Binding<Bool> {
        Binding(
            get: { themeStore.overlayEnabled },
            set: { newValue in
                if userTier == .free {
                    showPaywall = true
                } else {
                    themeStore.setOverlayEnabled(newValue)
                }
            }
        )
    }

    private var aiAccentPaletteBinding: Binding<Bool> {
        Binding(
            get: { themeStore.useAccentPaletteWhenAI },
            set: { newValue in
                if userTier == .free {
                    showPaywall = true
                } else {
                    themeStore.setUseAccentPaletteWhenAI(newValue)
                }
            }
        )
    }

    private var previewCard: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(alignment: .top) {
                    ThemeGlowPreview(
                        palette: themeStore.overlayPalette(isAIConfigured: true),
                        accent: themeStore.accentColor,
                        enabled: themeStore.overlayEnabled
                    )
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }

            VStack(alignment: .leading, spacing: 10) {
                Text("当前主题预览")
                    .font(.headline)

                Text(themeStore.accentOption == .systemDefault ? "经典 Deadliner" : "\(themeStore.accentOption.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Circle()
                        .fill(themeStore.accentColor)
                        .frame(width: 12, height: 12)

                    Text(themeStore.useAccentPaletteWhenAI ? "AI 光效：强调色方案" : "AI 光效：品牌方案")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Button {
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(themeStore.fabColor, in: Circle())
                    .shadow(color: themeStore.fabColor.opacity(0.28), radius: 12, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .padding(18)
            .allowsHitTesting(false)
        }
        .frame(height: 180)
    }

    private func accentCell(_ option: ThemeAccentOption) -> some View {
        Button {
            if userTier == .free {
                showPaywall = true
            } else {
                themeStore.setAccentOption(option)
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(option == .systemDefault ? ThemeDefaults.fabColor : option.color)
                        .frame(width: 34, height: 34)

                    if option == themeStore.accentOption {
                        Circle()
                            .stroke(Color.primary.opacity(0.18), lineWidth: 2)
                            .frame(width: 42, height: 42)
                    }

                    if option == .systemDefault {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                Text(option.displayName)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(option == themeStore.accentOption ? option.color.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

}

private struct ThemeGlowPreview: View {
    let palette: AIGlowPalette
    let accent: Color
    let enabled: Bool

    var body: some View {
        ZStack {
            if enabled {
                LinearGradient(
                    colors: [
                        accent.opacity(0.95),
                        accent.opacity(0.45),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [palette.blue, palette.blue.opacity(0.65), palette.blue.opacity(0)],
                    center: UnitPoint(x: 0.15, y: 0.22),
                    startRadius: 0,
                    endRadius: 150
                )

                RadialGradient(
                    colors: [palette.pink, palette.pink.opacity(0.62), palette.pink.opacity(0)],
                    center: UnitPoint(x: 0.82, y: 0.20),
                    startRadius: 0,
                    endRadius: 150
                )

                RadialGradient(
                    colors: [palette.amber, palette.amber.opacity(0.58), palette.amber.opacity(0)],
                    center: UnitPoint(x: 0.50, y: 0.88),
                    startRadius: 0,
                    endRadius: 140
                )
            }
        }
        .allowsHitTesting(false)
    }
}
