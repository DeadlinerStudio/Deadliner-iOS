//
//  CategoryContentDetailView.swift
//  Deadliner
//
//  Created by Codex on 2026/7/17.
//

import SwiftUI

struct CategoryContentDetailView: View {
    let category: TaskCategory
    let sourceActiveTasks: [DDLItem]
    let sourceActiveHabits: [Habit]
    let sourceArchivedTasks: [DDLItem]
    let sourceArchivedHabits: [Habit]
    let habitStatusMap: [String: HabitWithDailyStatus]
    let categoryMap: [String: TaskCategory]
    let taskActions: SearchTaskActions
    let habitActions: SearchHabitActions

    @State private var overlayProgress: CGFloat = 0
    @State private var visibleActiveTaskCount = 12
    @State private var visibleActiveHabitCount = 12
    @State private var visibleArchivedTaskCount = 12
    @State private var visibleArchivedHabitCount = 12

    private let pageSize = 12

    // Keep category results derived from the parent KMP-backed snapshots.
    // Capturing them after a delayed navigation task caused transient empty
    // lists and made a category detail stale while source data refreshed.
    private var activeTasks: [DDLItem] {
        sourceActiveTasks.filter { $0.categoryUID == category.uid }
    }

    private var activeHabits: [Habit] {
        sourceActiveHabits.filter { $0.categoryUID == category.uid }
    }

    private var archivedTasks: [DDLItem] {
        sourceArchivedTasks.filter { $0.categoryUID == category.uid }
    }

    private var archivedHabits: [Habit] {
        sourceArchivedHabits.filter { $0.categoryUID == category.uid }
    }

    private var badge: CategoryBadgeModel {
        CategoryBadgeModel(category: category)
    }

    private var hasContent: Bool {
        !activeTasks.isEmpty || !activeHabits.isEmpty || !archivedTasks.isEmpty || !archivedHabits.isEmpty
    }

    private var visibleActiveTasks: ArraySlice<DDLItem> {
        activeTasks.prefix(visibleActiveTaskCount)
    }

    private var visibleActiveHabits: ArraySlice<Habit> {
        activeHabits.prefix(visibleActiveHabitCount)
    }

    private var visibleArchivedTasks: ArraySlice<DDLItem> {
        archivedTasks.prefix(visibleArchivedTaskCount)
    }

    private var visibleArchivedHabits: ArraySlice<Habit> {
        archivedHabits.prefix(visibleArchivedHabitCount)
    }

    @ViewBuilder
    var body: some View {
        contentList
    }

    private var contentList: some View {
        List {
            if !activeTasks.isEmpty {
                sectionTitleRow("任务", systemImage: "checklist", topPadding: 16)
                ForEach(visibleActiveTasks) { task in
                    activeTaskRow(task)
                }
                loadMoreRow(
                    visibleCount: visibleActiveTaskCount,
                    totalCount: activeTasks.count,
                    title: "显示更多任务"
                ) {
                    visibleActiveTaskCount += pageSize
                }
            }

            if !activeHabits.isEmpty {
                sectionTitleRow("习惯", systemImage: "leaf", topPadding: 16)
                ForEach(visibleActiveHabits) { habit in
                    activeHabitRow(habit)
                }
                loadMoreRow(
                    visibleCount: visibleActiveHabitCount,
                    totalCount: activeHabits.count,
                    title: "显示更多习惯"
                ) {
                    visibleActiveHabitCount += pageSize
                }
            }

            if !archivedTasks.isEmpty {
                sectionTitleRow("归档任务", systemImage: "archivebox", topPadding: 16)
                ForEach(visibleArchivedTasks) { task in
                    archivedTaskRow(task)
                }
                loadMoreRow(
                    visibleCount: visibleArchivedTaskCount,
                    totalCount: archivedTasks.count,
                    title: "显示更多归档任务"
                ) {
                    visibleArchivedTaskCount += pageSize
                }
            }

            if !archivedHabits.isEmpty {
                sectionTitleRow("归档习惯", systemImage: "archivebox.fill", topPadding: 16)
                ForEach(visibleArchivedHabits) { habit in
                    archivedHabitRow(habit)
                }
                loadMoreRow(
                    visibleCount: visibleArchivedHabitCount,
                    totalCount: archivedHabits.count,
                    title: "显示更多归档习惯"
                ) {
                    visibleArchivedHabitCount += pageSize
                }
            }

            if !hasContent {
                ContentUnavailableView(
                    "暂无内容",
                    systemImage: CategoryPresentationSupport.safeIconKey(category.iconKey),
                    description: Text("这个分类里还没有任务或习惯。")
                )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollContentBackground(.hidden)
        .deadlinerScrollEdgeEffect()
        .deadlinerTopAtmosphereSceneBackground(
            progress: overlayProgress,
            isAIConfigured: false,
            semanticTone: .accent,
            semanticAccentColor: Color(hex: category.colorHex)
        )
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            max(0, geo.contentOffset.y + geo.contentInsets.top)
        } action: { _, newValue in
            overlayProgress = min(max(newValue / 120, 0), 1)
        }
    }

    private func sectionTitleRow(_ title: String, systemImage: String, topPadding: CGFloat) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
                .fontWeight(.medium)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color(hex: category.colorHex))
        }
        .padding(.top, topPadding)
        .padding(.bottom, 4)
        .padding(.leading, 16)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func loadMoreRow(
        visibleCount: Int,
        totalCount: Int,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        if visibleCount < totalCount {
            Button(action: action) {
                Text("\(title)（剩余 \(totalCount - visibleCount) 项）")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    private func activeTaskRow(_ item: DDLItem) -> some View {
        DDLItemCardSwipeable(
            title: item.name,
            remainingTimeAlt: SearchViewSupport.remainingTimeText(for: item),
            note: item.note,
            progress: SearchViewSupport.progress(for: item),
            isStarred: item.isStared,
            categoryBadge: badge,
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

        return HabitItemCard(
            habit: statusValue.habit,
            doneCount: statusValue.doneCount,
            targetCount: statusValue.targetCount,
            isCompleted: statusValue.isCompleted,
            status: statusValue.isCompleted ? .completed : .undergo,
            remainingText: statusValue.scheduleHintText,
            sharedProgressText: statusValue.progressText,
            sharedScheduleLabel: statusValue.scheduleLabel,
            categoryBadge: badge,
            canToggle: statusValue.canApplyPrimaryAction,
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
