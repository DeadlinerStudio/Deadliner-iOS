//
//  MainView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import SwiftUI

struct MainView: View {
    @State private var module: MainModule = .taskManagement
    @State private var taskSegment: TaskSegment = .tasks
    @State private var query: String = ""

    @State private var showAISheet = false
    @State private var showSettingsSheet = false
    @State private var navGradientProgress: CGFloat = 0
    
    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false
    @AppStorage("settings.ai.enabled") private var aiEnabled: Bool = true
    
    let repo: TaskRepository = TaskRepository.shared

    @State private var showAddTaskForm = false
    @State private var showAddHabitForm = false
    @State private var showAddOptions = false
    
    @State private var showArchiveSheet = false

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
                .sheet(isPresented: $showAddTaskForm) {
                    NavigationStack {
                        AddTaskSheetView(
                            repository: repo,
                            onDone: {
                                NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
                            }
                        )
                    }
                    .presentationDetents([.large])
                }
                .sheet(isPresented: $showAddHabitForm) {
                    NavigationStack {
                        AddHabitSheetView(onDone: {
                            NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
                        })
                    }
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
        case .timeline:
            DeadlinerTimelineView(query: $query)
        case .insights:
            OverviewView()
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
                        module = m
                        query = ""
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
    }

    @ToolbarContentBuilder
    private var topTrailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showSettingsSheet = true
            } label: {
                Image("avatar")
                    .resizable()
                    .renderingMode(.original)
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

    // MARK: - Bottom Toolbar

    @ToolbarContentBuilder
    private var bottomToolbar: some ToolbarContent {
        switch module {
        case .taskManagement:
            if aiEnabled {
                ToolbarItem(placement: .bottomBar) {
                    Button { showAISheet = true } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel("Deadliner AI")
                }
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.flexible, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button {
                    showAddOptions = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glassProminent)
                .tint(Color(hex: "#FFFF6D6D"))
                .accessibilityLabel("添加选项")
                
                .confirmationDialog("选择添加类型", isPresented: $showAddOptions, titleVisibility: .hidden) {
                    Button("新建任务") { showAddTaskForm = true }
                    Button("新建习惯") { showAddHabitForm = true }
                    Button("取消", role: .cancel) { }
                }
            }

        case .timeline:
            ToolbarItem(placement: .bottomBar) {
                Button {
                    // TODO: timeline filter
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.flexible, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button {
                    showAddOptions = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glassProminent)
                .tint(Color(hex: "#FFFF6D6D"))
                .accessibilityLabel("添加选项")
                
                .confirmationDialog("选择添加类型", isPresented: $showAddOptions, titleVisibility: .hidden) {
                    Button("新建任务") { showAddTaskForm = true }
                    Button("新建习惯") { showAddHabitForm = true }
                    Button("取消", role: .cancel) { }
                }
            }

        case .insights:
            ToolbarItem(placement: .bottomBar) {
                Button {
                    // TODO: range select
                } label: {
                    Label("Range", systemImage: "calendar.badge.clock")
                }
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button {
                    // TODO: export
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }

        case .archive:
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    NotificationCenter.default.post(name: .ddlDeleteAllArchived, object: nil)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                        Text("全部删除")
                            .fontWeight(.medium)
                    }
                }
                .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Search Prompt

    private var searchPrompt: String {
        switch module {
        case .taskManagement:
            return taskSegment == .tasks ? "搜索任务..." : "搜索习惯..."
        case .timeline:
            return "搜索待办..."
        case .insights:
            return "搜索模块..."
        case .archive:
            return "搜索归档..."
        }
    }
}

struct ProfilePicture: View {
    var body: some View {
        Image("avatar")
            .resizable()
            .scaledToFill()
            .frame(width: 28, height: 28)
            .clipShape(Circle())
            .padding(.horizontal)
            .accessibilityLabel("用户")
    }
}
