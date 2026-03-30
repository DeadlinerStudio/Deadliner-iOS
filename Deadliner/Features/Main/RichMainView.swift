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

private enum SearchScope: String, CaseIterable, Identifiable {
    case all = "全部"
    case active = "清单"
    case archive = "归档"

    var id: String { rawValue }
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

                Tab("概览", systemImage: "chart.bar.xaxis", value: RichMainTab.overview) {
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
        let tabBarAppearance = UITabBar.appearance()
        tabBarAppearance.tintColor = UIColor(themeStore.accentColor)
    }
}

private struct RichHomeTabView: View {
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

private struct RichArchiveTabView: View {
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

private struct RichOverviewTabView: View {
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
                            Image(systemName: isInsightFreeUser ? "lock.fill" : (insightAnalysisGenerated ? "checkmark.circle.fill" : "sparkles"))
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

private struct RichAITabView: View {
    @Binding var overlayProgress: CGFloat
    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false

    var body: some View {
        NavigationStack {
            DeadlinerAIPanel(
                showsDismissButton: false,
                embedInNavigationStack: false,
                bottomAccessoryInset: 16
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

private struct RichSearchTabView: View {
    @Binding var query: String
    @Binding var overlayProgress: CGFloat

    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false
    @State private var scope: SearchScope = .all
    @State private var activeTasks: [DDLItem] = []
    @State private var activeHabits: [Habit] = []
    @State private var archivedTasks: [DDLItem] = []
    @State private var archivedHabits: [Habit] = []
    @State private var isLoading = true
    @State private var selectedTaskForEdit: DDLItem?
    @State private var selectedHabitForEdit: Habit?

    private let taskRepo = TaskRepository.shared
    private let habitRepo = HabitRepository.shared

    var body: some View {
        NavigationStack {
            List {
                Picker("搜索范围", selection: $scope) {
                    ForEach(SearchScope.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .glassEffect()
                .textCase(nil)
                .padding(.horizontal, 16)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if isLoading {
                    ProgressView("搜索索引加载中...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .padding(.top, 24)
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchHintRow
                } else {
                    resultsSections
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.automatic)
            .searchable(text: $query, prompt: "搜索任务、习惯、归档内容...")
            .toolbarBackground(.hidden, for: .navigationBar)
            .background {
                ZStack(alignment: .top) {
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()

                    TopBarGradientOverlay(progress: overlayProgress, isAIConfigured: isAIConfigured)
                }
            }
            .task {
                await reload()
            }
            .refreshable {
                await reload()
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                max(0, geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, newValue in
                let p = min(max(newValue / 120, 0), 1)
                overlayProgress = p
            }
            .onReceive(NotificationCenter.default.publisher(for: .ddlDataChanged)) { _ in
                Task { await reload() }
            }
            .sheet(item: $selectedTaskForEdit) { item in
                EditTaskSheetView(
                    repository: TaskRepository.shared,
                    item: item,
                    onDone: {
                        NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
                    }
                )
            }
            .sheet(item: $selectedHabitForEdit) { habit in
                HabitEditorSheetView(
                    mode: .edit(original: habit),
                    initialDraft: .fromHabit(habit),
                    onDone: {
                        NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var resultsSections: some View {
        let taskMatches = scope.allowsActive ? searchResults(in: activeTasks) : []
        let habitMatches = scope.allowsActive ? searchResults(in: activeHabits) : []
        let archivedTaskMatches = scope.allowsArchive ? searchResults(in: archivedTasks, archived: true) : []
        let archivedHabitMatches = scope.allowsArchive ? searchResults(in: archivedHabits, archived: true) : []

        if taskMatches.isEmpty && habitMatches.isEmpty && archivedTaskMatches.isEmpty && archivedHabitMatches.isEmpty {
            emptySearchRow
        } else {
            if !taskMatches.isEmpty {
                resultSection(title: "任务", systemImage: "checklist", tint: .blue, items: taskMatches)
            }

            if !habitMatches.isEmpty {
                resultSection(title: "习惯", systemImage: "leaf", tint: .green, items: habitMatches)
            }

            if !archivedTaskMatches.isEmpty {
                resultSection(title: "归档任务", systemImage: "archivebox", tint: .gray, items: archivedTaskMatches)
            }

            if !archivedHabitMatches.isEmpty {
                resultSection(title: "归档习惯", systemImage: "archivebox.fill", tint: .gray, items: archivedHabitMatches)
            }
        }
    }

    private var searchHintRow: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("搜索整个 Deadliner")
                .font(.headline)
            Text("支持搜索任务、习惯和归档内容。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var emptySearchRow: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("没有找到匹配内容")
                .font(.headline)
            Text("试试换个关键词，或切换搜索范围。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func resultSection(
        title: String,
        systemImage: String,
        tint: Color,
        items: [SearchResultRowModel]
    ) -> some View {
        Section {
            ForEach(items) { item in
                Button {
                    openSearchResult(item)
                } label: {
                    SearchResultRow(item: item, tint: tint)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        } header: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
                .textCase(nil)
                .padding(.leading, 16)
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let tasks = taskRepo.getAllDDLs()
            async let habits = habitRepo.getAllHabits()
            let (allTasks, allHabits) = try await (tasks, habits)

            activeTasks = allTasks.filter { !$0.isArchived }
            archivedTasks = allTasks.filter { $0.isArchived }
            activeHabits = allHabits.filter { $0.status != .archived }
            archivedHabits = allHabits.filter { $0.status == .archived }
        } catch {
            print("RichSearchTab reload failed: \(error)")
        }
    }

    private func searchResults(in tasks: [DDLItem], archived: Bool = false) -> [SearchResultRowModel] {
        let tokens = queryTokens

        return tasks.compactMap { item in
            let title = item.name
            let subtitle = taskSubtitle(for: item, archived: archived)
            let detail = [item.note, item.endTime, item.startTime, item.completeTime]
                .joined(separator: "\n")
            let score = searchScore(title: title, subtitle: subtitle, detail: detail, tokens: tokens)
            guard score > 0 else { return nil }

            return SearchResultRowModel(
                title: title,
                subtitle: subtitle,
                badge: archived ? "归档" : "清单",
                sortScore: score,
                payload: .task(item)
            )
        }
        .sorted(by: searchSortComparator)
    }

    private func searchResults(in habits: [Habit], archived: Bool = false) -> [SearchResultRowModel] {
        let tokens = queryTokens

        return habits.compactMap { habit in
            let title = habit.name
            let subtitle = habitSubtitle(for: habit)
            let detail = [habit.description ?? "", habit.updatedAt, habit.createdAt, habitPeriodText(for: habit)]
                .joined(separator: "\n")
            let score = searchScore(title: title, subtitle: subtitle, detail: detail, tokens: tokens)
            guard score > 0 else { return nil }

            return SearchResultRowModel(
                title: title,
                subtitle: subtitle,
                badge: archived ? "归档" : "清单",
                sortScore: score,
                payload: .habit(habit)
            )
        }
        .sorted(by: searchSortComparator)
    }

    private var queryTokens: [String] {
        query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var searchSortComparator: (SearchResultRowModel, SearchResultRowModel) -> Bool {
        { lhs, rhs in
            if lhs.sortScore != rhs.sortScore {
                return lhs.sortScore > rhs.sortScore
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func searchScore(title: String, subtitle: String, detail: String, tokens: [String]) -> Int {
        guard !tokens.isEmpty else { return 0 }

        let titleLower = title.lowercased()
        let subtitleLower = subtitle.lowercased()
        let detailLower = detail.lowercased()

        var score = 0

        for token in tokens {
            guard titleLower.contains(token) || subtitleLower.contains(token) || detailLower.contains(token) else {
                return 0
            }

            if titleLower == token {
                score += 140
            } else if titleLower.hasPrefix(token) {
                score += 100
            } else if titleLower.contains(token) {
                score += 70
            }

            if subtitleLower.contains(token) {
                score += 28
            }

            if detailLower.contains(token) {
                score += 12
            }
        }

        if tokens.count > 1 {
            score += 16
        }

        return score
    }

    private func taskSubtitle(for item: DDLItem, archived: Bool) -> String {
        if !item.note.isEmpty {
            return item.note
        }

        if archived {
            return item.completeTime.isEmpty ? "已归档" : "完成于 \(item.completeTime)"
        }

        if !item.endTime.isEmpty {
            return item.endTime
        }

        return "无截止时间"
    }

    private func habitSubtitle(for habit: Habit) -> String {
        if let description = habit.description, !description.isEmpty {
            return description
        }

        return habitPeriodText(for: habit)
    }

    private func habitPeriodText(for habit: Habit) -> String {
        switch habit.period {
        case .daily: return "每日"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .ebbinghaus: return "艾宾浩斯"
        default: return "习惯"
        }
    }

    private func openSearchResult(_ item: SearchResultRowModel) {
        switch item.payload {
        case .task(let task):
            selectedTaskForEdit = task
        case .habit(let habit):
            selectedHabitForEdit = habit
        }
    }
}

private struct SearchResultRowModel: Identifiable {
    enum Payload {
        case task(DDLItem)
        case habit(Habit)
    }

    let id = UUID()
    let title: String
    let subtitle: String
    let badge: String
    let sortScore: Int
    let payload: Payload
}

private struct SearchResultRow: View {
    let item: SearchResultRowModel
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Text(item.badge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(tint.opacity(0.12))
                    )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.58))
        )
    }
}

private extension SearchScope {
    var allowsActive: Bool {
        self == .all || self == .active
    }

    var allowsArchive: Bool {
        self == .all || self == .archive
    }
}
