//
//  MainView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import SwiftUI
import UIKit

struct FocusMainView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Namespace private var toolbarTransition

    @State private var module: MainModule = .taskManagement
    @State private var taskSegment: TaskSegment = .tasks
    @State private var query: String = ""

    @State private var showAISheet = false
    @State private var showSettingsSheet = false
    @State private var navGradientProgress: CGFloat = 0
    
    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false
    @AppStorage("settings.ai.enabled") private var aiEnabled: Bool = true
    @AppStorage("settings.ai.last_analyzed_month") private var lastAnalyzedMonth: String = ""
    @AppStorage("userTier") private var userTier: UserTier = .free
    @AppStorage("userName") private var userName: String = "用户"
    
    let repo: TaskRepository = TaskRepository.shared

    @State private var showAddEntrySheet = false
    @State private var addEntrySelection: TaskSegment = .tasks
    
    @State private var showArchiveSheet = false
    @State private var showPaywall = false

    private let widgetLaunchDefaults = UserDefaults(suiteName: "group.top.aritxonly.deadliner.group")
    private let widgetLaunchKey = "widget.pending_add_entry_type"

    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle(module.title)
                .navigationBarTitleDisplayMode(.automatic)
                .searchable(text: $query, prompt: searchPrompt)
                .toolbar {
                    topLeadingToolbar
                    topTrailingToolbar
                    bottomToolbar
                }
                .background {
                    ZStack(alignment: .top) {
                        Color(uiColor: .systemGroupedBackground)
                                            .ignoresSafeArea()
                                        
                        
                        TopBarGradientOverlay(progress: navGradientProgress, isAIConfigured: isAIConfigured)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .sheet(isPresented: $showAISheet) {
                    DeadlinerAIPanel()
                        .presentationDetents([.medium, .large])
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
                .sheet(isPresented: $showPaywall) {
                    ProPaywallView()
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
        }
    }

    // MARK: - Content Host

    @ViewBuilder
    private var contentView: some View {
        switch module {
        case .taskManagement:
            HomeView(query: $query, taskSegment: $taskSegment,
                     onScrollProgressChange: { p in
                         navGradientProgress = p
                     })
        case .insights:
            OverviewView(onScrollProgressChange: { p in
                navGradientProgress = p
            })
        case .archive:
            ArchiveView(query: $query, onScrollProgressChange: { p in
                navGradientProgress = p
            })
        }
    }

    // MARK: - Top Toolbar

    @ToolbarContentBuilder
    private var topLeadingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                ForEach(MainModule.allCases) { m in
                    Button {
                        withAnimation(.smooth(duration: 0.32, extraBounce: 0)) {
                            module = m
                            query = ""
                        }
                    } label: {
                        Label(m.title, systemImage: m.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: module.systemImage)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("切换模块")
        }
        .matchedTransitionSource(id: "main-toolbar-leading", in: toolbarTransition)
    }
    @ToolbarContentBuilder
    private var topTrailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if module == .taskManagement {
                Button {
                    showSettingsSheet = true
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
            } else {
            }
        }
        .matchedTransitionSource(id: "main-toolbar-trailing", in: toolbarTransition)
        .sharedBackgroundVisibility(.hidden)
    }

    // MARK: - Bottom Toolbar

    @ToolbarContentBuilder
    private var bottomToolbar: some ToolbarContent {
        switch module {
        case .taskManagement:
            taskManagementBottomToolbar
        case .insights:
            insightsBottomToolbar
        case .archive:
            archiveBottomToolbar
        }
    }

    @ToolbarContentBuilder
    private var taskManagementBottomToolbar: some ToolbarContent {
        if aiEnabled {
            ToolbarItem(placement: .bottomBar) {
                Button { showAISheet = true } label: {
                    Image(systemName: "sparkles")
                }
                .accessibilityLabel("Deadliner Claw")
            }
            .matchedTransitionSource(id: "main-toolbar-bottom-leading", in: toolbarTransition)
        }

        ToolbarSpacer(.fixed, placement: .bottomBar)
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
            .matchedTransitionSource(id: "main-toolbar-bottom-center", in: toolbarTransition)
        ToolbarSpacer(.fixed, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            Button {
                presentAddSheet(selection: taskSegment)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.glassProminent)
            .tint(themeStore.fabColor)
            .id("main-fab-\(themeStore.accentOption.rawValue)")
            .accessibilityLabel("添加")
        }
        .matchedTransitionSource(id: "main-toolbar-bottom-trailing", in: toolbarTransition)
    }

    @ToolbarContentBuilder
    private var insightsBottomToolbar: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button {
                if isInsightFreeUser {
                    showPaywall = true
                } else {
                    NotificationCenter.default.post(name: .ddlRequestMonthlyAnalysis, object: nil)
                }
            } label: {
                HStack(spacing: 4) {
                    if isInsightFreeUser {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                    } else {
                        Image(systemName: insightAnalysisGenerated ? "checkmark.circle.fill" : "sparkles")
                    }

                    Text(insightAnalysisGenerated && !isInsightFreeUser ? "上月分析已生成" : "AI 月度分析")

                    if isInsightFreeUser {
                        GeekBadge()
                    }
                }
            }
            .disabled(!isInsightFreeUser && insightAnalysisGenerated)
            .foregroundColor(insightAnalysisGenerated && !isInsightFreeUser ? .secondary : .primary)
        }
        .matchedTransitionSource(id: "main-toolbar-bottom-center", in: toolbarTransition)
    }

    @ToolbarContentBuilder
    private var archiveBottomToolbar: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button(role: .destructive) {
                NotificationCenter.default.post(name: .ddlDeleteAllArchived, object: nil)
            } label: {
                Image(systemName: "trash")
            }
            .foregroundStyle(.red)
            .accessibilityLabel("删除所有归档")
        }
        .matchedTransitionSource(id: "main-toolbar-bottom-leading", in: toolbarTransition)

        ToolbarSpacer(.flexible, placement: .bottomBar)

        DefaultToolbarItem(kind: .search, placement: .bottomBar)
            .matchedTransitionSource(id: "main-toolbar-bottom-trailing", in: toolbarTransition)
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

    private func presentAddSheet(selection: TaskSegment) {
        module = .taskManagement
        taskSegment = selection
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
            presentAddSheet(selection: .habits)
        default:
            presentAddSheet(selection: .tasks)
        }
    }

    private func consumePendingWidgetLaunch() {
        guard let rawValue = widgetLaunchDefaults?.string(forKey: widgetLaunchKey) else { return }
        widgetLaunchDefaults?.removeObject(forKey: widgetLaunchKey)

        switch rawValue {
        case "habit", "habits":
            presentAddSheet(selection: .habits)
        default:
            presentAddSheet(selection: .tasks)
        }
    }

    // MARK: - Search Prompt

    private var searchPrompt: String {
        switch module {
        case .taskManagement:
            return taskSegment == .tasks ? "搜索任务..." : "搜索习惯..."
        case .insights:
            return "搜索模块..."
        case .archive:
            return "搜索归档..."
        }
    }
}

struct ProfilePicture: View {
    var body: some View {
        Group {
            if let avatar = AvatarManager.shared.avatarImage {
                avatar
                    .resizable()
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .scaledToFill()
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .padding(.horizontal)
        .accessibilityLabel("用户")
    }
}
