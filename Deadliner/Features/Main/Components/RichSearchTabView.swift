//
//  RichSearchTabView.swift
//  Deadliner
//
//  Created by Codex on 2026/3/30.
//

import SwiftUI

private enum SearchScope: String, CaseIterable, Identifiable {
    case all = "全部"
    case active = "清单"
    case archive = "归档"

    var id: String { rawValue }
}

struct RichSearchTabView: View {
    @Binding var query: String
    @Binding var overlayProgress: CGFloat

    @AppStorage("settings.ai.is_configured") private var isAIConfigured: Bool = false
    @State private var scope: SearchScope = .all
    @State private var activeTasks: [DDLItem] = []
    @State private var activeHabits: [Habit] = []
    @State private var archivedTasks: [DDLItem] = []
    @State private var archivedHabits: [Habit] = []
    @State private var habitStatusMap: [Int64: HabitWithDailyStatus] = [:]
    @State private var isLoading = true
    @State private var selectedTaskForEdit: DDLItem?
    @State private var selectedHabitForEdit: Habit?
    @State private var pendingDeleteTarget: RichSearchDeleteTarget?
    @State private var showDeleteAlert = false
    @State private var pendingGiveUpTask: DDLItem?
    @State private var showGiveUpAlert = false

    private let taskRepo = TaskRepository.shared
    private let habitRepo = HabitRepository.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                }

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
            .searchable(text: $query, prompt: searchPrompt)
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
            .sheet(item: $selectedTaskForEdit) { item in
                EditTaskSheetView(
                    repository: TaskRepository.shared,
                    item: item
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

    private var searchHintRow: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("搜索整个 Deadliner")
                .font(.headline)
            Text("支持同时搜索任务、习惯和归档内容。")
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
            remainingTimeAlt: remainingTimeText(for: item.task),
            note: item.task.note,
            progress: progress(for: item.task),
            isStarred: item.task.isStared,
            status: status(for: item.task),
            onTap: { },
            onComplete: {
                Task { await toggleTaskCompletion(item.task) }
            },
            onDelete: {
                pendingDeleteTarget = .task(item.task)
                showDeleteAlert = true
            },
            onGiveUp: {
                if item.task.state.isAbandonedLike {
                    Task { await toggleTaskGiveUp(item.task) }
                } else {
                    pendingGiveUpTask = item.task
                    showGiveUpAlert = true
                }
            },
            onArchive: {
                Task { await archiveTask(item.task) }
            },
            onEdit: {
                selectedTaskForEdit = item.task
            }
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func activeHabitRow(_ item: SearchHabitResult) -> some View {
        let status = habitStatusMap[item.habit.id] ?? fallbackStatus(for: item.habit)
        let ebbinghausState = getEbbinghausState(habit: item.habit, targetDate: Date())

        return HabitItemCard(
            habit: status.habit,
            doneCount: status.doneCount,
            targetCount: status.targetCount,
            isCompleted: status.isCompleted,
            status: status.isCompleted ? .completed : .undergo,
            remainingText: ebbinghausState.text,
            canToggle: ebbinghausState.isDue,
            onToggle: {
                Task { await toggleHabit(status) }
            },
            onLongPress: {
                selectedHabitForEdit = item.habit
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                pendingDeleteTarget = .habit(item.habit)
                showDeleteAlert = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            .tint(.red)

            Button {
                selectedHabitForEdit = item.habit
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await archiveHabit(item.habit) }
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
            startTime: formatDate(item.task.startTime),
            completeTime: archivedTaskDetail(for: item.task),
            note: item.task.note,
            onUndo: {
                Task { await unarchiveTask(item.task) }
            },
            onDelete: {
                pendingDeleteTarget = .task(item.task)
                showDeleteAlert = true
            }
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func archivedHabitRow(_ item: SearchHabitResult) -> some View {
        ArchivedDDLItemCard(
            title: item.habit.name,
            startTime: formatHabitDetail(item.habit),
            completeTime: "归档于 \(formatDate(item.habit.updatedAt))",
            note: item.habit.description ?? "无备注",
            onUndo: {
                Task { await unarchiveHabit(item.habit) }
            },
            onDelete: {
                pendingDeleteTarget = .habit(item.habit)
                showDeleteAlert = true
            }
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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

    private func searchResults(in tasks: [DDLItem], archived: Bool = false) -> [SearchTaskResult] {
        let tokens = queryTokens

        return tasks.compactMap { item in
            let title = item.name
            let subtitle = taskSubtitle(for: item, archived: archived)
            let detail = [item.note, item.endTime, item.startTime, item.completeTime]
                .joined(separator: "\n")
            let score = searchScore(title: title, subtitle: subtitle, detail: detail, tokens: tokens)
            guard score > 0 else { return nil }
            return SearchTaskResult(task: item, sortScore: score)
        }
        .sorted(by: searchSortComparator)
    }

    private func searchResults(in habits: [Habit], archived: Bool = false) -> [SearchHabitResult] {
        let tokens = queryTokens

        return habits.compactMap { habit in
            let title = habit.name
            let subtitle = habitSubtitle(for: habit)
            let detail = [habit.description ?? "", habit.updatedAt, habit.createdAt, habitPeriodText(for: habit)]
                .joined(separator: "\n")
            let score = searchScore(title: title, subtitle: subtitle, detail: detail, tokens: tokens)
            guard score > 0 else { return nil }
            return SearchHabitResult(habit: habit, sortScore: score)
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

    private func searchSortComparator<T: RichSearchSortable>(_ lhs: T, _ rhs: T) -> Bool {
        if lhs.sortScore != rhs.sortScore {
            return lhs.sortScore > rhs.sortScore
        }
        return lhs.sortTitle.localizedStandardCompare(rhs.sortTitle) == .orderedAscending
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
            if item.state.isAbandonedLike {
                return item.completeTime.isEmpty ? "已放弃归档" : "放弃于 \(item.completeTime)"
            }
            return item.completeTime.isEmpty ? "已归档" : "完成于 \(item.completeTime)"
        }

        if item.state.isAbandonedLike {
            return "已放弃"
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
        case .daily:
            return "每日"
        case .weekly:
            return "每周"
        case .monthly:
            return "每月"
        case .ebbinghaus:
            return "艾宾浩斯"
        case .once:
            return "单次"
        }
    }

    private var searchPrompt: String {
        switch scope {
        case .all:
            return "搜索任务、习惯、归档内容..."
        case .active:
            return "搜索当前清单..."
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
        case .none:
            return "此操作不可撤销。"
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
            }
            await reload()
        } catch {
            print("RichSearchTab performDelete failed: \(error)")
        }
    }

    private func fallbackStatus(for habit: Habit) -> HabitWithDailyStatus {
        HabitWithDailyStatus(
            habit: habit,
            doneCount: 0,
            targetCount: max(1, habit.totalTarget ?? habit.timesPerPeriod),
            isCompleted: false
        )
    }

    private func status(for item: DDLItem) -> DDLStatus {
        if item.state.isAbandonedLike {
            return .abandoned
        }

        if item.isCompleted {
            return .completed
        }

        guard let end = DeadlineDateParser.safeParseOptional(item.endTime) else {
            return .undergo
        }

        let now = Date()
        if end < now {
            return .passed
        }

        let hours = end.timeIntervalSince(now) / 3600
        if hours <= 24 {
            return .near
        }
        return .undergo
    }

    private func remainingTimeText(for item: DDLItem) -> String {
        if item.state.isAbandonedLike {
            return item.isArchived ? "已放弃归档" : "已放弃"
        }

        if item.isCompleted {
            return "已完成"
        }

        guard let end = DeadlineDateParser.safeParseOptional(item.endTime) else {
            return item.endTime
        }

        let now = Date()
        let diffSec = end.timeIntervalSince(now)
        let diffHours = Int(floor(diffSec / 3600.0))

        if diffSec < 0 {
            return "已逾期 \(abs(diffHours)) 小时"
        }

        let days = diffHours / 24
        let hours = diffHours % 24

        if days > 0 {
            return "\(days)天 \(hours)小时"
        }

        return hours == 0 ? "不足1小时" : "\(hours)小时"
    }

    private func progress(for item: DDLItem) -> CGFloat {
        guard
            let start = DeadlineDateParser.safeParseOptional(item.startTime),
            let end = DeadlineDateParser.safeParseOptional(item.endTime),
            end > start
        else {
            return item.isCompleted ? 1 : 0
        }

        if item.isCompleted {
            return 1
        }

        let now = Date()
        if now <= start {
            return 0
        }
        if now >= end {
            return 1
        }

        let raw = now.timeIntervalSince(start) / end.timeIntervalSince(start)
        return CGFloat(min(max(raw, 0), 1))
    }

    private func getEbbinghausState(habit: Habit, targetDate: Date) -> EbbinghausState {
        if habit.period != .ebbinghaus {
            return EbbinghausState(isDue: true, text: "")
        }

        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: targetDate)

        guard let createdAtDate = DeadlineDateParser.safeParseOptional(habit.createdAt) else {
            return EbbinghausState(isDue: true, text: "")
        }

        let startDay = calendar.startOfDay(for: createdAtDate)
        let diffDays = calendar.dateComponents([.day], from: startDay, to: targetDay).day ?? 0
        let curve = [0, 1, 2, 4, 7, 15, 30, 60]

        if diffDays < 0 {
            return EbbinghausState(isDue: false, text: "\(-diffDays) 天后开始")
        }

        if curve.contains(diffDays) {
            return EbbinghausState(isDue: true, text: "")
        }

        if let nextDay = curve.first(where: { $0 > diffDays }) {
            return EbbinghausState(isDue: false, text: "\(nextDay - diffDays) 天后复习")
        }

        return EbbinghausState(isDue: false, text: "已完成记忆周期")
    }

    private func formatDate(_ rawValue: String) -> String {
        guard let date = DeadlineDateParser.safeParseOptional(rawValue) else {
            return rawValue.isEmpty ? "未知时间" : rawValue
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private func formatHabitDetail(_ habit: Habit) -> String {
        "\(habitPeriodText(for: habit)) · 创建于 \(formatDate(habit.createdAt))"
    }

    private func archivedTaskDetail(for item: DDLItem) -> String {
        if item.state.isAbandonedLike {
            return item.completeTime.isEmpty ? "已放弃归档" : "放弃于 \(formatDate(item.completeTime))"
        }

        return formatDate(item.completeTime)
    }
}

private enum RichSearchDeleteTarget {
    case task(DDLItem)
    case habit(Habit)
}

private protocol RichSearchSortable {
    var sortScore: Int { get }
    var sortTitle: String { get }
}

private struct SearchTaskResult: Identifiable, RichSearchSortable {
    let task: DDLItem
    let sortScore: Int

    var id: Int64 { task.id }
    var sortTitle: String { task.name }
}

private struct SearchHabitResult: Identifiable, RichSearchSortable {
    let habit: Habit
    let sortScore: Int

    var id: Int64 { habit.id }
    var sortTitle: String { habit.name }
}

private extension SearchScope {
    var allowsActive: Bool {
        self == .all || self == .active
    }

    var allowsArchive: Bool {
        self == .all || self == .archive
    }
}
