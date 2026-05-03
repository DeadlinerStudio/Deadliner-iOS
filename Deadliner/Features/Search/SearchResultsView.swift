//
//  SearchResultsView.swift
//  Deadliner
//
//  Created by Codex on 2026/4/2.
//

import SwiftUI

struct SearchResultsView: View {
    @Binding var scope: SearchScope
    let query: String
    let inspirations: [CaptureInboxItem]
    let activeTasks: [DDLItem]
    let activeHabits: [Habit]
    let archivedTasks: [DDLItem]
    let archivedHabits: [Habit]
    let habitStatusMap: [Int64: HabitWithDailyStatus]
    let taskActions: SearchTaskActions
    let habitActions: SearchHabitActions
    let inspirationActions: SearchInspirationActions

    private var taskMatches: [SearchTaskResult] {
        scope.allowsActive ? SearchViewSupport.searchResults(in: activeTasks, query: query) : []
    }

    private var habitMatches: [SearchHabitResult] {
        scope.allowsActive ? SearchViewSupport.searchResults(in: activeHabits, query: query) : []
    }

    private var inspirationMatches: [SearchInspirationResult] {
        scope.allowsActive ? SearchViewSupport.searchResults(in: inspirations, query: query) : []
    }

    private var archivedTaskMatches: [SearchTaskResult] {
        scope.allowsArchive ? SearchViewSupport.searchResults(in: archivedTasks, query: query, archived: true) : []
    }

    private var archivedHabitMatches: [SearchHabitResult] {
        scope.allowsArchive ? SearchViewSupport.searchResults(in: archivedHabits, query: query, archived: true) : []
    }

    var body: some View {
        resultsScopeSection

        if taskMatches.isEmpty && inspirationMatches.isEmpty && habitMatches.isEmpty && archivedTaskMatches.isEmpty && archivedHabitMatches.isEmpty {
            emptySearchRow
        } else {
            if !inspirationMatches.isEmpty {
                Section {
                    ForEach(inspirationMatches) { item in
                        inspirationRow(item)
                    }
                } header: {
                    searchSectionHeader("灵感", systemImage: "quote.bubble")
                }
            }

            if !taskMatches.isEmpty {
                Section {
                    ForEach(taskMatches) { item in
                        activeTaskRow(item)
                    }
                } header: {
                    searchSectionHeader("任务", systemImage: "checklist")
                }
            }

            if !habitMatches.isEmpty {
                Section {
                    ForEach(habitMatches) { item in
                        activeHabitRow(item)
                    }
                } header: {
                    searchSectionHeader("习惯", systemImage: "leaf")
                }
            }

            if !archivedTaskMatches.isEmpty {
                Section {
                    ForEach(archivedTaskMatches) { item in
                        archivedTaskRow(item)
                    }
                } header: {
                    searchSectionHeader("归档任务", systemImage: "archivebox")
                }
            }

            if !archivedHabitMatches.isEmpty {
                Section {
                    ForEach(archivedHabitMatches) { item in
                        archivedHabitRow(item)
                    }
                } header: {
                    searchSectionHeader("归档习惯", systemImage: "archivebox.fill")
                }
            }
        }
    }

    private var resultsScopeSection: some View {
        Section {
            Picker("搜索范围", selection: $scope) {
                ForEach(SearchScope.allCases, id: \.self) { item in
                    Text(item.rawValue)
                        .tag(item as SearchScope)
                }
            }
            .pickerStyle(.segmented)
            .glassEffect()
            .textCase(nil)
            .padding(.horizontal, 16)
        }
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

    private func searchSectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.leading, 16)
    }

    private func activeTaskRow(_ item: SearchTaskResult) -> some View {
        DDLItemCardSwipeable(
            title: item.task.name,
            remainingTimeAlt: SearchViewSupport.remainingTimeText(for: item.task),
            note: item.task.note,
            progress: SearchViewSupport.progress(for: item.task),
            isStarred: item.task.isStared,
            status: SearchViewSupport.status(for: item.task),
            onTap: { },
            onComplete: {
                Task { await taskActions.onToggleCompletion(item.task) }
            },
            onDelete: {
                taskActions.onDelete(item.task)
            },
            onGiveUp: {
                taskActions.onGiveUp(item.task)
            },
            onArchive: {
                Task { await taskActions.onArchive(item.task) }
            },
            onEdit: {
                taskActions.onEdit(item.task)
            }
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func inspirationRow(_ item: SearchInspirationResult) -> some View {
        CaptureNoteCard(
            item: item.item,
            relativeTimeText: SearchViewSupport.relativeTimeText(for: item.item.updatedAt),
            selectionMode: false,
            isSelected: false,
            onTap: {
                inspirationActions.onOpen(item.item)
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                inspirationActions.onDelete(item.item)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                inspirationActions.onAIConvertToHabit(item.item)
            } label: {
                Label("AI 习惯", systemImage: "leaf")
            }
            .tint(.green)

            Button {
                inspirationActions.onAIConvertToTask(item.item)
            } label: {
                Label("AI 任务", image: "sparkles")
            }
            .tint(.blue)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func activeHabitRow(_ item: SearchHabitResult) -> some View {
        let status = habitStatusMap[item.habit.id] ?? SearchViewSupport.fallbackStatus(for: item.habit)
        let ebbinghausState = SearchViewSupport.getEbbinghausState(habit: item.habit, targetDate: Date())

        return HabitItemCard(
            habit: status.habit,
            doneCount: status.doneCount,
            targetCount: status.targetCount,
            isCompleted: status.isCompleted,
            status: status.isCompleted ? .completed : .undergo,
            remainingText: ebbinghausState.text,
            canToggle: ebbinghausState.isDue,
            onToggle: {
                Task { await habitActions.onToggle(status) }
            },
            onLongPress: {
                habitActions.onEdit(item.habit)
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                habitActions.onDelete(item.habit)
            } label: {
                Label("删除", systemImage: "trash")
            }
            .tint(.red)

            Button {
                habitActions.onEdit(item.habit)
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await habitActions.onArchive(item.habit) }
            } label: {
                Label("归档", systemImage: "archivebox")
            }
            .tint(.gray)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func archivedTaskRow(_ item: SearchTaskResult) -> some View {
        ArchivedDDLItemCard(
            title: item.task.name,
            startTime: SearchViewSupport.formatDate(item.task.startTime),
            completeTime: SearchViewSupport.archivedTaskDetail(for: item.task),
            note: item.task.note,
            onUndo: {
                Task { await taskActions.onUnarchive(item.task) }
            },
            onDelete: {
                taskActions.onDelete(item.task)
            }
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func archivedHabitRow(_ item: SearchHabitResult) -> some View {
        ArchivedDDLItemCard(
            title: item.habit.name,
            startTime: SearchViewSupport.formatHabitDetail(item.habit),
            completeTime: "归档于 \(SearchViewSupport.formatDate(item.habit.updatedAt))",
            note: item.habit.description ?? "无备注",
            onUndo: {
                Task { await habitActions.onUnarchive(item.habit) }
            },
            onDelete: {
                habitActions.onDelete(item.habit)
            }
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
