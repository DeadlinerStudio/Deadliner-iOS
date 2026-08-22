//
//  SearchCategoryDetailView.swift
//  Deadliner
//
//  Created by Codex on 2026/4/2.
//

import SwiftUI

struct SearchCategoryDetailView: View {
    let category: SearchBrowseCategory
    let activeTasks: [DDLItem]
    let activeHabits: [Habit]
    let archivedTasks: [DDLItem]
    let archivedHabits: [Habit]
    let habitStatusMap: [String: HabitWithDailyStatus]
    let categoryMap: [String: TaskCategory]
    let taskActions: SearchTaskActions
    let habitActions: SearchHabitActions
    @Binding var usesLocalAtmosphere: Bool
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
        .scrollContentBackground(.hidden)
        .deadlinerScrollEdgeEffect()
        .deadlinerTopAtmosphereSceneBackground(
            progress: overlayProgress,
            isAIConfigured: false,
            semanticTone: category.atmosphereTone
        )
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            usesLocalAtmosphere = true
        }
        .onDisappear {
            usesLocalAtmosphere = false
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
            categoryBadge: CategoryPresentationSupport.badge(for: item.categoryUID, categories: categoryMap),
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
            categoryBadge: CategoryPresentationSupport.badge(for: habit.categoryUID, categories: categoryMap),
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

extension SearchBrowseCategory {
    var atmosphereTone: ImmersiveSurfaceTone {
        switch self {
        case .today:
            return .warning
        case .upcoming:
            return .danger
        case .starred:
            return .warning
        case .archived:
            return .neutral
        case .tasks:
            return .accent
        case .habits:
            return .success
        }
    }
}
