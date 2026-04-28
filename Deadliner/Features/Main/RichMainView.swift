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
    case inspiration
    case ai
    case search
}

struct RichMainView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var selectedTab: RichMainTab = .home
    @State private var homeTaskSegment: TaskSegment = .tasks
    @State private var homeQuery: String = ""

    @State private var searchQuery: String = ""

    @State private var navGradientProgress: CGFloat = 0

    @State private var showAddEntrySheet = false
    @State private var addEntrySelection: TaskSegment = .tasks
    @State private var showSettingsSheet = false
    @State private var homeResetToken = 0
    @State private var overviewResetToken = 0
    @State private var inspirationResetToken = 0
    @State private var aiResetToken = 0
    @State private var searchResetToken = 0

    private let repo: TaskRepository = TaskRepository.shared
    private let widgetLaunchDefaults = UserDefaults(suiteName: "group.top.aritxonly.deadliner.group")
    private let widgetLaunchKey = "widget.pending_add_entry_type"
    private let widgetLaunchTaskDetailIdKey = "widget.pending_task_detail_id"

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
                    .id(homeResetToken)
                }

                Tab("概览", systemImage: "chart.pie", value: RichMainTab.overview) {
                    RichOverviewTabView(
                        overlayProgress: $navGradientProgress
                    )
                    .id(overviewResetToken)
                }

                Tab("灵感", systemImage: "pencil.and.outline", value: RichMainTab.inspiration) {
                    RichInspirationTabView(
                        overlayProgress: $navGradientProgress
                    )
                    .id(inspirationResetToken)
                }
                
                Tab("AI", image: "lifi.logo.v1", value: RichMainTab.ai) {
                    RichAITabView(
                        overlayProgress: $navGradientProgress
                    )
                    .id(aiResetToken)
                }

                Tab("搜索", systemImage: "magnifyingglass", value: RichMainTab.search, role: .search) {
                    RichSearchTabView(
                        query: $searchQuery,
                        overlayProgress: $navGradientProgress
                    )
                    .id(searchResetToken)
                }
            }

            if selectedTab == .home {
                floatingAddButton
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .animation(.smooth(duration: 0.28, extraBounce: 0), value: selectedTab)
        .onChange(of: selectedTab) { _, newTab in
            resetScroll(for: newTab)
        }
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
            applyTabBarSelectedTint()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            consumePendingWidgetLaunch()
            applyTabBarSelectedTint()
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onChange(of: themeStore.accentOption) { _, _ in
            applyTabBarSelectedTint()
        }
    }

    private var floatingAddButton: some View {
        Button {
            presentAddSheet(selection: homeTaskSegment)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 48, height: 48)
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
        if url.host == "ai" {
            selectedTab = .ai
            return
        }
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
        case "open_ai":
            selectedTab = .ai
        case "open_inspiration":
            selectedTab = .inspiration
        case "open_home":
            selectedTab = .home
            homeTaskSegment = .tasks
        case "open_home_or_urgent":
            selectedTab = .home
            homeTaskSegment = .tasks
            let rawTaskId = widgetLaunchDefaults?.object(forKey: widgetLaunchTaskDetailIdKey)
            let taskId: Int64? = {
                if let v = rawTaskId as? Int64 { return v }
                if let v = rawTaskId as? Int { return Int64(v) }
                if let v = rawTaskId as? NSNumber { return v.int64Value }
                return nil
            }()
            if let taskId {
                widgetLaunchDefaults?.removeObject(forKey: widgetLaunchTaskDetailIdKey)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(
                        name: .ddlOpenTaskDetail,
                        object: nil,
                        userInfo: ["taskId": taskId]
                    )
                }
            }
        case "open_add_habits", "habit", "habits":
            selectedTab = .home
            homeTaskSegment = .habits
            presentAddSheet(selection: .habits)
        case "open_add_tasks":
            selectedTab = .home
            homeTaskSegment = .tasks
            presentAddSheet(selection: .tasks)
        default:
            selectedTab = .home
            homeTaskSegment = .tasks
            presentAddSheet(selection: .tasks)
        }
    }

    private func applyTabBarSelectedTint() {
        let selectedColor = UIColor(themeStore.accentColor)
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        applySelectedColor(to: appearance.stackedLayoutAppearance, selectedColor: selectedColor)
        applySelectedColor(to: appearance.inlineLayoutAppearance, selectedColor: selectedColor)
        applySelectedColor(to: appearance.compactInlineLayoutAppearance, selectedColor: selectedColor)

        let tabBarProxy = UITabBar.appearance()
        tabBarProxy.standardAppearance = appearance
        tabBarProxy.scrollEdgeAppearance = appearance
        tabBarProxy.tintColor = selectedColor
        tabBarProxy.unselectedItemTintColor = nil
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                applyTabBarTintRecursively(
                    from: window.rootViewController,
                    selectedColor: selectedColor,
                    appearance: appearance
                )
            }
        }
    }

    private func applySelectedColor(to itemAppearance: UITabBarItemAppearance, selectedColor: UIColor) {
        itemAppearance.selected.iconColor = selectedColor
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
    }

    private func applyTabBarTintRecursively(
        from viewController: UIViewController?,
        selectedColor: UIColor,
        appearance: UITabBarAppearance
    ) {
        guard let viewController else { return }
        if let tabBarController = viewController as? UITabBarController {
            tabBarController.tabBar.standardAppearance = appearance
            tabBarController.tabBar.scrollEdgeAppearance = appearance
            tabBarController.tabBar.tintColor = selectedColor
            tabBarController.tabBar.unselectedItemTintColor = nil
            tabBarController.tabBar.setNeedsLayout()
            tabBarController.tabBar.layoutIfNeeded()
        }
        for child in viewController.children {
            applyTabBarTintRecursively(from: child, selectedColor: selectedColor, appearance: appearance)
        }
        applyTabBarTintRecursively(from: viewController.presentedViewController, selectedColor: selectedColor, appearance: appearance)
    }

    private func resetScroll(for tab: RichMainTab) {
        switch tab {
        case .home:
            homeResetToken += 1
        case .overview:
            overviewResetToken += 1
        case .inspiration:
            inspirationResetToken += 1
        case .ai:
            aiResetToken += 1
        case .search:
            searchResetToken += 1
        }
    }

}
