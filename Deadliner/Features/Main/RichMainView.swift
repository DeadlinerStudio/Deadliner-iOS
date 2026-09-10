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

struct RichMainView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false
    @AppStorage(RichTabBarTitles.settingKey) private var richTabBarTitlesVisible: Bool = RichTabBarTitles.defaultValue
    @AppStorage(SeperateSearchBar.settingKey) private var seperateSearchBarVisible: Bool = SeperateSearchBar.defaultValue
    @AppStorage(DashboardHomeLayout.settingKey) private var dashboardHomeLayoutEnabled: Bool = DashboardHomeLayout.defaultValue
    @AppStorage(RichTabCustomization.settingKey) private var richTabCustomizationRaw = RichTabCustomization.defaultRawValue

    @State private var selectedTab: RichMainTab = .home
    @State private var homeTaskSegment: TaskSegment = .tasks
    @State private var homeCategoryFilter: CategoryFilter = .all
    @State private var homeAtmosphereTone: ImmersiveSurfaceTone = .accent
    @State private var homeQuery: String = ""

    @State private var searchQuery: String = ""

    @State private var navGradientProgress: CGFloat = 0

    @State private var showAddEntrySheet = false
    @State private var addEntrySelection: TaskSegment = .tasks
    @State private var showSettingsSheet = false
    @State private var showQuickInspirationSheet = false
    @State private var showHomeCategoryFilterSheet = false
    @State private var homeResetToken = 0
    @State private var overviewResetToken = 0
    @State private var inspirationResetToken = 0
    @State private var aiResetToken = 0
    @State private var searchResetToken = 0
    @State private var searchFocusRequestToken = 0
    @State private var searchUsesLocalAtmosphere = false

    private let widgetLaunchDefaults = UserDefaults(suiteName: "group.top.aritxonly.deadliner.group")
    private let widgetLaunchKey = "widget.pending_add_entry_type"
    private let widgetLaunchTaskDetailUIDKey = "widget.pending_task_detail_uid"

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                if #available(iOS 27.0, *), seperateSearchBarVisible {
                    ForEach(visibleTabs) { tab in
                        if richTabBarTitlesVisible {
                            titledProminentSearchTab(for: tab)
                        } else {
                            iconOnlyProminentSearchTab(for: tab)
                        }
                    }
                } else {
                    ForEach(visibleTabs) { tab in
                        if richTabBarTitlesVisible {
                            titledTab(for: tab)
                        } else {
                            iconOnlyTab(for: tab)
                        }
                    }
                }
            }
            .background {
                RichTabBarTapObserver(
                    visibleTabs: visibleTabs,
                    selectedTab: selectedTab,
                    onReselect: handleTabReselect
                )
            }

            if selectedTab == .home {
                floatingAddButton
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .animation(.smooth(duration: 0.28, extraBounce: 0), value: selectedTab)
        .onChange(of: selectedTab) { oldTab, newTab in
            navGradientProgress = 0
            if newTab != .search {
                searchUsesLocalAtmosphere = false
            }
            if oldTab != .search, newTab == .search, !seperateSearchBarVisible {
                searchResetToken += 1
            }
        }
        .sheet(isPresented: $showAddEntrySheet) {
            AddEntrySheetView(
                repository: PersistenceStores.tasks,
                initialSelection: addEntrySelection
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showQuickInspirationSheet) {
            QuickInspirationCaptureSheet { text in
                CaptureStore.shared.addItem(text: text)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettingsSheet) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("用户与设置")
                    .navigationBarTitleDisplayMode(.large)
            }
            .deadlinerContainerSystemBackground()
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showHomeCategoryFilterSheet) {
            CategoryFilterSheet(selectedFilter: $homeCategoryFilter)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            consumePendingWidgetLaunch()
            applyTabBarAppearance()
            repairSelectedTabIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            consumePendingWidgetLaunch()
            applyTabBarAppearance()
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onChange(of: themeStore.accentOption) { _, _ in
            applyTabBarAppearance()
        }
        .onChange(of: richTabCustomizationRaw) { _, _ in
            repairSelectedTabIfNeeded()
        }
    }

    @TabContentBuilder<RichMainTab>
    private func titledTab(for tab: RichMainTab) -> some TabContent<RichMainTab> {
        switch tab {
        case .home:
            Tab(value: RichMainTab.home) {
                homeTabContent
            } label: {
                Label {
                    Text(homeTabTitle)
                } icon: {
                    RichMainTab.home.iconImage()
                }
            }
        case .overview:
            Tab("概览", systemImage: "chart.pie", value: RichMainTab.overview) {
                overviewTabContent
            }
        case .inspiration:
            Tab("灵感", systemImage: "pencil.and.outline", value: RichMainTab.inspiration) {
                inspirationTabContent
            }
        case .ai:
            Tab("AI", image: "lifi.logo.v1", value: RichMainTab.ai) {
                aiTabContent
            }
        case .search:
            Tab("浏览", systemImage: "magnifyingglass", value: RichMainTab.search, role: .search) {
                searchTabContent
            }
        }
    }

    @TabContentBuilder<RichMainTab>
    private func iconOnlyTab(for tab: RichMainTab) -> some TabContent<RichMainTab> {
        switch tab {
        case .home:
            Tab(value: RichMainTab.home) {
                homeTabContent
            } label: {
                RichMainTab.home.iconImage()
                    .accessibilityLabel(homeTabTitle)
            }
        case .overview:
            Tab(value: RichMainTab.overview) {
                overviewTabContent
            } label: {
                Image(systemName: "chart.pie")
                    .accessibilityLabel("概览")
            }
        case .inspiration:
            Tab(value: RichMainTab.inspiration) {
                inspirationTabContent
            } label: {
                Image(systemName: "pencil.and.outline")
                    .accessibilityLabel("灵感")
            }
        case .ai:
            Tab(value: RichMainTab.ai) {
                aiTabContent
            } label: {
                Image("lifi.logo.v1")
                    .accessibilityLabel("AI")
            }
        case .search:
            Tab(value: RichMainTab.search, role: .search) {
                searchTabContent
            } label: {
                Image(systemName: "magnifyingglass")
                    .accessibilityLabel("浏览")
            }
        }
    }

    @available(iOS 27.0, *)
    @TabContentBuilder<RichMainTab>
    private func titledProminentSearchTab(for tab: RichMainTab) -> some TabContent<RichMainTab> {
        switch tab {
        case .home:
            Tab(value: RichMainTab.home) {
                homeTabContent
            } label: {
                Label {
                    Text(homeTabTitle)
                } icon: {
                    RichMainTab.home.iconImage()
                }
            }
        case .overview:
            Tab("概览", systemImage: "chart.pie", value: RichMainTab.overview) {
                overviewTabContent
            }
        case .inspiration:
            Tab("灵感", systemImage: "pencil.and.outline", value: RichMainTab.inspiration) {
                inspirationTabContent
            }
        case .ai:
            Tab("AI", image: "lifi.logo.v1", value: RichMainTab.ai) {
                aiTabContent
            }
        case .search:
            Tab("浏览", systemImage: "magnifyingglass", value: RichMainTab.search, role: .prominent) {
                searchTabContent
            }
        }
    }

    @available(iOS 27.0, *)
    @TabContentBuilder<RichMainTab>
    private func iconOnlyProminentSearchTab(for tab: RichMainTab) -> some TabContent<RichMainTab> {
        switch tab {
        case .home:
            Tab(value: RichMainTab.home) {
                homeTabContent
            } label: {
                RichMainTab.home.iconImage()
                    .accessibilityLabel(homeTabTitle)
            }
        case .overview:
            Tab(value: RichMainTab.overview) {
                overviewTabContent
            } label: {
                Image(systemName: "chart.pie")
                    .accessibilityLabel("概览")
            }
        case .inspiration:
            Tab(value: RichMainTab.inspiration) {
                inspirationTabContent
            } label: {
                Image(systemName: "pencil.and.outline")
                    .accessibilityLabel("灵感")
            }
        case .ai:
            Tab(value: RichMainTab.ai) {
                aiTabContent
            } label: {
                Image("lifi.logo.v1")
                    .accessibilityLabel("AI")
            }
        case .search:
            Tab(value: RichMainTab.search, role: .prominent) {
                searchTabContent
            } label: {
                Image(systemName: "magnifyingglass")
                    .accessibilityLabel("浏览")
            }
        }
    }

    private var homeTabContent: some View {
        RichHomeTabView(
            query: $homeQuery,
            taskSegment: $homeTaskSegment,
            categoryFilter: $homeCategoryFilter,
            overlayProgress: $navGradientProgress,
            atmosphereTone: homeAtmosphereTone,
            onAtmosphereToneChange: { homeAtmosphereTone = $0 },
            showsHomeFilterToolbarItem: !dashboardHomeLayoutEnabled,
            onHomeFilterTapped: {
                showHomeCategoryFilterSheet = true
            },
            onSettingsTapped: {
                showSettingsSheet = true
            }
        )
        .id(homeResetToken)
    }

    private var overviewTabContent: some View {
        RichOverviewTabView(
            overlayProgress: $navGradientProgress
        )
        .id(overviewResetToken)
    }

    private var inspirationTabContent: some View {
        RichInspirationTabView(
            overlayProgress: $navGradientProgress
        )
        .id(inspirationResetToken)
    }

    private var aiTabContent: some View {
        RichAITabView(
            overlayProgress: $navGradientProgress
        )
        .id(aiResetToken)
    }

    private var searchTabContent: some View {
        RichSearchTabView(
            query: $searchQuery,
            overlayProgress: $navGradientProgress,
            focusRequestToken: searchFocusRequestToken,
            usesLocalAtmosphere: $searchUsesLocalAtmosphere,
            hiddenMainTabs: hiddenMainTabs
        )
        .id(searchResetToken)
    }

    private var visibleTabs: [RichMainTab] {
        RichTabCustomization.visibleTabs(rawValue: richTabCustomizationRaw)
    }

    private var hiddenMainTabs: [RichMainTab] {
        RichTabCustomization.hiddenTabs(rawValue: richTabCustomizationRaw)
    }

    private var homeTabTitle: String {
        dashboardHomeLayoutEnabled ? "今日" : "清单"
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
            openAIEntryPoint()
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
            openAIEntryPoint()
        case "open_inspiration":
            selectedTab = .inspiration
        case "open_inspiration_composer":
            showQuickInspirationSheet = true
        case "open_home":
            selectedTab = .home
            homeTaskSegment = .tasks
        case "open_home_or_urgent":
            selectedTab = .home
            homeTaskSegment = .tasks
            if let taskUID = widgetLaunchDefaults?.string(forKey: widgetLaunchTaskDetailUIDKey) {
                widgetLaunchDefaults?.removeObject(forKey: widgetLaunchTaskDetailUIDKey)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(
                        name: .ddlOpenTaskDetail,
                        object: nil,
                        userInfo: ["taskId": taskUID]
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

    private func applyTabBarAppearance() {
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

    private func openAIEntryPoint() {
        if visibleTabs.contains(.ai) {
            selectedTab = .ai
        } else {
            selectedTab = .search
        }
    }

    private func handleTabReselect(_ tab: RichMainTab) {
        guard #available(iOS 27.0, *) else { return }
        if tab == .search {
            searchFocusRequestToken += 1
        } else {
            resetScroll(for: tab)
        }
    }

    private func repairSelectedTabIfNeeded() {
        guard !visibleTabs.contains(selectedTab) else { return }
        selectedTab = visibleTabs.first ?? .search
    }

}

private struct RichTabBarTapObserver: UIViewRepresentable {
    let visibleTabs: [RichMainTab]
    let selectedTab: RichMainTab
    let onReselect: (RichMainTab) -> Void

    func makeUIView(context: Context) -> RichTabBarTapObserverView {
        let view = RichTabBarTapObserverView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: RichTabBarTapObserverView, context: Context) {
        uiView.configure(
            visibleTabs: visibleTabs,
            selectedTab: selectedTab,
            onReselect: onReselect
        )
    }
}

private final class RichTabBarTapObserverView: UIView, UIGestureRecognizerDelegate {
    private weak var observedTabBar: UITabBar?
    private var observedCandidateControls: [UIControl] = []
    private var observedLogicalIndices: [Int] = []
    private var tabBarTapGestureRecognizer: UITapGestureRecognizer?
    private var visibleTabs: [RichMainTab] = []
    private var selectedTab: RichMainTab = .home
    private var onReselect: ((RichMainTab) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.attachIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachIfNeeded()
    }

    func configure(
        visibleTabs: [RichMainTab],
        selectedTab: RichMainTab,
        onReselect: @escaping (RichMainTab) -> Void
    ) {
        self.visibleTabs = visibleTabs
        self.selectedTab = selectedTab
        self.onReselect = onReselect

        DispatchQueue.main.async { [weak self] in
            self?.attachIfNeeded()
        }
    }

    private func attachIfNeeded() {
        guard let tabBar = findTabBar() else { return }
        if observedTabBar !== tabBar {
            unbindTabBarCandidates()
            removeTabBarTapGesture()
            observedTabBar = tabBar
        }
        bindTabBarCandidatesIfNeeded()
        installTabBarTapGestureIfNeeded()
    }

    private func bindTabBarCandidatesIfNeeded() {
        guard let tabBar = observedTabBar else { return }
        let directSubviews = tabBar.subviews
            .filter { $0.bounds.width > 0 && !$0.isHidden }
            .sorted { $0.frame.minX < $1.frame.minX }

        let candidates = directSubviews.filter { view in
            let className = NSStringFromClass(type(of: view)).lowercased()
            return className.contains("tab") || className.contains("button") || className.contains("item")
        }

        let platterCandidates = platterCandidateViews(from: directSubviews)
        let resolvedCandidates: [UIView]
        if !platterCandidates.isEmpty {
            resolvedCandidates = platterCandidates
        } else if !candidates.isEmpty {
            resolvedCandidates = candidates
        } else {
            resolvedCandidates = directSubviews
        }
        let resolvedControls = resolvedCandidates.compactMap { $0 as? UIControl }
        guard !resolvedControls.isEmpty else { return }
        guard resolvedControls.map(ObjectIdentifier.init) != observedCandidateControls.map(ObjectIdentifier.init) else { return }

        let logicalIndices = logicalTabIndices(for: resolvedControls)

        unbindTabBarCandidates()
        observedCandidateControls = resolvedControls
        observedLogicalIndices = logicalIndices
    }

    private func platterCandidateViews(from directSubviews: [UIView]) -> [UIView] {
        guard let platterView = directSubviews.first(where: {
            NSStringFromClass(type(of: $0)).lowercased().contains("platter")
        }) else {
            return []
        }

        let levelOne = platterView.subviews
            .filter { $0.bounds.width > 0 && !$0.isHidden }
            .sorted { $0.frame.minX < $1.frame.minX }

        let contentLikeLevelOne = levelOne.filter { view in
            let className = NSStringFromClass(type(of: view)).lowercased()
            return className.contains("contentview")
        }

        let levelTwoParents = contentLikeLevelOne.isEmpty ? levelOne : contentLikeLevelOne
        let levelTwo = levelTwoParents
            .flatMap(visibleSubviews(of:))
            .sorted { lhs, rhs in
                if lhs.frame.minY == rhs.frame.minY {
                    return lhs.frame.minX < rhs.frame.minX
                }
                return lhs.frame.minY < rhs.frame.minY
            }

        let itemLikeLevelTwo = candidateItemViews(from: levelTwo, containerWidth: platterView.bounds.width)
        if itemLikeLevelTwo.count >= visibleTabs.count {
            return itemLikeLevelTwo
        }

        let levelThree = levelTwo
            .flatMap(visibleSubviews(of:))
            .sorted { lhs, rhs in
                if lhs.frame.minY == rhs.frame.minY {
                    return lhs.frame.minX < rhs.frame.minX
                }
                return lhs.frame.minY < rhs.frame.minY
            }

        let itemLikeLevelThree = candidateItemViews(from: levelThree, containerWidth: platterView.bounds.width)
        if itemLikeLevelThree.count >= visibleTabs.count {
            return itemLikeLevelThree
        }

        return levelTwo
    }

    private func visibleSubviews(of view: UIView) -> [UIView] {
        view.subviews.filter { $0.bounds.width > 0 && !$0.isHidden }
    }

    private func candidateItemViews(from views: [UIView], containerWidth: CGFloat) -> [UIView] {
        views.filter { view in
            let className = NSStringFromClass(type(of: view)).lowercased()
            let width = view.bounds.width
            let looksLikeItemClass =
                className.contains("item") ||
                className.contains("button") ||
                className.contains("label") ||
                className.contains("icon")
            let looksLikeSegment =
                width > 24 &&
                width < containerWidth * 0.6 &&
                view.bounds.height > 20
            return looksLikeItemClass || looksLikeSegment
        }
    }

    private func logicalTabIndices(for controls: [UIControl]) -> [Int] {
        var logicalCenters: [CGFloat] = []
        let tolerance: CGFloat = 2

        return controls.map { control in
            let centerX = control.frame.midX
            if let existingIndex = logicalCenters.firstIndex(where: { abs($0 - centerX) <= tolerance }) {
                return existingIndex
            }
            logicalCenters.append(centerX)
            logicalCenters.sort()
            return logicalCenters.firstIndex(where: { abs($0 - centerX) <= tolerance }) ?? 0
        }
    }

    private func unbindTabBarCandidates() {
        observedCandidateControls.removeAll()
        observedLogicalIndices.removeAll()
    }

    private func installTabBarTapGestureIfNeeded() {
        guard let tabBar = observedTabBar else { return }
        guard tabBarTapGestureRecognizer?.view !== tabBar else { return }

        removeTabBarTapGesture()

        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTabBarTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        tabBar.addGestureRecognizer(recognizer)
        tabBarTapGestureRecognizer = recognizer
    }

    private func removeTabBarTapGesture() {
        if let recognizer = tabBarTapGestureRecognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
        tabBarTapGestureRecognizer = nil
    }

    private func frameForLogicalTabIndex(_ logicalIndex: Int) -> CGRect? {
        let frames = zip(observedCandidateControls, observedLogicalIndices)
            .filter { _, index in index == logicalIndex }
            .map(\.0.frame)

        guard !frames.isEmpty else {
            return nil
        }

        let bestFrame = frames.min { lhs, rhs in
            if lhs.width == rhs.width {
                return lhs.minX < rhs.minX
            }
            return lhs.width < rhs.width
        }
        return bestFrame
    }

    @objc
    private func handleTabBarTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        guard selectedTab == .search else { return }
        guard let searchIndex = visibleTabs.firstIndex(of: .search) else { return }
        guard let searchFrame = frameForLogicalTabIndex(searchIndex) else { return }

        let location = recognizer.location(in: observedTabBar)
        guard searchFrame.contains(location) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onReselect?(.search)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    private func findTabBar() -> UITabBar? {
        guard let rootViewController = window?.rootViewController else { return nil }
        return findTabBar(in: rootViewController)
    }

    private func findTabBar(in viewController: UIViewController) -> UITabBar? {
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController.tabBar
        }

        for child in viewController.children {
            if let tabBar = findTabBar(in: child) {
                return tabBar
            }
        }

        if let presentedViewController = viewController.presentedViewController {
            return findTabBar(in: presentedViewController)
        }

        return nil
    }
}
