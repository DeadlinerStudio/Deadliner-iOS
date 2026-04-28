//
//  HomeView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import SwiftUI
import SwiftData
import os

struct HomeView: View {
    @Binding var query: String
    @Binding var taskSegment: TaskSegment
    var onScrollProgressChange: ((CGFloat) -> Void)? = nil
    var onSelectionModeChange: ((Bool) -> Void)? = nil
    
    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false

    @StateObject private var vm = HomeViewModel()
    @State private var pendingDeleteItems: [DDLItem] = []
    @State private var pendingDeleteHabits: [Habit] = []
    @State private var showDeleteConfirm: Bool = false
    @State private var pendingGiveUpItem: DDLItem? = nil
    @State private var showGiveUpConfirm: Bool = false
    
    @StateObject private var confetti = ConfettiController()
    
    @State private var listAnimToken: Int = 0
    @State private var enterAnimToken: Int = 0
    @State private var isStagingRebuild: Bool = false
    
    @State private var editSheetItem: DDLItem? = nil
    @State private var editSheetHabit: Habit? = nil
    @State private var detailSheetItem: DDLItem? = nil
    @State private var detailSheetDetent: PresentationDetent = .medium
    @State private var pendingOpenTaskDetailId: Int64? = nil
    
    @State private var selectionMode: Bool = false
    @State private var selectedTaskIDs = Set<Int64>()
    @State private var selectedHabitIDs = Set<Int64>()

    private var filteredTasks: [DDLItem] {
        let base = vm.tasks.filter { !$0.isArchived }
        let queried = query.isEmpty ? base : base.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.note.localizedCaseInsensitiveContains(query) ||
            $0.endTime.localizedCaseInsensitiveContains(query)
        }
        let incomplete = queried.filter { !$0.isCompleted }
        let completed = queried.filter(\.isCompleted)
        return incomplete.filter(\.isStared)
            + incomplete.filter { !$0.isStared }
            + completed.filter(\.isStared)
            + completed.filter { !$0.isStared }
    }
    
    private var selectedTasks: [DDLItem] {
        filteredTasks.filter { selectedTaskIDs.contains($0.id) }
    }
    
    private var selectedHabits: [Habit] {
        vm.displayHabits
            .map(\.habit)
            .filter { selectedHabitIDs.contains($0.id) }
    }
    
    private var selectedCount: Int {
        taskSegment == .tasks ? selectedTasks.count : selectedHabits.count
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { vm.errorText != nil },
            set: { isPresented in
                if !isPresented { vm.errorText = nil }
            }
        )
    }
    
    var body: some View {
        List {
            Section {
                if taskSegment == .tasks {
                    if vm.isLoading && vm.tasks.isEmpty {
                        ProgressView("加载中...")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else if filteredTasks.isEmpty {
                        if isStagingRebuild {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else {
                            emptyView(text: "暂无任务", icon: "checklist")
                        }
                    } else {
                        ForEach(Array(filteredTasks.enumerated()), id: \.element.id) { idx, item in
                            FloatUpRow(index: idx, maxLoad: 15, enable: true, animateToken: enterAnimToken) {
                                DDLItemCardSwipeable(
                                    title: item.name,
                                    remainingTimeAlt: remainingTimeText(for: item),
                                    note: item.note,
                                    progress: progress(for: item),
                                    isStarred: item.isStared,
                                    status: status(for: item),
                                    selectionMode: selectionMode,
                                    selected: selectedTaskIDs.contains(item.id),
                                    onTap: {
                                        detailSheetDetent = .medium
                                        detailSheetItem = item
                                    },
                                    onLongPressSelect: {
                                        if selectionMode {
                                            toggleTaskSelection(item.id)
                                        } else {
                                            enterTaskSelection(with: item.id)
                                        }
                                    },
                                    onToggleSelect: {
                                        toggleTaskSelection(item.id)
                                    },
                                    onComplete: {
                                        let wasCompleted = item.isCompleted
                                        let isNowCompleted = withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            listAnimToken += 1
                                            return vm.toggleCompleteLocal(item)
                                        }

                                        if isNowCompleted { confetti.fire() }

                                        if wasCompleted && !isNowCompleted {
                                            Task { @MainActor in
                                                isStagingRebuild = true
                                                let snapshot = vm.tasks
                                                await vm.stageRebuildFromCurrentSnapshot(snapshot: snapshot, blankDelayMs: 90)
                                                enterAnimToken += 1 // 触发重排后的上浮
                                                isStagingRebuild = false
                                            }
                                        }
                                        Task { await vm.persistToggleComplete(original: item) }
                                    },
                                    onDelete: {
                                        pendingDeleteItems = [item]
                                        pendingDeleteHabits = []
                                        showDeleteConfirm = true
                                    },
                                    onGiveUp: {
                                        if item.state.isAbandonedLike {
                                            Task { await vm.toggleGiveUpItem(item: item) }
                                        } else {
                                            pendingGiveUpItem = item
                                            showGiveUpConfirm = true
                                        }
                                    },
                                    onArchive: {
                                        Task { await vm.toggleArchiveItem(item: item) }
                                    },
                                    onEdit: {
                                        editSheetItem = item
                                    }
                                )
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                            .id(item.id) // 🟢 关键修复：确保 List 复用时识别出新行
                        }
                    }
                } else {
                    // 1. 顶部进度
                    HabitProgressView(progress: vm.getTodayCompletionRatio())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 8)
                        .id("habit-progress-\(enterAnimToken)")

                    // 2. 本周日期横条
                    WeekRow(
                        weekOverview: vm.weekOverview,
                        selectedDate: vm.selectedDate,
                        onSelectDate: { d in
                            Task { await vm.onDateSelected(d) }
                        },
                        onChangeWeek: { offset in
                            Task { await vm.changeWeek(offset: offset) }
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .padding(.bottom, 8)

                    if vm.displayHabits.isEmpty {
                        emptyView(text: "暂无待打卡习惯", icon: "leaf")
                            .padding(.top, 40)
                    } else {
                        ForEach(Array(vm.displayHabits.enumerated()), id: \.element.id) { idx, item in
                            FloatUpRow(index: idx + 1, maxLoad: 15, enable: true, animateToken: enterAnimToken) {
                                let ebState = vm.getEbbinghausState(habit: item.habit, targetDate: vm.selectedDate)
                                HabitItemCard(
                                    habit: item.habit,
                                    doneCount: item.doneCount,
                                    targetCount: item.targetCount,
                                    isCompleted: item.isCompleted,
                                    status: item.isCompleted ? .completed : .undergo,
                                    remainingText: ebState.text,
                                    isSelected: selectedHabitIDs.contains(item.habit.id),
                                    selectionMode: selectionMode,
                                    canToggle: (Calendar.current.startOfDay(for: vm.selectedDate) <= Calendar.current.startOfDay(for: Date())) && ebState.isDue,
                                    onToggle: {
                                        Task {
                                            let finished = await vm.toggleHabitRecord(item: item)
                                            if finished { confetti.fire() }
                                        }
                                    },
                                    onToggleSelect: {
                                        toggleHabitSelection(item.habit.id)
                                    },
                                    onLongPress: {
                                        if selectionMode {
                                            toggleHabitSelection(item.habit.id)
                                        } else {
                                            enterHabitSelection(with: item.habit.id)
                                        }
                                    }
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: !selectionMode) {
                                    if !selectionMode {
                                        Button {
                                            pendingDeleteItems = []
                                            pendingDeleteHabits = [item.habit]
                                            showDeleteConfirm = true
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                        .tint(.red)
                                        
                                        Button {
                                            editSheetHabit = item.habit
                                        } label: {
                                            Label("编辑", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: !selectionMode) {
                                    if !selectionMode {
                                        Button {
                                            Task { await vm.archiveHabit(item.habit) }
                                        } label: {
                                            Label("归档", systemImage: "archivebox")
                                        }
                                        .tint(.gray)
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
            } header: {
                Picker("Task Segment", selection: $taskSegment) {
                    ForEach(TaskSegment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .glassEffect()
                .textCase(nil)
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .toolbar {
            homeToolbar
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: listAnimToken)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            max(0, geo.contentOffset.y + geo.contentInsets.top)
        } action: { _, newValue in
            let p = min(max(newValue / 120, 0), 1)
            onScrollProgressChange?(p)
        }
        .task {
            do {
                try await TaskRepository.shared.initializeIfNeeded(container: SharedModelContainer.shared)
            } catch {
                assertionFailure("Home init DB failed: \(error)")
            }
            await vm.initialLoad()
            // 初始加载完成后触发一次动画
            enterAnimToken += 1
        }
        .refreshable {
            await vm.pullToRefresh()
            // 下拉刷新完成后触发一次动画
            enterAnimToken += 1
        }
        .onChange(of: vm.tasks.count) { old, new in
            // 如果数量真的变了（同步新增/删除），也触发一次动画
            if old != 0 && old != new {
                enterAnimToken += 1
            }
            sanitizeSelection()
            tryOpenPendingTaskDetailIfNeeded()
        }
        .onChange(of: vm.displayHabits.count) { _, _ in
            sanitizeSelection()
        }
        .onChange(of: query) { _, newValue in
            vm.searchQuery = newValue
            sanitizeSelection()
        }
        .onChange(of: taskSegment) { _, _ in
            clearSelection()
        }
        .onChange(of: selectionMode) { _, newValue in
            onSelectionModeChange?(newValue)
        }
        .onAppear {
            vm.searchQuery = query
            onSelectionModeChange?(selectionMode)
            tryOpenPendingTaskDetailIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ddlOpenTaskDetail)) { notification in
            let rawId = notification.userInfo?["taskId"] as? Int64
            pendingOpenTaskDetailId = rawId
            tryOpenPendingTaskDetailIfNeeded()
        }
        .alert("提示", isPresented: errorAlertPresented) {
            Button("确定", role: .cancel) { vm.errorText = nil }
        } message: {
            Text(vm.errorText ?? "")
        }
        .alert(
            deleteConfirmTitle,
            isPresented: $showDeleteConfirm
        ) {
            Button("删除", role: .destructive) {
                let deletingItems = pendingDeleteItems
                let deletingHabits = pendingDeleteHabits
                pendingDeleteItems = []
                pendingDeleteHabits = []
                clearSelection()
                if !deletingItems.isEmpty {
                    Task { await vm.deleteTasks(deletingItems) }
                } else if !deletingHabits.isEmpty {
                    Task { await vm.deleteHabits(deletingHabits) }
                }
            }
            Button("取消", role: .cancel) {
                pendingDeleteItems = []
                pendingDeleteHabits = []
            }
        } message: {
            if pendingDeleteItems.count == 1, let item = pendingDeleteItems.first {
                Text("将删除「\(item.name)」。此操作不可撤销。")
            } else if pendingDeleteHabits.count == 1, let habit = pendingDeleteHabits.first {
                Text("将删除「\(habit.name)」。此操作不可撤销。")
            } else if !pendingDeleteItems.isEmpty {
                Text("将删除选中的 \(pendingDeleteItems.count) 条任务。此操作不可撤销。")
            } else if !pendingDeleteHabits.isEmpty {
                Text("将删除选中的 \(pendingDeleteHabits.count) 条习惯。此操作不可撤销。")
            } else {
                Text("此操作不可撤销。")
            }
        }
        .alert(
            "确认放弃任务？",
            isPresented: $showGiveUpConfirm
        ) {
            Button("放弃", role: .destructive) {
                if let item = pendingGiveUpItem {
                    Task { await vm.toggleGiveUpItem(item: item) }
                }
                pendingGiveUpItem = nil
            }
            Button("取消", role: .cancel) {
                pendingGiveUpItem = nil
            }
        } message: {
            if let item = pendingGiveUpItem {
                Text("将把「\(item.name)」标记为已放弃。之后你仍可以恢复，或继续归档到归档页。")
            } else {
                Text("放弃后任务会变成已放弃状态。")
            }
        }
        .overlay {
            ConfettiOverlay(controller: confetti)
        }
        .sheet(item: $editSheetItem) { item in
            EditTaskSheetView(repository: TaskRepository.shared, item: item)
        }
        .sheet(item: $editSheetHabit) { habit in
            HabitEditorSheetView(
                mode: .edit(original: habit),
                initialDraft: .fromHabit(habit),
                onDone: {
                    NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
                }
            )
        }
        .sheet(item: $detailSheetItem) { item in
            TaskDetailSheetView(item: item, isExpanded: detailSheetDetent == .large)
                .presentationDetents([.medium, .large], selection: $detailSheetDetent)
                .presentationDragIndicator(.visible)
        }
    }

    private var deleteConfirmTitle: String {
        if pendingDeleteItems.count > 1 {
            return "确认删除这些任务？"
        }
        if pendingDeleteHabits.count > 1 {
            return "确认删除这些习惯？"
        }
        if !pendingDeleteItems.isEmpty {
            return "确认删除任务？"
        }
        return "确认删除习惯？"
    }

    @ToolbarContentBuilder
    private var homeToolbar: some ToolbarContent {
        if selectionMode {
            ToolbarItem(placement: .topBarLeading) {
                Button("", systemImage: "xmark") {
                    clearSelection()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        if taskSegment == .tasks {
                            await vm.archiveTasks(selectedTasks)
                        } else {
                            await vm.archiveHabits(selectedHabits)
                        }
                        clearSelection()
                    }
                } label: {
                    Image(systemName: "archivebox")
                }
                .disabled(selectedCount == 0)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    requestDeleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedCount == 0)
            }
        }
    }

    private func enterTaskSelection(with id: Int64) {
        withAnimation(.smooth(duration: 0.24, extraBounce: 0)) {
            selectionMode = true
            selectedTaskIDs = [id]
            selectedHabitIDs.removeAll()
        }
    }

    private func enterHabitSelection(with id: Int64) {
        withAnimation(.smooth(duration: 0.24, extraBounce: 0)) {
            selectionMode = true
            selectedHabitIDs = [id]
            selectedTaskIDs.removeAll()
        }
    }

    private func toggleTaskSelection(_ id: Int64) {
        if selectedTaskIDs.contains(id) {
            selectedTaskIDs.remove(id)
        } else {
            selectedTaskIDs.insert(id)
        }
    }

    private func toggleHabitSelection(_ id: Int64) {
        if selectedHabitIDs.contains(id) {
            selectedHabitIDs.remove(id)
        } else {
            selectedHabitIDs.insert(id)
        }
    }

    private func requestDeleteSelected() {
        if taskSegment == .tasks {
            pendingDeleteItems = selectedTasks
            pendingDeleteHabits = []
            showDeleteConfirm = !pendingDeleteItems.isEmpty
            return
        }
        pendingDeleteHabits = selectedHabits
        pendingDeleteItems = []
        showDeleteConfirm = !pendingDeleteHabits.isEmpty
    }

    private func sanitizeSelection() {
        selectedTaskIDs = selectedTaskIDs.intersection(Set(filteredTasks.map(\.id)))
        selectedHabitIDs = selectedHabitIDs.intersection(Set(vm.displayHabits.map { $0.habit.id }))
        if selectionMode && selectedCount == 0 {
            selectionMode = false
        }
    }

    private func clearSelection() {
        withAnimation(.smooth(duration: 0.24, extraBounce: 0)) {
            selectionMode = false
            selectedTaskIDs.removeAll()
            selectedHabitIDs.removeAll()
        }
    }

    private func tryOpenPendingTaskDetailIfNeeded() {
        guard let taskId = pendingOpenTaskDetailId else { return }
        guard let item = vm.tasks.first(where: { $0.id == taskId }) else { return }
        detailSheetDetent = .medium
        detailSheetItem = item
        pendingOpenTaskDetailId = nil
    }

    @ViewBuilder
    private func emptyView(text: String, icon: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Mapping Helpers (基础版)

    private func status(for item: DDLItem) -> DDLStatus {
        if item.state.isAbandonedLike { return .abandoned }
        if item.isCompleted { return .completed }

        guard let end = DeadlineDateParser.safeParseOptional(item.endTime) else { return .undergo }
        let now = Date()
        if end < now { return .passed }

        let hours = end.timeIntervalSince(now) / 3600
        if hours <= 24 { return .near }
        return .undergo
    }

    private func remainingTimeText(for item: DDLItem) -> String {
        if item.state.isAbandonedLike { return item.isArchived ? "已放弃归档" : "已放弃" }
        if item.isCompleted { return "已完成" }
        guard let end = DeadlineDateParser.safeParseOptional(item.endTime) else { return item.endTime }

        let now = Date()
        let diffSec = end.timeIntervalSince(now)
        let diffHours = Int(floor(diffSec / 3600.0))

        if diffSec < 0 {
            return "已逾期 \(abs(diffHours)) 小时"
        } else {
            let days = diffHours / 24
            let hours = diffHours % 24

            if days > 0 {
                return "\(days)天 \(hours)小时"
            } else {
                return hours == 0 ? "不足1小时" : "\(hours)小时"
            }
        }
    }

    /// 基础版本：用“开始-结束”时间窗估算进度；非法时间时返回 0
    private func progress(for item: DDLItem) -> CGFloat {
        guard let start = DeadlineDateParser.safeParseOptional(item.startTime), let end = DeadlineDateParser.safeParseOptional(item.endTime), end > start else {
            return item.isCompleted ? 1 : 0
        }
        if item.isCompleted { return 1 }

        let now = Date()
        if now <= start { return 0 }
        if now >= end { return 1 }

        let p = now.timeIntervalSince(start) / end.timeIntervalSince(start)
        let actualProgress = CGFloat(min(max(p, 0), 1))
        let progress = vm.progressDir ? actualProgress : 1.0 - actualProgress
        return progress
    }
}
