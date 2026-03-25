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
    
    @State private var selectedTab: Int = 0 // 0: 任务, 1: 习惯
    @State private var archivedTasks: [DDLItem] = []
    @State private var archivedHabits: [Habit] = []
    @State private var isLoading: Bool = true
    
    @State private var itemToDelete: DeleteTarget?
    @State private var showDeleteAlert: Bool = false
    @State private var showDeleteAllAlert: Bool = false
    
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

    private let taskRepo = TaskRepository.shared
    private let habitRepo = HabitRepository.shared

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
                Picker("归档类型", selection: $selectedTab) {
                    Text("任务").tag(0)
                    Text("习惯").tag(1)
                }
                .pickerStyle(.segmented)
                .glassEffect()
                .textCase(nil)
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            max(0, geo.contentOffset.y + geo.contentInsets.top)
        } action: { _, newValue in
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
                    completeTime: formatDate(item.completeTime),
                    note: item.note,
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
                let all = try await taskRepo.getAllDDLs()
                archivedTasks = all.filter { $0.isArchived }
                    .sorted { (a, b) in
                        let tA = a.completeTime
                        let tB = b.completeTime
                        return tA > tB
                    }
            } else {
                let all = try await habitRepo.getAllHabits()
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
            case .task(var item):
                try item.transition(to: .completed)
                try await taskRepo.updateDDL(item)
                archivedTasks.removeAll { $0.id == item.id }
            case .habit(var habit):
                habit.status = .active
                try await habitRepo.updateHabit(habit)
                archivedHabits.removeAll { $0.id == habit.id }
            }
            // 发送数据变更通知以刷新主页
            NotificationCenter.default.post(name: .ddlDataChanged, object: nil)
        } catch {
            print("Undo failed: \(error)")
        }
    }
    
    private func performDelete(_ target: DeleteTarget) async {
        do {
            switch target {
            case .task(let item):
                try await taskRepo.deleteDDL(item.id)
                archivedTasks.removeAll { $0.id == item.id }
            case .habit(let habit):
                try await habitRepo.deleteHabitByDdlId(ddlId: habit.ddlId)
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
                    try await taskRepo.deleteDDL(item.id)
                }
                archivedTasks.removeAll()
            } else {
                for habit in archivedHabits {
                    try await habitRepo.deleteHabitByDdlId(ddlId: habit.ddlId)
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
        let periodStr: String = {
            switch habit.period {
            case .daily: return "每日"
            case .weekly: return "每周"
            case .monthly: return "每月"
            case .ebbinghaus: return "艾宾浩斯"
            default: return "习惯"
            }
        }()
        
        let goalStr: String = {
            if habit.goalType == .total {
                return "总目标 \(habit.totalTarget ?? 0)"
            } else {
                return "\(habit.timesPerPeriod)次"
            }
        }()
        
        return "\(periodStr) · \(goalStr)"
    }
}
