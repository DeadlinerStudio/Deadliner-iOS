//
//  SearchHiddenMainTabDestinationView.swift
//  Deadliner
//
//  Created by Codex on 2026/7/18.
//

import SwiftUI

struct SearchHiddenMainTabDestinationView: View {
    let tab: RichMainTab
    @Binding var usesLocalAtmosphere: Bool

    @EnvironmentObject private var themeStore: ThemeStore
    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false
    @AppStorage(RichCompactLayout.settingKey) private var compactLayoutEnabled: Bool = false
    @AppStorage(DashboardHomeLayout.settingKey) private var dashboardHomeLayoutEnabled: Bool = DashboardHomeLayout.defaultValue

    @State private var homeQuery = ""
    @State private var homeTaskSegment: TaskSegment = .tasks
    @State private var homeCategoryFilter: CategoryFilter = .all
    @State private var homeAtmosphereTone: ImmersiveSurfaceTone = .accent
    @State private var homeOverlayProgress: CGFloat = 0
    @State private var overviewOverlayProgress: CGFloat = 0
    @State private var inspirationOverlayProgress: CGFloat = 0
    @State private var aiOverlayProgress: CGFloat = 0

    var body: some View {
        content
            .toolbarBackground(.hidden, for: .navigationBar)
            .deadlinerTopAtmosphereSceneBackground(
                progress: overlayProgress,
                isAIConfigured: isAIConfigured,
                semanticTone: atmosphereTone,
                semanticAccentColor: semanticAccentColor
            )
            .onAppear {
                usesLocalAtmosphere = true
            }
            .onDisappear {
                usesLocalAtmosphere = false
            }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home:
            homeContent
                .richCompactNavigationTitle(homeNavigationTitle)
        case .overview:
            OverviewView(
                onScrollProgressChange: { overviewOverlayProgress = $0 },
                compactLayoutProgress: compactLayoutEnabled ? overviewOverlayProgress : nil
            )
            .richCompactNavigationTitle("概览")
        case .inspiration:
            CaptureInboxView(
                onScrollProgressChange: { inspirationOverlayProgress = $0 }
            )
            .richCompactNavigationTitle("灵感")
        case .ai:
            DeadlinerAIPanel(
                showsDismissButton: false,
                embedInNavigationStack: false,
                bottomAccessoryInset: 16,
                useSheetDetents: false,
                onScrollProgressChange: { aiOverlayProgress = $0 }
            )
            .richCompactNavigationTitle("AI")
            .deadlinerNavigationTitleBarMinimizeOnScrollDown(true)
        case .search:
            ContentUnavailableView("浏览已在当前页面", systemImage: "magnifyingglass")
                .richCompactNavigationTitle("浏览")
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        if dashboardHomeLayoutEnabled {
            DashboardHomeView(
                query: $homeQuery,
                taskSegment: $homeTaskSegment,
                categoryFilter: $homeCategoryFilter,
                onScrollProgressChange: { homeOverlayProgress = $0 },
                onAtmosphereToneChange: { homeAtmosphereTone = $0 },
                compactLayoutProgress: compactLayoutEnabled ? homeOverlayProgress : nil
            )
        } else {
            HomeView(
                query: $homeQuery,
                taskSegment: $homeTaskSegment,
                categoryFilter: $homeCategoryFilter,
                onScrollProgressChange: { homeOverlayProgress = $0 },
                onAtmosphereToneChange: { homeAtmosphereTone = $0 },
                compactLayoutProgress: compactLayoutEnabled ? homeOverlayProgress : nil
            )
        }
    }

    private var homeNavigationTitle: String {
        dashboardHomeLayoutEnabled ? "今日" : "清单"
    }

    private var overlayProgress: CGFloat {
        switch tab {
        case .home:
            return homeOverlayProgress
        case .overview:
            return overviewOverlayProgress
        case .inspiration:
            return inspirationOverlayProgress
        case .ai:
            return aiOverlayProgress
        case .search:
            return 0
        }
    }

    private var atmosphereTone: ImmersiveSurfaceTone {
        switch tab {
        case .home:
            return homeAtmosphereTone
        case .overview, .inspiration, .ai:
            return .accent
        case .search:
            return .calm
        }
    }

    private var semanticAccentColor: Color? {
        switch tab {
        case .home:
            guard homeAtmosphereTone == .accent else {
                return nil
            }
            return tab.atmosphereAccentColor(for: themeStore.accentOption)
        case .overview, .inspiration, .ai, .search:
            return tab.atmosphereAccentColor(for: themeStore.accentOption)
        }
    }
}
