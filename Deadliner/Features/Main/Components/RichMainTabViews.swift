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
    @Binding var categoryFilter: CategoryFilter
    @Binding var overlayProgress: CGFloat
    let atmosphereTone: ImmersiveSurfaceTone
    let onAtmosphereToneChange: (ImmersiveSurfaceTone) -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false
    @AppStorage(RichCompactLayout.settingKey) private var compactLayoutEnabled: Bool = false
    @AppStorage(DashboardHomeLayout.settingKey) private var dashboardHomeLayoutEnabled: Bool = DashboardHomeLayout.defaultValue
    @State private var selectionMode = false
    let showsHomeFilterToolbarItem: Bool
    let onHomeFilterTapped: () -> Void
    let onSettingsTapped: () -> Void
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    var showsAddToolbarItem = false
    var usesBottomAddToolbarItem = false
    var onAddTapped: () -> Void = {}
    var onTabBarPlacementChange: (TabBarPlacement?) -> Void = { _ in }
    var onComposerBottomChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            homeContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ComposerBottomBoundary(onChange: onComposerBottomChange)
            }
            .richCompactNavigationTitle(
                homeNavigationTitle,
                inlineWhenCompact: selectionMode
            )
            .navigationLargeTitleOverride(
                !selectionMode ? "Deadliner" : nil
            )
            .toolbar {
                if showsHomeFilterToolbarItem && !selectionMode {
                    ToolbarItem(placement: .topBarLeading) {
                        homeFilterButton
                    }
                }

                if showsAddToolbarItem && tabBarPlacement != .sidebar && !selectionMode {
                    ToolbarItem(placement: usesBottomAddToolbarItem ? .bottomBar : .topBarTrailing) {
                        Button(action: onAddTapped) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .tint(themeStore.fabColor)
                        .accessibilityLabel("添加")
                        .accessibilityIdentifier("home.toolbar.add")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    settingsButton
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .deadlinerTopAtmosphereSceneBackground(
                progress: overlayProgress,
                isAIConfigured: isAIConfigured,
                semanticTone: atmosphereTone,
                semanticAccentColor: homeTaskNormalSemanticAccent
            )
        }
        .deadlinerNavigationBarMinimizeOnScrollDown()
        .onChange(of: tabBarPlacement, initial: true) { _, placement in
            onTabBarPlacementChange(placement)
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        if dashboardHomeLayoutEnabled {
            DashboardHomeView(
                query: $query,
                taskSegment: $taskSegment,
                categoryFilter: $categoryFilter,
                onScrollProgressChange: { overlayProgress = $0 },
                onSelectionModeChange: { selectionMode = $0 },
                onAtmosphereToneChange: onAtmosphereToneChange,
                compactLayoutProgress: compactLayoutEnabled && !selectionMode ? overlayProgress : nil
            )
        } else {
            HomeView(
                query: $query,
                taskSegment: $taskSegment,
                categoryFilter: $categoryFilter,
                onScrollProgressChange: { overlayProgress = $0 },
                onSelectionModeChange: { selectionMode = $0 },
                onAtmosphereToneChange: onAtmosphereToneChange,
                compactLayoutProgress: compactLayoutEnabled && !selectionMode ? overlayProgress : nil
            )
        }
    }

    private var settingsButton: some View {
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
            .glassEffect(.regular.interactive(), in: Circle())
//            .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            .contentShape(Circle())
        }
        .accessibilityLabel("用户与设置")
        .accessibilityHint("打开用户面板与设置")
        .padding(.trailing, compactLayoutEnabled ? -8 : 0)
    }

    private var homeFilterButton: some View {
        Button {
            onHomeFilterTapped()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .tint(categoryFilter.isAll ? Color.primary : Color.accentColor)
        .accessibilityLabel("筛选")
        .accessibilityHint("按分类筛选主页内容")
    }

    private var homeNavigationTitle: String {
        dashboardHomeLayoutEnabled ? "今日" : "清单"
    }

    private var homeTaskNormalSemanticAccent: Color? {
        guard atmosphereTone == .accent else {
            return nil
        }

        return RichMainTab.home.atmosphereAccentColor(for: themeStore.accentOption)
    }
}

struct RichArchiveTabView: View {
    @Binding var query: String
    @Binding var overlayProgress: CGFloat

    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false
    @AppStorage(RichCompactLayout.settingKey) private var compactLayoutEnabled: Bool = false

    var body: some View {
        NavigationStack {
            ArchiveView(
                query: $query,
                onScrollProgressChange: { overlayProgress = $0 },
                compactLayoutProgress: compactLayoutEnabled ? overlayProgress : nil
            )
                .richCompactNavigationTitle("归档")
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
                .toolbarBackground(.hidden, for: .navigationBar)
                .deadlinerTopAtmosphereSceneBackground(
                    progress: overlayProgress,
                    isAIConfigured: isAIConfigured,
                    semanticTone: .neutral
                )
        }
    }
}

struct RichOverviewTabView: View {
    @Binding var overlayProgress: CGFloat

    @EnvironmentObject private var themeStore: ThemeStore
    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false
    @AppStorage(RichCompactLayout.settingKey) private var compactLayoutEnabled: Bool = false

    var body: some View {
        NavigationStack {
            OverviewView(
                onScrollProgressChange: { overlayProgress = $0 },
                compactLayoutProgress: compactLayoutEnabled ? overlayProgress : nil
            )
                .toolbarBackground(.hidden, for: .navigationBar)
                .deadlinerTopAtmosphereSceneBackground(
                    progress: overlayProgress,
                    isAIConfigured: isAIConfigured,
                    semanticTone: .accent,
                    semanticAccentColor: RichMainTab.overview.atmosphereAccentColor(
                        for: themeStore.accentOption
                    )
                )
        }
    }
}

struct RichInspirationTabView: View {
    @Binding var overlayProgress: CGFloat

    @EnvironmentObject private var themeStore: ThemeStore
    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false
    @State private var selectionMode = false

    var body: some View {
        NavigationStack {
            CaptureInboxView(
                onScrollProgressChange: { overlayProgress = $0 },
                onSelectionModeChange: { selectionMode = $0 }
            )
                .richCompactNavigationTitle(
                    "灵感",
                    inlineWhenCompact: selectionMode
                )
                .toolbarBackground(.hidden, for: .navigationBar)
                .deadlinerTopAtmosphereSceneBackground(
                    progress: overlayProgress,
                    isAIConfigured: isAIConfigured,
                    semanticTone: .accent,
                    semanticAccentColor: RichMainTab.inspiration.atmosphereAccentColor(
                        for: themeStore.accentOption
                    )
                )
        }
    }
}

struct RichAITabView: View {
    @Binding var overlayProgress: CGFloat

    @EnvironmentObject private var themeStore: ThemeStore
    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false

    var body: some View {
        NavigationStack {
            DeadlinerAIPanel(
                showsDismissButton: false,
                embedInNavigationStack: false,
                bottomAccessoryInset: FloatingComposerStyle.tabAccessoryInset,
                useSheetDetents: false,
                onScrollProgressChange: { overlayProgress = $0 }
            )
            .toolbarBackground(.hidden, for: .navigationBar)
            .deadlinerNavigationTitleBarMinimizeOnScrollDown(true)
            .deadlinerTopAtmosphereSceneBackground(
                progress: overlayProgress,
                isAIConfigured: isAIConfigured,
                semanticTone: .accent,
                semanticAccentColor: RichMainTab.ai.atmosphereAccentColor(
                    for: themeStore.accentOption
                )
            )
        }
    }
}
