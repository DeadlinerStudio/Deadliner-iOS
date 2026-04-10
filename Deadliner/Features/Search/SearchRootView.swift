//
//  SearchRootView.swift
//  Deadliner
//
//  Created by Codex on 2026/4/2.
//

import SwiftUI

struct RichSearchTabView: View {
    @Binding var query: String
    @Binding var overlayProgress: CGFloat

    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false
    @State private var scope: SearchScope = .all
    @StateObject private var captureStore = CaptureStore()
    @State private var activeTasks: [DDLItem] = []
    @State private var activeHabits: [Habit] = []
    @State private var archivedTasks: [DDLItem] = []
    @State private var archivedHabits: [Habit] = []
    @State private var habitStatusMap: [Int64: HabitWithDailyStatus] = [:]
    @State private var isLoading = true
    @State private var selectedTaskForEdit: DDLItem?
    @State private var selectedHabitForEdit: Habit?
    @State private var selectedInspirationForEdit: CaptureInboxItem?
    @State private var inspirationConversionRequest: CaptureConversionRequest?
    @State private var pendingDeleteTarget: RichSearchDeleteTarget?
    @State private var showDeleteAlert = false
    @State private var pendingGiveUpTask: DDLItem?
    @State private var showGiveUpAlert = false

    private let taskRepo = TaskRepository.shared
    private let habitRepo = HabitRepository.shared

    private var isBrowsingHome: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var taskActions: SearchTaskActions {
        SearchTaskActions(
            onToggleCompletion: toggleTaskCompletion,
            onDelete: { task in
                pendingDeleteTarget = .task(task)
                showDeleteAlert = true
            },
            onGiveUp: { task in
                if task.state.isAbandonedLike {
                    Task { await toggleTaskGiveUp(task) }
                } else {
                    pendingGiveUpTask = task
                    showGiveUpAlert = true
                }
            },
            onArchive: archiveTask,
            onEdit: { task in
                selectedTaskForEdit = task
            },
            onUnarchive: unarchiveTask
        )
    }

    private var habitActions: SearchHabitActions {
        SearchHabitActions(
            onToggle: toggleHabit,
            onDelete: { habit in
                pendingDeleteTarget = .habit(habit)
                showDeleteAlert = true
            },
            onArchive: archiveHabit,
            onEdit: { habit in
                selectedHabitForEdit = habit
            },
            onUnarchive: unarchiveHabit
        )
    }

    private var inspirationActions: SearchInspirationActions {
        SearchInspirationActions(
            onOpen: { item in
                selectedInspirationForEdit = item
            },
            onDelete: { item in
                pendingDeleteTarget = .inspiration(item)
                showDeleteAlert = true
            },
            onConvertToTask: { item in
                inspirationConversionRequest = CaptureConversionRequest(kind: .task, item: item, consumedIDs: [item.id])
            },
            onConvertToHabit: { item in
                inspirationConversionRequest = CaptureConversionRequest(kind: .habit, item: item, consumedIDs: [item.id])
            },
            onAIConvertToTask: { item in
                inspirationConversionRequest = CaptureConversionRequest(kind: .aiTask, item: item, consumedIDs: [item.id])
            },
            onAIConvertToHabit: { item in
                inspirationConversionRequest = CaptureConversionRequest(kind: .aiHabit, item: item, consumedIDs: [item.id])
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView("搜索索引加载中...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .padding(.top, 24)
                } else if isBrowsingHome {
                    SearchBrowseHomeView()
                        .transition(
                            .asymmetric(
                                insertion: .opacity,
                                removal: .opacity.combined(with: .move(edge: .top))
                            )
                        )
                } else {
                    SearchResultsView(
                        scope: $scope,
                        query: query,
                        inspirations: captureStore.items,
                        activeTasks: activeTasks,
                        activeHabits: activeHabits,
                        archivedTasks: archivedTasks,
                        archivedHabits: archivedHabits,
                        habitStatusMap: habitStatusMap,
                        taskActions: taskActions,
                        habitActions: habitActions,
                        inspirationActions: inspirationActions
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        )
                    )
                }
            }
            .modifier(SearchListStyleModifier(useInsetGrouped: isBrowsingHome))
            .scrollContentBackground(.hidden)
            .animation(.smooth(duration: 0.22, extraBounce: 0), value: isBrowsingHome)
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.automatic)
            .searchable(text: $query, prompt: searchPrompt)
            .navigationDestination(for: SearchBrowseCategory.self) { category in
                SearchCategoryDetailView(
                    category: category,
                    activeTasks: SearchViewSupport.tasks(
                        for: category,
                        activeTasks: activeTasks,
                        archivedTasks: archivedTasks
                    ),
                    activeHabits: SearchViewSupport.habits(for: category, activeHabits: activeHabits),
                    archivedTasks: SearchViewSupport.archivedTasks(for: category, archivedTasks: archivedTasks),
                    archivedHabits: SearchViewSupport.archivedHabits(for: category, archivedHabits: archivedHabits),
                    habitStatusMap: habitStatusMap,
                    taskActions: taskActions,
                    habitActions: habitActions
                )
            }
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
                overlayProgress = min(max(newValue / 120, 0), 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .ddlDataChanged)) { _ in
                Task { await reload() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .captureInboxChanged)) { _ in
                captureStore.reload()
            }
            .sheet(item: $selectedTaskForEdit) { item in
                EditTaskSheetView(repository: TaskRepository.shared, item: item)
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
            .sheet(item: $selectedInspirationForEdit) { item in
                CaptureItemDetailSheet(
                    item: item,
                    onSave: { updatedText in
                        captureStore.updateItem(id: item.id, text: updatedText)
                    },
                    onConvertToTask: {
                        selectedInspirationForEdit = nil
                        inspirationConversionRequest = CaptureConversionRequest(kind: .task, item: item, consumedIDs: [item.id])
                    },
                    onConvertToHabit: {
                        selectedInspirationForEdit = nil
                        inspirationConversionRequest = CaptureConversionRequest(kind: .habit, item: item, consumedIDs: [item.id])
                    },
                    onAIConvertToTask: {
                        selectedInspirationForEdit = nil
                        inspirationConversionRequest = CaptureConversionRequest(kind: .aiTask, item: item, consumedIDs: [item.id])
                    },
                    onAIConvertToHabit: {
                        selectedInspirationForEdit = nil
                        inspirationConversionRequest = CaptureConversionRequest(kind: .aiHabit, item: item, consumedIDs: [item.id])
                    },
                    onDelete: {
                        selectedInspirationForEdit = nil
                        pendingDeleteTarget = .inspiration(item)
                        showDeleteAlert = true
                    }
                )
            }
            .sheet(item: $inspirationConversionRequest) { request in
                inspirationConversionDestination(for: request)
            }
            .alert(deleteAlertTitle, isPresented: $showDeleteAlert) {
                Button("取消", role: .cancel) {
                    pendingDeleteTarget = nil
                }
                Button("删除", role: .destructive) {
                    if let target = pendingDeleteTarget {
                        Task { await performDelete(target) }
                    }
                }
            } message: {
                Text(deleteAlertMessage)
            }
            .alert("确认放弃任务？", isPresented: $showGiveUpAlert) {
                Button("取消", role: .cancel) {
                    pendingGiveUpTask = nil
                }
                Button("放弃", role: .destructive) {
                    if let task = pendingGiveUpTask {
                        Task { await toggleTaskGiveUp(task) }
                    }
                }
            } message: {
                if let task = pendingGiveUpTask {
                    Text("「\(task.name)」将被标记为已放弃。之后你仍可以恢复它，或将它归档。")
                } else {
                    Text("任务将被标记为已放弃。")
                }
            }
        }
    }

    private var searchPrompt: String {
        switch scope {
        case .all:
            return "搜索任务、习惯、灵感、归档内容..."
        case .active:
            return "搜索当前清单和灵感..."
        case .archive:
            return "搜索归档..."
        }
    }

    private var deleteAlertTitle: String {
        switch pendingDeleteTarget {
        case .task:
            return "确认删除任务？"
        case .habit:
            return "确认删除习惯？"
        case .inspiration:
            return "确认删除灵感？"
        case .none:
            return "确认删除？"
        }
    }

    private var deleteAlertMessage: String {
        switch pendingDeleteTarget {
        case .task(let item):
            return "将删除「\(item.name)」。此操作不可撤销。"
        case .habit(let habit):
            return "将删除「\(habit.name)」。此操作不可撤销。"
        case .inspiration(let item):
            return "将删除「\(item.text)」。此操作不可撤销。"
        case .none:
            return "此操作不可撤销。"
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let tasks = taskRepo.getDDLsByType(.task)
            async let habits = habitRepo.getAllHabits()
            let (allTasks, allHabits) = try await (tasks, habits)

            activeTasks = allTasks.filter { !$0.isArchived }
            archivedTasks = allTasks.filter { $0.isArchived }
            activeHabits = allHabits.filter { $0.status != .archived }
            archivedHabits = allHabits.filter { $0.status == .archived }
            habitStatusMap = await buildHabitStatuses(for: activeHabits)
        } catch {
            print("RichSearchTab reload failed: \(error)")
        }
    }

    private func buildHabitStatuses(for habits: [Habit]) async -> [Int64: HabitWithDailyStatus] {
        var result: [Int64: HabitWithDailyStatus] = [:]

        for habit in habits {
            if let status = await buildStatusForToday(habit: habit) {
                result[habit.id] = status
            }
        }

        return result
    }

    @ViewBuilder
    private func inspirationConversionDestination(for request: CaptureConversionRequest) -> some View {
        switch request.kind {
        case .task:
            NavigationStack {
                TaskEditorSheetView(
                    repository: TaskRepository.shared,
                    mode: .add,
                    initialDraft: TaskDraft(
                        name: request.item.text,
                        note: "",
                        startTime: Date(),
                        endTime: Date().addingTimeInterval(3600),
                        isStarred: false
                    ),
                    onSaved: {
                        captureStore.consumeItems(ids: Set(request.consumedIDs))
                        inspirationConversionRequest = nil
                    }
                )
            }
        case .habit:
            NavigationStack {
                HabitEditorSheetView(
                    mode: .add,
                    initialDraft: HabitDraft(
                        name: request.item.text,
                        description: "",
                        period: .daily,
                        goalType: .perPeriod,
                        timesPerPeriod: "1",
                        totalTarget: "100"
                    ),
                    onSaved: {
                        captureStore.consumeItems(ids: Set(request.consumedIDs))
                        inspirationConversionRequest = nil
                    }
                )
            }
        case .aiTask:
            NavigationStack {
                TaskEditorSheetView(
                    repository: TaskRepository.shared,
                    mode: .add,
                    initialDraft: .empty(),
                    onSaved: {
                        captureStore.consumeItems(ids: Set(request.consumedIDs))
                        inspirationConversionRequest = nil
                    },
                    initialAIInput: request.item.text,
                    autoRunAIOnAppear: true
                )
            }
        case .aiHabit:
            NavigationStack {
                HabitEditorSheetView(
                    mode: .add,
                    initialDraft: .empty(),
                    onSaved: {
                        captureStore.consumeItems(ids: Set(request.consumedIDs))
                        inspirationConversionRequest = nil
                    },
                    initialAIInput: request.item.text,
                    autoRunAIOnAppear: true
                )
            }
        }
    }

    private func buildStatusForToday(habit: Habit) async -> HabitWithDailyStatus? {
        let today = Date()
        let bounds = habitRepo.periodBounds(period: habit.period, date: today)
        let queryStart = habit.goalType == .total ? Date(timeIntervalSince1970: 0) : bounds.0
        let queryEnd = habit.goalType == .total ? today : bounds.1

        do {
            let records = try await habitRepo.getRecordsForHabitInRange(
                habitId: habit.id,
                startDate: queryStart,
                endDateInclusive: queryEnd
            )
            let done = records.filter { $0.status == .completed }.reduce(0) { $0 + $1.count }
            let target = habit.goalType == .total
                ? habit.totalTarget.map { max(1, $0) } ?? max(1, done)
                : max(1, habit.timesPerPeriod)

            return HabitWithDailyStatus(
                habit: habit,
                doneCount: done,
                targetCount: target,
                isCompleted: habit.totalTarget != nil ? done >= (habit.totalTarget ?? 0) : done >= target
            )
        } catch {
            return nil
        }
    }

    private func toggleTaskCompletion(_ item: DDLItem) async {
        var updated = item

        do {
            try updated.transition(using: item.isCompleted ? .restoreActive : .markComplete)
            updated.completeTime = updated.isCompleted ? Date().toLocalISOString() : ""
            try await taskRepo.updateDDL(updated)
            await reload()
        } catch {
            print("RichSearchTab toggleTaskCompletion failed: \(error)")
        }
    }

    private func archiveTask(_ item: DDLItem) async {
        var updated = item

        do {
            try updated.transition(using: .markArchive)
            try await taskRepo.updateDDL(updated)
            await reload()
        } catch {
            print("RichSearchTab archiveTask failed: \(error)")
        }
    }

    private func toggleTaskGiveUp(_ item: DDLItem) async {
        var updated = item

        do {
            try updated.transition(using: item.state.isAbandonedLike ? .restoreActive : .markGiveUp)
            updated.completeTime = updated.state.isAbandonedLike ? Date().toLocalISOString() : ""
            try await taskRepo.updateDDL(updated)
            await reload()
        } catch {
            print("RichSearchTab toggleTaskGiveUp failed: \(error)")
        }
    }

    private func unarchiveTask(_ item: DDLItem) async {
        var updated = item

        do {
            try updated.transition(using: .unarchive)
            try await taskRepo.updateDDL(updated)
            await reload()
        } catch {
            print("RichSearchTab unarchiveTask failed: \(error)")
        }
    }

    private func archiveHabit(_ habit: Habit) async {
        do {
            var updated = habit
            updated.status = .archived
            try await habitRepo.updateHabit(updated)
            await reload()
            NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        } catch {
            print("RichSearchTab archiveHabit failed: \(error)")
        }
    }

    private func unarchiveHabit(_ habit: Habit) async {
        do {
            var updated = habit
            updated.status = .active
            try await habitRepo.updateHabit(updated)
            await reload()
            NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        } catch {
            print("RichSearchTab unarchiveHabit failed: \(error)")
        }
    }

    private func toggleHabit(_ status: HabitWithDailyStatus) async {
        do {
            try await habitRepo.toggleRecord(habitId: status.habit.id, date: Date())
            await reload()
        } catch {
            print("RichSearchTab toggleHabit failed: \(error)")
        }
    }

    private func performDelete(_ target: RichSearchDeleteTarget) async {
        defer { pendingDeleteTarget = nil }

        do {
            switch target {
            case .task(let item):
                try await taskRepo.deleteDDL(item.id)
            case .habit(let habit):
                try await habitRepo.deleteHabitByDdlId(ddlId: habit.ddlId)
            case .inspiration(let item):
                captureStore.deleteItem(id: item.id)
            }
            await reload()
        } catch {
            print("RichSearchTab performDelete failed: \(error)")
        }
    }
}
