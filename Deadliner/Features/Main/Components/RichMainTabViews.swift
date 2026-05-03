//
//  RichMainTabViews.swift
//  Deadliner
//
//  Created by Codex on 2026/3/30.
//

import SwiftUI

struct RichHomeTabView: View {
    @Binding var query: String
    @Binding var taskSegment: TaskSegment
    @Binding var overlayProgress: CGFloat

    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false

    let onSettingsTapped: () -> Void

    var body: some View {
        NavigationStack {
            HomeView(
                query: $query,
                taskSegment: $taskSegment,
                onScrollProgressChange: { overlayProgress = $0 }
            )
            .navigationTitle("清单")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSettingsTapped()
                    } label: {
                        Group {
                            if let avatar = AvatarManager.shared.avatarImage {
                                avatar
                                    .resizable()
                                    .renderingMode(.original)
                            } else {
                                Image(systemName: "person.crop.circle")
                                    .resizable()
                                    .renderingMode(.original)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                        .contentShape(Circle())
                    }
                    .accessibilityLabel("用户与设置")
                    .accessibilityHint("打开用户面板与设置")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .background {
                ZStack(alignment: .top) {
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()

                    TopBarGradientOverlay(progress: overlayProgress, isAIConfigured: isAIConfigured)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

struct RichArchiveTabView: View {
    @Binding var query: String
    @Binding var overlayProgress: CGFloat

    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false

    var body: some View {
        NavigationStack {
            ArchiveView(query: $query, onScrollProgressChange: { overlayProgress = $0 })
                .navigationTitle("归档")
                .navigationBarTitleDisplayMode(.automatic)
                .searchable(text: $query, prompt: "搜索归档...")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            NotificationCenter.default.post(name: .ddlDeleteAllArchived, object: nil)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("删除所有归档")
                    }
                }
                .background {
                    ZStack(alignment: .top) {
                        Color(uiColor: .systemGroupedBackground)
                            .ignoresSafeArea()

                        TopBarGradientOverlay(progress: overlayProgress, isAIConfigured: isAIConfigured)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

struct RichOverviewTabView: View {
    @Binding var overlayProgress: CGFloat

    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false
    @AppStorage("settings.ai.last_analyzed_month") private var lastAnalyzedMonth: String = ""
    @AppStorage("userTier") private var userTier: UserTier = .free
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            OverviewView(onScrollProgressChange: { overlayProgress = $0 })
                .navigationTitle("概览")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationSubtitle(overviewSubtitle)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if isInsightFreeUser {
                                showPaywall = true
                            } else if !insightAnalysisGenerated {
                                NotificationCenter.default.post(name: .ddlRequestMonthlyAnalysis, object: nil)
                            }
                        } label: {
                            if isInsightFreeUser {
                                Image(systemName: "lock.fill")
                            } else if insightAnalysisGenerated {
                                Image(systemName: "checkmark.circle.fill")
                            } else {
                                Image("lifi.logo.v1")
                            }
                        }
                        .disabled(!isInsightFreeUser && insightAnalysisGenerated)
                        .tint(.primary)
                    }
                }
                .background {
                    ZStack(alignment: .top) {
                        Color(uiColor: .systemGroupedBackground)
                            .ignoresSafeArea()

                        TopBarGradientOverlay(progress: overlayProgress, isAIConfigured: isAIConfigured)
                    }
                }
                .sheet(isPresented: $showPaywall) {
                    ProPaywallView()
                }
        }
    }

    private var isInsightFreeUser: Bool {
        userTier == .free
    }

    private var insightAnalysisGenerated: Bool {
        lastAnalyzedMonth == previousMonthKey
    }

    private var previousMonthKey: String {
        let calendar = Calendar.current
        let now = Date()

        guard let firstDayOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let firstDayOfLastMonth = calendar.date(byAdding: .month, value: -1, to: firstDayOfThisMonth) else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: firstDayOfLastMonth)
    }

    private var overviewSubtitle: String {
        if isInsightFreeUser {
            return "AI 月度分析需要 Geek"
        }
        return insightAnalysisGenerated ? "上月 AI 分析已生成" : "点击生成上月 AI 分析"
    }
}

struct RichInspirationTabView: View {
    @Binding var overlayProgress: CGFloat

    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false

    var body: some View {
        NavigationStack {
            CaptureInboxView(onScrollProgressChange: { overlayProgress = $0 })
                .navigationTitle("灵感")
                .navigationBarTitleDisplayMode(.automatic)
                .toolbarBackground(.hidden, for: .navigationBar)
                .background {
                    ZStack(alignment: .top) {
                        Color(uiColor: .systemGroupedBackground)
                            .ignoresSafeArea()

                        TopBarGradientOverlay(progress: overlayProgress, isAIConfigured: isAIConfigured)
                    }
                }
        }
    }
}

struct RichAITabView: View {
    @Binding var overlayProgress: CGFloat
    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false

    var body: some View {
        NavigationStack {
            DeadlinerAIPanel(
                showsDismissButton: false,
                embedInNavigationStack: false,
                bottomAccessoryInset: 16,
                useSheetDetents: false,
                onScrollProgressChange: { overlayProgress = $0 }
            )
            .toolbarBackground(.hidden, for: .navigationBar)
            .background {
                ZStack(alignment: .top) {
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()

                    TopBarGradientOverlay(progress: overlayProgress, isAIConfigured: isAIConfigured)
                }
            }
        }
    }
}
