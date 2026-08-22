//
//  ArchiveView.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import SwiftUI

struct ArchiveView: View {
    @Binding var query: String
    var onScrollProgressChange: ((CGFloat) -> Void)? = nil
    var compactLayoutProgress: CGFloat? = nil
    
    @State private var selectedTab: Int = 0 // 0: 任务, 1: 习惯
    @State private var archivedTasks: [DDLItem] = []
    @State private var archivedHabits: [Habit] = []
    @State private var isLoading: Bool = true
    
    @State private var itemToDelete: DeleteTarget?
    @State private var showDeleteAlert: Bool = false
    @State private var showDeleteAllAlert: Bool = false
    @State private var scrollProgress: CGFloat = 0

    private var compactLayoutEnabled: Bool {
        compactLayoutProgress != nil
    }

    private var effectiveCompactProgress: CGFloat {
        compactLayoutProgress ?? scrollProgress
    }
    
    enum DeleteTarget {
        case task(DDLItem)
        case habit(Habit)
        
        var name: String {
            switch self {
            case .task(let item): return item.name
            case .habit(let habit): return habit.name
            }
        }
    }

    private let taskRepo: any KMPTaskUIStore = PersistenceStores.tasks
    private let habitRepo: any KMPHabitUIStore = PersistenceStores.habits

    var body: some View {
        List {
            Section {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .padding(.top, 40)
                } else if selectedTab == 0 {
                    taskRows
                } else {
                    habitRows
                }
            } header: {
                if !compactLayoutEnabled {
                    segmentedControl
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .deadlinerScrollEdgeEffect()
        .background(Color.clear)
        .safeAreaInset(edge: .top, spacing: 0) {
            if compactLayoutEnabled {
                segmentedControlInset
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            max(0, geo.contentOffset.y + geo.contentInsets.top)
        } action: { _, newValue in
            scrollProgress = min(max(newValue / 120, 0), 1)
            let p = min(max(newValue / 120, 0), 1)
            onScrollProgressChange?(p)
        }
        .task {
            await refreshData()
        }
        .onChange(of: selectedTab) { _ in
            Task { await refreshData() }
        }
        .alert("永久删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let target = itemToDelete {
                    Task { await performDelete(target) }
                }
            }
        } message: {
            if let target = itemToDelete {
                Text("确定要永久删除\(target.name == "" ? "该项" : "“\(target.name)”")吗？此操作不可恢复。")
            }
        }
        .alert("全部永久删除", isPresented: $showDeleteAllAlert) {
            Button("取消", role: .cancel) { }
            Button("全部删除", role: .destructive) {
                Task { await performDeleteAll() }
            }
        } message: {
            Text("确定要永久删除所有归档的\(selectedTab == 0 ? "任务" : "习惯")吗？此操作不可恢复。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .ddlDeleteAllArchived)) { _ in
            if selectedTab == 0 {
                if !archivedTasks.isEmpty { showDeleteAllAlert = true }
            } else {
                if !archivedHabits.isEmpty { showDeleteAllAlert = true }
            }
        }
    }

    private var segmentedControl: some View {
        Picker("归档类型", selection: $selectedTab) {
            Text("任务").tag(0)
            Text("习惯").tag(1)
        }
        .pickerStyle(.segmented)
        .glassEffect()
        .textCase(nil)
        .padding(
            EdgeInsets(
                top: RichCompactLayout.headerTopPadding(
                    enabled: compactLayoutEnabled,
                    progress: effectiveCompactProgress
                ),
                leading: 12,
                bottom: 4,
                trailing: 12
            )
        )
    }

    private var segmentedControlInset: some View {
        segmentedControl
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(Color.clear)
    }
    
    // MARK: - Row Views
    
    @ViewBuilder
    private var taskRows: some View {
        let filtered = archivedTasks.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        }
        
        if filtered.isEmpty {
            emptyRow(text: "没有归档的任务")
        } else {
            ForEach(filtered) { item in
                ArchivedDDLItemCard(
                    title: item.name,
                    startTime: formatDate(item.startTime),
                    completeTime: archivedTaskDetail(for: item),
                    note: item.note,
                    indicatorColor: item.state.isAbandonedLike ? .gray : .blue,
                    onUndo: {
                        Task { await performUndo(.task(item)) }
                    },
                    onDelete: {
                        itemToDelete = .task(item)
                        showDeleteAlert = true
                    }
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            
            // 底部间距
            Spacer().frame(height: 80)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }
    
    @ViewBuilder
    private var habitRows: some View {
        let filtered = archivedHabits.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        }
        
        if filtered.isEmpty {
            emptyRow(text: "没有归档的习惯")
        } else {
            ForEach(filtered) { habit in
                ArchivedDDLItemCard(
                    title: habit.name,
                    startTime: formatHabitDetail(habit),
                    completeTime: "归档于 \(formatDate(habit.updatedAt))",
                    note: habit.description ?? "无备注",
                    onUndo: {
                        Task { await performUndo(.habit(habit)) }
                    },
                    onDelete: {
                        itemToDelete = .habit(habit)
                        showDeleteAlert = true
                    }
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            
            // 底部间距
            Spacer().frame(height: 80)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }
    
    private func emptyRow(text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
    
    // MARK: - Logic
    
    private func refreshData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            if selectedTab == 0 {
                let all = try await taskRepo.allTasks()
                archivedTasks = all.filter { $0.isArchived }
                    .sorted { (a, b) in
                        let tA = a.completeTime
                        let tB = b.completeTime
                        return tA > tB
                    }
            } else {
                let all = try await habitRepo.allHabits()
                archivedHabits = all.filter { $0.status == .archived }
                    .sorted { $0.updatedAt > $1.updatedAt }
            }
        } catch {
            print("Failed to load archived data: \(error)")
        }
    }

    private func performUndo(_ target: DeleteTarget) async {
        do {
            switch target {
            case .task(let item):
                _ = try await taskRepo.performTaskAction(id: item.id, action: .unarchive)
                archivedTasks.removeAll { $0.id == item.id }
            case .habit(let habit):
                _ = try await habitRepo.performHabitStatusAction(id: habit.id, action: .restore)
                archivedHabits.removeAll { $0.id == habit.id }
            }
        } catch {
            print("Undo failed: \(error)")
        }
    }
    
    private func performDelete(_ target: DeleteTarget) async {
        do {
            switch target {
            case .task(let item):
                try await taskRepo.deleteTask(id: item.id)
                archivedTasks.removeAll { $0.id == item.id }
            case .habit(let habit):
                try await habitRepo.deleteHabit(carrierID: habit.id)
                archivedHabits.removeAll { $0.id == habit.id }
            }
        } catch {
            print("Delete failed: \(error)")
        }
    }
    
    private func performDeleteAll() async {
        do {
            if selectedTab == 0 {
                for item in archivedTasks {
                    try await taskRepo.deleteTask(id: item.id)
                }
                archivedTasks.removeAll()
            } else {
                for habit in archivedHabits {
                    try await habitRepo.deleteHabit(carrierID: habit.id)
                }
                archivedHabits.removeAll()
            }
        } catch {
            print("Delete all failed: \(error)")
        }
    }
    
    private func formatDate(_ dateStr: String) -> String {
        guard let date = DeadlineDateParser.safeParseOptional(dateStr) else { return "未知时间" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
    
    private func formatHabitDetail(_ habit: Habit) -> String {
        let schedule = HabitSharedPresentationMapper.scheduleLabel(for: habit)
        if habit.goalType == .total { return schedule }
        return "\(schedule) · 目标 \(max(1, habit.timesPerPeriod))"
    }

    private func archivedTaskDetail(for item: DDLItem) -> String {
        if item.state.isAbandonedLike {
            return item.completeTime.isEmpty ? "已放弃归档" : "放弃于 \(formatDate(item.completeTime))"
        }
        return item.completeTime.isEmpty ? "已归档" : "完成于 \(formatDate(item.completeTime))"
    }
}
