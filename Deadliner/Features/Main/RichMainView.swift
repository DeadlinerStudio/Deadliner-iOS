//
//  RichMainView.swift
//  Deadliner
//
//  Created by Codex on 2026/3/30.
//

import SwiftUI
import UIKit

struct MainView: View {
    @AppStorage("settings.home.style") private var homeStyleRawValue: String = HomeStyleOption.rich.rawValue

    var body: some View {
        switch HomeStyleOption(rawValue: homeStyleRawValue) ?? .rich {
        case .focus:
            FocusMainView()
        case .rich:
            RichMainView()
        }
    }
}

private enum RichMainTab: String, Hashable {
    case home
    case overview
    case archive
    case ai
    case search
}

struct RichMainView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var selectedTab: RichMainTab = .home
    @State private var homeTaskSegment: TaskSegment = .tasks
    @State private var homeQuery: String = ""

    @State private var searchQuery: String = ""
    @State private var archiveQuery: String = ""

    @State private var navGradientProgress: CGFloat = 0

    @State private var showAddEntrySheet = false
    @State private var addEntrySelection: TaskSegment = .tasks
    @State private var showSettingsSheet = false

    private let repo: TaskRepository = TaskRepository.shared
    private let widgetLaunchDefaults = UserDefaults(suiteName: "group.top.aritxonly.deadliner.group")
    private let widgetLaunchKey = "widget.pending_add_entry_type"

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                Tab("清单", systemImage: "checklist", value: RichMainTab.home) {
                    RichHomeTabView(
                        query: $homeQuery,
                        taskSegment: $homeTaskSegment,
                        overlayProgress: $navGradientProgress,
                        onSettingsTapped: {
                            showSettingsSheet = true
                        }
                    )
                }

                Tab("概览", systemImage: "chart.pie", value: RichMainTab.overview) {
                    RichOverviewTabView(
                        overlayProgress: $navGradientProgress
                    )
                }

                Tab("归档", systemImage: "archivebox", value: RichMainTab.archive) {
                    RichArchiveTabView(
                        query: $archiveQuery,
                        overlayProgress: $navGradientProgress
                    )
                }

                Tab("AI", systemImage: "sparkles", value: RichMainTab.ai) {
                    RichAITabView(
                        overlayProgress: $navGradientProgress
                    )
                }

                Tab("搜索", systemImage: "magnifyingglass", value: RichMainTab.search, role: .search) {
                    RichSearchTabView(
                        query: $searchQuery,
                        overlayProgress: $navGradientProgress
                    )
                }
            }

            if selectedTab == .home {
                floatingAddButton
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.28, extraBounce: 0), value: selectedTab)
        .sheet(isPresented: $showAddEntrySheet) {
            AddEntrySheetView(
                repository: repo,
                initialSelection: addEntrySelection,
                onDone: {
                    NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showSettingsSheet) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("用户与设置")
                    .navigationBarTitleDisplayMode(.large)
            }
            .presentationDetents([.large])
        }
        .onAppear {
            consumePendingWidgetLaunch()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            consumePendingWidgetLaunch()
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .task {
            applyTabBarAccent()
        }
        .onChange(of: themeStore.accentOption) { _, _ in
            applyTabBarAccent()
        }
    }

    private var floatingAddButton: some View {
        Button {
            presentAddSheet(selection: homeTaskSegment)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(themeStore.fabColor)
        .padding(.bottom, 68)
        .accessibilityLabel("添加")
    }

    private func presentAddSheet(selection: TaskSegment) {
        addEntrySelection = selection
        showAddEntrySheet = true
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "deadliner" else { return }
        guard url.host == "add" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let type = components?.queryItems?.first(where: { $0.name == "type" })?.value

        switch type {
        case "habit", "habits":
            selectedTab = .home
            homeTaskSegment = .habits
            presentAddSheet(selection: .habits)
        default:
            selectedTab = .home
            homeTaskSegment = .tasks
            presentAddSheet(selection: .tasks)
        }
    }

    private func consumePendingWidgetLaunch() {
        guard let rawValue = widgetLaunchDefaults?.string(forKey: widgetLaunchKey) else { return }
        widgetLaunchDefaults?.removeObject(forKey: widgetLaunchKey)

        switch rawValue {
        case "habit", "habits":
            selectedTab = .home
            homeTaskSegment = .habits
            presentAddSheet(selection: .habits)
        default:
            selectedTab = .home
            homeTaskSegment = .tasks
            presentAddSheet(selection: .tasks)
        }
    }

    private func applyTabBarAccent() {
        let selectedColor = UIColor(themeStore.accentColor)
        let unselectedColor = UIColor.secondaryLabel

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        configureTabBarItemAppearance(appearance.stackedLayoutAppearance, selectedColor: selectedColor, unselectedColor: unselectedColor)
        configureTabBarItemAppearance(appearance.inlineLayoutAppearance, selectedColor: selectedColor, unselectedColor: unselectedColor)
        configureTabBarItemAppearance(appearance.compactInlineLayoutAppearance, selectedColor: selectedColor, unselectedColor: unselectedColor)

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = selectedColor
        tabBar.unselectedItemTintColor = unselectedColor

        updateVisibleTabBars(appearance: appearance, selectedColor: selectedColor, unselectedColor: unselectedColor)
    }

    private func configureTabBarItemAppearance(
        _ itemAppearance: UITabBarItemAppearance,
        selectedColor: UIColor,
        unselectedColor: UIColor
    ) {
        itemAppearance.selected.iconColor = selectedColor
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        itemAppearance.normal.iconColor = unselectedColor
        itemAppearance.normal.titleTextAttributes = [.foregroundColor: unselectedColor]
    }

    private func updateVisibleTabBars(
        appearance: UITabBarAppearance,
        selectedColor: UIColor,
        unselectedColor: UIColor
    ) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                applyTabBarAppearanceRecursively(
                    from: window.rootViewController,
                    appearance: appearance,
                    selectedColor: selectedColor,
                    unselectedColor: unselectedColor
                )
            }
        }
    }

    private func applyTabBarAppearanceRecursively(
        from viewController: UIViewController?,
        appearance: UITabBarAppearance,
        selectedColor: UIColor,
        unselectedColor: UIColor
    ) {
        guard let viewController else { return }

        if let tabBarController = viewController as? UITabBarController {
            tabBarController.tabBar.standardAppearance = appearance
            tabBarController.tabBar.scrollEdgeAppearance = appearance
            tabBarController.tabBar.tintColor = selectedColor
            tabBarController.tabBar.unselectedItemTintColor = unselectedColor
            tabBarController.tabBar.setNeedsLayout()
            tabBarController.tabBar.layoutIfNeeded()
        }

        for child in viewController.children {
            applyTabBarAppearanceRecursively(
                from: child,
                appearance: appearance,
                selectedColor: selectedColor,
                unselectedColor: unselectedColor
            )
        }

        applyTabBarAppearanceRecursively(
            from: viewController.presentedViewController,
            appearance: appearance,
            selectedColor: selectedColor,
            unselectedColor: unselectedColor
        )
    }
}
