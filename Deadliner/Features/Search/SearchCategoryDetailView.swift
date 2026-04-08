//
//  SearchCategoryDetailView.swift
//  Deadliner
//
//  Created by Codex on 2026/4/2.
//

import SwiftUI

struct SearchCategoryDetailView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    let category: SearchBrowseCategory
    let activeTasks: [DDLItem]
    let activeHabits: [Habit]
    let archivedTasks: [DDLItem]
    let archivedHabits: [Habit]
    let habitStatusMap: [Int64: HabitWithDailyStatus]
    let taskActions: SearchTaskActions
    let habitActions: SearchHabitActions
    @State private var overlayProgress: CGFloat = 0

    private var hasContent: Bool {
        !activeTasks.isEmpty || !activeHabits.isEmpty || !archivedTasks.isEmpty || !archivedHabits.isEmpty
    }

    var body: some View {
        List {
            if !activeTasks.isEmpty {
                sectionTitleRow("任务", systemImage: "checklist", topPadding: 16)
                ForEach(activeTasks) { task in
                    activeTaskRow(task)
                }
            }

            if !activeHabits.isEmpty {
                sectionTitleRow("习惯", systemImage: "leaf", topPadding: 16)
                ForEach(activeHabits) { habit in
                    activeHabitRow(habit)
                }
            }

            if !archivedTasks.isEmpty {
                sectionTitleRow("归档任务", systemImage: "archivebox", topPadding: 16)
                ForEach(archivedTasks) { task in
                    archivedTaskRow(task)
                }
            }

            if !archivedHabits.isEmpty {
                sectionTitleRow("归档习惯", systemImage: "archivebox.fill", topPadding: 16)
                ForEach(archivedHabits) { habit in
                    archivedHabitRow(habit)
                }
            }

            if !hasContent {
                ContentUnavailableView("暂无内容", systemImage: "tray", description: Text("这个分类里还没有可展示的卡片。"))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .environment(\.defaultMinListRowHeight, 1)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background {
            ZStack(alignment: .top) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                SearchCategoryTopOverlay(
                    progress: overlayProgress,
                    palette: category.overlayPalette,
                    isEnabled: themeStore.overlayEnabled
                )
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            max(0, geo.contentOffset.y + geo.contentInsets.top)
        } action: { _, newValue in
            overlayProgress = min(max(newValue / 120, 0), 1)
        }
    }

    private var hasActiveContent: Bool {
        !activeTasks.isEmpty || !activeHabits.isEmpty
    }

    private var hasLeadingArchiveSection: Bool {
        !archivedTasks.isEmpty && hasActiveContent
    }

    private func sectionTitleRow(_ title: String, systemImage: String, topPadding: CGFloat) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
                .fontWeight(.medium)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor(for: title))
        }
        .padding(.top, topPadding)
        .padding(.bottom, 4)
        .padding(.leading, 16)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func iconColor(for title: String) -> Color {
        switch title {
        case "任务":
            return .blue
        case "习惯":
            return .green
        case "归档任务", "归档习惯":
            return .gray
        default:
            return .secondary
        }
    }

    private func activeTaskRow(_ item: DDLItem) -> some View {
        DDLItemCardSwipeable(
            title: item.name,
            remainingTimeAlt: SearchViewSupport.remainingTimeText(for: item),
            note: item.note,
            progress: SearchViewSupport.progress(for: item),
            isStarred: item.isStared,
            status: SearchViewSupport.status(for: item),
            onTap: { },
            onComplete: {
                Task { await taskActions.onToggleCompletion(item) }
            },
            onDelete: {
                taskActions.onDelete(item)
            },
            onGiveUp: {
                taskActions.onGiveUp(item)
            },
            onArchive: {
                Task { await taskActions.onArchive(item) }
            },
            onEdit: {
                taskActions.onEdit(item)
            }
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func activeHabitRow(_ habit: Habit) -> some View {
        let statusValue = habitStatusMap[habit.id] ?? SearchViewSupport.fallbackStatus(for: habit)
        let ebbinghausState = SearchViewSupport.getEbbinghausState(habit: habit, targetDate: Date())

        return HabitItemCard(
            habit: statusValue.habit,
            doneCount: statusValue.doneCount,
            targetCount: statusValue.targetCount,
            isCompleted: statusValue.isCompleted,
            status: statusValue.isCompleted ? .completed : .undergo,
            remainingText: ebbinghausState.text,
            canToggle: ebbinghausState.isDue,
            onToggle: {
                Task { await habitActions.onToggle(statusValue) }
            },
            onLongPress: {
                habitActions.onEdit(habit)
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                habitActions.onDelete(habit)
            } label: {
                Label("删除", systemImage: "trash")
            }
            .tint(.red)

            Button {
                habitActions.onEdit(habit)
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await habitActions.onArchive(habit) }
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            .tint(.gray)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func archivedTaskRow(_ item: DDLItem) -> some View {
        ArchivedDDLItemCard(
            title: item.name,
            startTime: SearchViewSupport.formatDate(item.startTime),
            completeTime: SearchViewSupport.archivedTaskDetail(for: item),
            note: item.note,
            onUndo: {
                Task { await taskActions.onUnarchive(item) }
            },
            onDelete: {
                taskActions.onDelete(item)
            }
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func archivedHabitRow(_ item: Habit) -> some View {
        ArchivedDDLItemCard(
            title: item.name,
            startTime: SearchViewSupport.formatHabitDetail(item),
            completeTime: "归档于 \(SearchViewSupport.formatDate(item.updatedAt))",
            note: item.description ?? "无备注",
            onUndo: {
                Task { await habitActions.onUnarchive(item) }
            },
            onDelete: {
                habitActions.onDelete(item)
            }
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

extension SearchBrowseCategory {
    var overlayPalette: AIGlowPalette {
        switch self {
        case .today:
            return .accentOnly(for: .orange)
        case .upcoming:
            return .accentOnly(for: .red)
        case .starred:
            return .accentOnly(for: .yellow)
        case .archived:
            return .accentOnly(for: .gray)
        case .tasks:
            return .accentOnly(for: .blue)
        case .habits:
            return .accentOnly(for: .green)
        }
    }
}

struct SearchCategoryTopOverlay: View {
    let progress: CGFloat
    let palette: AIGlowPalette
    let isEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = min(max(progress, 0), 1)
        let height: CGFloat = max(0, 340 - 340 * p)
        let baseAlpha: CGFloat = colorScheme == .dark ? 0.60 : 0.95
        let topAlpha: CGFloat = max(0, baseAlpha - 0.50 * p)

        ZStack {
            if isEnabled {
                SearchCategoryGlowView(palette: palette)
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(topAlpha), location: 0.0),
                    .init(color: .black.opacity(0.0), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .ignoresSafeArea(edges: .top)
        .animation(.easeOut(duration: 0.15), value: p)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

private struct SearchCategoryGlowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAnimating = false

    let palette: AIGlowPalette

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let mid = colorScheme == .dark ? 0.6 : 0.85

            ZStack {
                RadialGradient(
                    colors: [palette.blue, palette.blue.opacity(mid), palette.blue.opacity(0)],
                    center: UnitPoint(
                        x: isAnimating ? 0.22 : 0.11,
                        y: isAnimating ? 0.28 : 0.40
                    ),
                    startRadius: 0,
                    endRadius: h * 1.2
                )
                .opacity(isAnimating ? 1.0 : 0.76)

                RadialGradient(
                    colors: [palette.pink, palette.pink.opacity(mid), palette.pink.opacity(0)],
                    center: UnitPoint(
                        x: isAnimating ? 0.78 : 0.90,
                        y: isAnimating ? 0.42 : 0.29
                    ),
                    startRadius: 0,
                    endRadius: h * 1.2
                )
                .opacity(isAnimating ? 0.82 : 1.0)

                RadialGradient(
                    colors: [palette.amber, palette.amber.opacity(mid), palette.amber.opacity(0)],
                    center: UnitPoint(
                        x: isAnimating ? 0.57 : 0.43,
                        y: isAnimating ? 0.79 : 0.93
                    ),
                    startRadius: 0,
                    endRadius: h * 1.1
                )
                .opacity(isAnimating ? 0.96 : 0.70)
            }
            .onAppear {
                guard !isAnimating else { return }
                withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
    }
}
