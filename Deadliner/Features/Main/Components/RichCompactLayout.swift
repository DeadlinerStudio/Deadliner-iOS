//
//  RichCompactLayout.swift
//  Deadliner
//
//  Created by Codex on 2026/5/13.
//

import SwiftUI

enum RichCompactLayout {
    static let settingKey = "settings.home.rich.compact_layout"
    static let expandedHeaderTopPadding: CGFloat = 0
    static let collapseStartProgress: CGFloat = 0.48
    static let collapseEndProgress: CGFloat = 0.8

    static func isCollapsed(progress: CGFloat) -> Bool {
        collapseProgress(for: progress) >= 1
    }

    static func collapseProgress(for progress: CGFloat) -> CGFloat {
        let normalized = (progress - collapseStartProgress) / (collapseEndProgress - collapseStartProgress)
        return min(max(normalized, 0), 1)
    }

    static func headerTopPadding(enabled: Bool, progress: CGFloat) -> CGFloat {
        guard enabled else { return -4 }
        return expandedHeaderTopPadding * (1 - collapseProgress(for: progress))
    }
}

enum RichTabBarTitles {
    static let settingKey = "settings.home.rich.tab_bar_titles_visible"
    static let defaultValue = true
}

enum SeperateSearchBar {
    static let settingKey = "settings.home.rich.seperate_search_bar"
    static let defaultValue = true
}

enum DashboardHomeLayout {
    static let settingKey = "settings.home.rich.experimental_dashboard"
    static let defaultValue = false
}

enum RichMainTab: String, CaseIterable, Codable, Hashable, Identifiable {
    case home
    case overview
    case inspiration
    case ai
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "清单"
        case .overview:
            return "概览"
        case .inspiration:
            return "灵感"
        case .ai:
            return "AI"
        case .search:
            return "浏览"
        }
    }

    var settingsTitle: String {
        switch self {
        case .home:
            return "主页"
        default:
            return title
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "checklist"
        case .overview:
            return "chart.pie"
        case .inspiration:
            return "pencil.and.outline"
        case .ai:
            return "sparkles"
        case .search:
            return "magnifyingglass"
        }
    }

    var canHide: Bool {
        self != .home && self != .search
    }

    var browseTint: Color {
        switch self {
        case .home:
            return ThemeDefaults.homeTaskSemanticAccent
        case .overview:
            return .teal
        case .inspiration:
            return .indigo
        case .ai:
            return .purple
        case .search:
            return .blue
        }
    }

    func atmosphereAccentColor(for themeAccentOption: ThemeAccentOption) -> Color? {
        guard themeAccentOption == .systemDefault else {
            return nil
        }

        return browseTint
    }

    func iconImage() -> Image {
        Image(systemName: systemImage)
    }
}

struct RichTabConfiguration: Codable, Equatable {
    var order: [RichMainTab]
    var hidden: Set<RichMainTab>
}

enum RichTabCustomization {
    static let settingKey = "settings.home.rich.tab_customization"

    static var defaultConfiguration: RichTabConfiguration {
        RichTabConfiguration(order: RichMainTab.allCases, hidden: [])
    }

    static var defaultRawValue: String {
        encode(defaultConfiguration)
    }

    static func decode(_ rawValue: String) -> RichTabConfiguration {
        guard !rawValue.isEmpty,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RichTabConfiguration.self, from: data) else {
            return defaultConfiguration
        }

        return normalized(decoded)
    }

    static func encode(_ configuration: RichTabConfiguration) -> String {
        let normalizedConfiguration = normalized(configuration)
        guard let data = try? JSONEncoder().encode(normalizedConfiguration),
              let rawValue = String(data: data, encoding: .utf8) else {
            return ""
        }

        return rawValue
    }

    static func visibleTabs(rawValue: String) -> [RichMainTab] {
        let configuration = normalized(decode(rawValue))
        let available = Set(availableTabs())
        let visible = configuration.order.filter { tab in
            available.contains(tab) && (!configuration.hidden.contains(tab) || !tab.canHide)
        }

        return visible.contains(.search) ? visible : visible + [.search]
    }

    static func hiddenTabs(rawValue: String) -> [RichMainTab] {
        let configuration = normalized(decode(rawValue))
        let available = Set(availableTabs())

        return configuration.order.filter { tab in
            available.contains(tab) && tab.canHide && configuration.hidden.contains(tab)
        }
    }

    static func availableTabs() -> [RichMainTab] {
        RichMainTab.allCases
    }

    static func normalizedConfiguration(rawValue: String) -> RichTabConfiguration {
        let configuration = normalized(decode(rawValue))
        let available = Set(availableTabs())
        let visibleOrder = configuration.order.filter { available.contains($0) }
        let unavailableOrder = configuration.order.filter { !available.contains($0) }

        return RichTabConfiguration(
            order: visibleOrder + unavailableOrder,
            hidden: configuration.hidden.filter { $0.canHide }
        )
    }

    private static func normalized(_ configuration: RichTabConfiguration) -> RichTabConfiguration {
        var seen = Set<RichMainTab>()
        var order = configuration.order.filter { tab in
            guard !seen.contains(tab) else { return false }
            seen.insert(tab)
            return true
        }

        for tab in RichMainTab.allCases where !seen.contains(tab) {
            order.append(tab)
        }

        return RichTabConfiguration(
            order: order,
            hidden: configuration.hidden.filter { $0.canHide }
        )
    }
}

enum ExperimentalHomeAtmosphereStyle: String, CaseIterable, Identifiable {
    case floatingGlow
    case semanticTint

    static let settingKey = "settings.home.rich.experimental_dashboard.atmosphere"
    static let defaultValue: ExperimentalHomeAtmosphereStyle = .semanticTint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .floatingGlow: return "幻彩"
        case .semanticTint: return "沉浸"
        }
    }
}

private struct RichCompactNavigationTitleModifier: ViewModifier {
    @AppStorage(RichCompactLayout.settingKey) private var compactLayoutEnabled = false

    let title: String
    let inlineWhenCompact: Bool
    let legacyDisplayMode: NavigationBarItem.TitleDisplayMode

    @ViewBuilder
    func body(content: Content) -> some View {
        if compactLayoutEnabled {
            content
                .navigationTitle(title)
                .toolbarTitleDisplayMode(inlineWhenCompact ? .inline : .inlineLarge)
        } else {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(legacyDisplayMode)
        }
    }
}

extension View {
    func richCompactNavigationTitle(
        _ title: String,
        inlineWhenCompact: Bool = false,
        legacyDisplayMode: NavigationBarItem.TitleDisplayMode = .automatic
    ) -> some View {
        modifier(
            RichCompactNavigationTitleModifier(
                title: title,
                inlineWhenCompact: inlineWhenCompact,
                legacyDisplayMode: legacyDisplayMode
            )
        )
    }
}
