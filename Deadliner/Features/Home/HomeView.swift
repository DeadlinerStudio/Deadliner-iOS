//
//  HomeView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import SwiftUI
import os

enum HomeBoardPresentationStyle {
    case classic
    case dashboard
}

struct HomeView: View {
    @Binding var query: String
    @Binding var taskSegment: TaskSegment
    @Binding var categoryFilter: CategoryFilter
    var onScrollProgressChange: ((CGFloat) -> Void)? = nil
    var onSelectionModeChange: ((Bool) -> Void)? = nil
    var onAtmosphereToneChange: ((ImmersiveSurfaceTone) -> Void)? = nil
    var compactLayoutProgress: CGFloat? = nil

    var body: some View {
        HomeBoardCoreView(
            query: $query,
            taskSegment: $taskSegment,
            categoryFilter: $categoryFilter,
            onScrollProgressChange: onScrollProgressChange,
            onSelectionModeChange: onSelectionModeChange,
            onAtmosphereToneChange: onAtmosphereToneChange,
            compactLayoutProgress: compactLayoutProgress,
            presentationStyle: .classic
        )
    }
}

struct HomeBoardCoreView: View {
    @Binding var query: String
    @Binding var taskSegment: TaskSegment
    @Binding var categoryFilter: CategoryFilter
    var onScrollProgressChange: ((CGFloat) -> Void)? = nil
    var onSelectionModeChange: ((Bool) -> Void)? = nil
    var onAtmosphereToneChange: ((ImmersiveSurfaceTone) -> Void)? = nil
    var compactLayoutProgress: CGFloat? = nil
    let presentationStyle: HomeBoardPresentationStyle

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
    @State private var pendingOpenTaskDetailId: String? = nil
    
    @State private var selection = HomeBoardSelectionState()
    @State private var scrollProgress: CGFloat = 0

    private var viewState: HomeBoardDerivedState {
        HomeBoardDerivedState(
            query: query,
            taskSegment: taskSegment,
            tasks: vm.tasks,
            displayHabits: vm.displayHabits,
            categories: vm.categories,
            categoryFilter: categoryFilter,
            selection: selection,
            compactLayoutProgress: compactLayoutProgress,
            scrollProgress: scrollProgress,
            todayHabitCompletionRatio: vm.getTodayCompletionRatio(),
            progressDir: vm.progressDir
        )
    }

    private var experimentalLayoutActive: Bool {
        presentationStyle == .dashboard
    }

    private var selectionMode: Bool {
        selection.isActive
    }

    private var showsToolbarSegmentPicker: Bool {
        presentationStyle == .classic && !selectionMode
    }

    private var selectedTasks: [DDLItem] {
        viewState.selectedTasks
    }

    private var selectedHabits: [Habit] {
        viewState.selectedHabits
    }

    private var selectedCount: Int {
        viewState.selectedCount
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
        let state = viewState
        GeometryReader { proxy in
            let isWide = proxy.size.width >= 840
            
            Group {
                if experimentalLayoutActive {
                    experimentalDashboardLayout(state: state)
                } else if isWide {
                    twoColumnLayout(state: state)
                } else {
                    classicSingleColumnLayout(state: state)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: listAnimToken)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                max(0, geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, newValue in
                scrollProgress = min(max(newValue / 120, 0), 1)
                let p = min(max(newValue / 120, 0), 1)
                onScrollProgressChange?(p)
            }
        }
        .background(.clear)
        .toolbar {
            homeToolbar
        }
        .task {
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
        .onChange(of: categoryFilter) { _, _ in
            clearSelection()
            sanitizeSelection()
            logCategoryFilter()
        }
        .onChange(of: selection.isActive) { _, newValue in
            onSelectionModeChange?(newValue)
        }
        .onAppear {
            vm.searchQuery = query
            logCategoryFilter()
            onSelectionModeChange?(selection.isActive)
            onAtmosphereToneChange?(state.currentAtmosphereTone)
            tryOpenPendingTaskDetailIfNeeded()
        }
        .onChange(of: state.currentAtmosphereTone) { _, newValue in
            onAtmosphereToneChange?(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ddlOpenTaskDetail)) { notification in
            let rawId = notification.userInfo?["taskId"] as? String
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
            EditTaskSheetView(repository: PersistenceStores.tasks, item: item)
        }
        .sheet(item: $editSheetHabit) { habit in
            HabitEditorSheetView(
                mode: .edit(original: habit),
                initialDraft: .fromHabit(habit)
            )
        }
        .sheet(item: $detailSheetItem) { item in
            TaskDetailSheetView(item: item, isExpanded: detailSheetDetent == .large)
                .presentationDetents([.medium, .large], selection: $detailSheetDetent)
                .presentationDragIndicator(.visible)
        }
    }

    private func logCategoryFilter() {
        let scope: String
        if categoryFilter.isAll {
            scope = "all"
        } else {
            scope = "categories=\(categoryFilter.categoryUIDs.count), uncategorized=\(categoryFilter.includesUncategorized)"
        }
        SyncDebugLog.log("[KMP][Home] categoryFilter \(scope)")
    }

    private func classicSingleColumnLayout(state: HomeBoardDerivedState) -> some View {
        List {
            Section {
                if taskSegment == .tasks {
                    tasksSectionContent(state: state)
                } else {
                    habitsSectionContent(state: state)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .deadlinerScrollEdgeEffect()
    }

    @ViewBuilder
    private func experimentalDashboardLayout(state: HomeBoardDerivedState) -> some View {
        ExperimentalHomeDashboardView(
            segment: taskSegment,
            dashboard: state.dashboardHeader,
            onSelectSegment: { taskSegment = $0 }
        ) {
            if taskSegment == .tasks {
                EmptyView()
            } else {
                habitWeekRow
            }
        } listContent: {
            if taskSegment == .tasks {
                tasksSectionContent(state: state)
            } else {
                habitCardsContent(state: state)
            }
        }
    }

    private func twoColumnLayout(state: HomeBoardDerivedState) -> some View {
        HStack(spacing: 0) {
            List {
                Section {
                    tasksSectionContent(state: state)
                } header: {
                    Text("任务")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .padding(.bottom, 8)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .deadlinerScrollEdgeEffect(forceImmersive: true)

            Divider()

            List {
                Section {
                    habitsSectionContent(state: state)
                } header: {
                    Text("习惯")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .padding(.bottom, 8)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .deadlinerScrollEdgeEffect(forceImmersive: true)
        }
    }

    @ViewBuilder
    private func tasksSectionContent(state: HomeBoardDerivedState) -> some View {
        if vm.isLoading && vm.tasks.isEmpty {
            ProgressView("加载中...")
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else if state.filteredTasks.isEmpty {
            if isStagingRebuild {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                emptyView(text: "暂无任务", icon: "checklist")
            }
        } else {
            ForEach(state.taskRows) { row in
                FloatUpRow(index: row.index, maxLoad: 15, enable: true, animateToken: enterAnimToken) {
                    DDLItemCardSwipeable(
                        title: row.item.name,
                        remainingTimeAlt: row.remainingTimeText,
                        note: row.item.note,
                        progress: row.progress,
                        isStarred: row.item.isStared,
                        categoryBadge: row.categoryBadge,
                        status: row.status,
                        selectionMode: selectionMode,
                        selected: selection.containsTask(row.item.id),
                        onTap: {
                            detailSheetDetent = .medium
                            detailSheetItem = row.item
                        },
                        onLongPressSelect: {
                            if selectionMode {
                                toggleTaskSelection(row.item.id)
                            } else {
                                enterTaskSelection(with: row.item.id)
                            }
                        },
                        onToggleSelect: {
                            toggleTaskSelection(row.item.id)
                        },
                        onComplete: {
                            Task { @MainActor in
                                let isNowCompleted = await vm.toggleComplete(row.item)
                                listAnimToken += 1
                                if isNowCompleted { confetti.fire() }
                            }
                        },
                        onDelete: {
                            pendingDeleteItems = [row.item]
                            pendingDeleteHabits = []
                            showDeleteConfirm = true
                        },
                        onGiveUp: {
                            if row.item.state.isAbandonedLike {
                                Task { await vm.toggleGiveUpItem(item: row.item) }
                            } else {
                                pendingGiveUpItem = row.item
                                showGiveUpConfirm = true
                            }
                        },
                        onArchive: {
                            Task { await vm.toggleArchiveItem(item: row.item) }
                        },
                        onEdit: {
                            editSheetItem = row.item
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    @ViewBuilder
    private func habitsSectionContent(state: HomeBoardDerivedState) -> some View {
        habitOverviewRows
        habitCardsContent(state: state)
    }

    @ViewBuilder
    private var habitOverviewRows: some View {
        HabitProgressView(progress: vm.getTodayCompletionRatio())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .padding(.vertical, 8)
            .id("habit-progress-\(enterAnimToken)")

        habitWeekRow
    }

    @ViewBuilder
    private var habitWeekRow: some View {
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
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func habitCardsContent(state: HomeBoardDerivedState) -> some View {
        if vm.displayHabits.isEmpty {
            emptyView(text: "暂无待打卡习惯", icon: "leaf")
                .padding(.top, 40)
        } else {
            ForEach(state.habitRows) { row in
                FloatUpRow(index: row.index + 1, maxLoad: 15, enable: true, animateToken: enterAnimToken) {
                    HabitItemCard(
                        habit: row.item.habit,
                        doneCount: row.item.doneCount,
                        targetCount: row.item.targetCount,
                        isCompleted: row.item.isCompleted,
                        status: row.item.isCompleted ? .completed : .undergo,
                        remainingText: row.item.scheduleHintText,
                        sharedProgressText: row.item.progressText,
                        sharedScheduleLabel: row.item.scheduleLabel,
                        categoryBadge: row.categoryBadge,
                        isSelected: selection.containsHabit(row.item.habit.id),
                        selectionMode: selectionMode,
                        canToggle: row.item.canApplyPrimaryAction,
                        onToggle: {
                            Task {
                                let finished = await vm.toggleHabitRecord(item: row.item)
                                if finished { confetti.fire() }
                            }
                        },
                        onToggleSelect: {
                            toggleHabitSelection(row.item.habit.id)
                        },
                        onLongPress: {
                            if selectionMode {
                                toggleHabitSelection(row.item.habit.id)
                            } else {
                                enterHabitSelection(with: row.item.habit.id)
                            }
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: !selectionMode) {
                        if !selectionMode {
                            Button {
                                pendingDeleteItems = []
                                pendingDeleteHabits = [row.item.habit]
                                showDeleteConfirm = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .tint(.red)
                            
                            Button {
                                editSheetHabit = row.item.habit
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: !selectionMode) {
                        if !selectionMode {
                            Button {
                                Task { await vm.archiveHabit(row.item.habit) }
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

    private var toolbarSegmentedControl: some View {
        Picker("Task Segment", selection: $taskSegment) {
            ForEach(TaskSegment.allCases) { segment in
                Text(segment.rawValue).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
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
        } else if showsToolbarSegmentPicker {
            ToolbarItem(placement: .principal) {
                toolbarSegmentedControl
            }
        }
    }

    private func enterTaskSelection(with id: String) {
        withAnimation(.smooth(duration: 0.24, extraBounce: 0)) {
            selection.enterTask(id)
        }
    }

    private func enterHabitSelection(with id: String) {
        withAnimation(.smooth(duration: 0.24, extraBounce: 0)) {
            selection.enterHabit(id)
        }
    }

    private func toggleTaskSelection(_ id: String) {
        selection.toggleTask(id)
    }

    private func toggleHabitSelection(_ id: String) {
        selection.toggleHabit(id)
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
        selection.sanitize(validTaskIDs: viewState.validTaskIDs, validHabitIDs: viewState.validHabitIDs)
    }

    private func clearSelection() {
        withAnimation(.smooth(duration: 0.24, extraBounce: 0)) {
            selection.clear()
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

}
