//
//  HomeViewModel.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/16.
//

import Foundation
import Combine
import os

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var tasks: [DDLItem] = []
    @Published var isLoading = false
    @Published var errorText: String?
    
    @Published var progressDir: Bool = false

    private let repo: TaskRepository
    private var cancellables = Set<AnyCancellable>()

    private var reloadTask: Task<Void, Never>?
    private var isReloading = false
    private var pendingReload = false
    
    private var suppressReloadUntil: Date? = nil

    // 防止进入页面时重复触发首刷（例如 View 重建）
    private var didInitialLoad = false

    private let logger = Logger(subsystem: "Deadliner", category: "HomeViewModel")

    init(repo: TaskRepository = .shared) {
        self.repo = repo

        NotificationCenter.default.publisher(for: .ddlDataChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }

                if let until = self.suppressReloadUntil {
                    let now = Date()
                    if now < until {
                        // 延后刷新：确保在抑制期结束后，最终能同步来自同步或其他来源的数据
                        let delayMs = Int(until.timeIntervalSince(now) * 1000) + 100
                        self.scheduleReload(delay: UInt64(delayMs * 1_000_000))
                        return
                    }
                }
                
                self.scheduleReload()
            }
            .store(in: &cancellables)
    }

    deinit {
        reloadTask?.cancel()
    }

    // MARK: - Page Lifecycle

    /// 页面进入：先刷新本地，再后台同步；仅执行一次初始流程
    func initialLoad() async {
        self.progressDir = await LocalValues.shared.getProgressDir()
        
        // 1. 无论是否已初始化，都先刷一次本地，确保 UI 立即显示
        await reload()
        
        guard !didInitialLoad else { return }
        didInitialLoad = true

        // 2. 后台静默同步，避免阻塞主线程显示
        Task {
            let syncOK = await repo.syncNow()
            logger.info("initial background sync result=\(syncOK, privacy: .public)")
            // 注意：syncNow 内部成功后会发通知，触发 scheduleReload，所以这里不需要手动 reload
        }
    }

    /// 下拉刷新：先展示本地，同时触发同步
    func pullToRefresh() async {
        isLoading = true
        // 1. 先确保本地是最新的（以防万一）
        await reload()
        
        // 2. 执行同步
        let syncOK = await repo.syncNow()
        logger.info("pull-to-refresh sync result=\(syncOK, privacy: .public)")
        
        // 3. 同步完成后再次刷新
        await reload()
        isLoading = false
    }

    // 保留兼容入口（如果别处还在调这两个）
    func loadTasks() async { await initialLoad() }
    func refresh() async { await pullToRefresh() }

    // MARK: - Local UI Patch (sync)
    /// 只做 UI 内存更新 + 立即排序，返回“更新后是否 completed”
    func toggleCompleteLocal(_ item: DDLItem) -> Bool {
        beginSuppressReload()
        
        var updated = item
        updated.isCompleted.toggle()
        updated.completeTime = updated.isCompleted ? Date().toLocalISOString() : ""

        if let idx = tasks.firstIndex(where: { $0.id == item.id }) {
            tasks[idx] = updated
        } else {
            // 理论上不会发生，但防御性处理
            tasks.append(updated)
        }

        sortTasksInPlace()
        return updated.isCompleted
    }

    // MARK: - Persist (async)
    /// 写库/同步；失败则回滚到 original
    func persistToggleComplete(original: DDLItem) async {
        var updated = original
        updated.isCompleted.toggle()
        updated.completeTime = updated.isCompleted ? Date().toLocalISOString() : ""

        do {
            try await repo.updateDDL(updated)
            // 依然可以保留 ddlDataChanged -> scheduleReload 做最终一致性校正
        } catch {
            errorText = "更新失败：\(error.localizedDescription)"
            rollbackTo(original)
        }
    }
    
    func toggleArchiveItem(item: DDLItem) async {
        var updated = item
        updated.isArchived.toggle()
        
        do {
            try await repo.updateDDL(updated)
        } catch {
            errorText = "更新失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    func stageRebuildFromCurrentSnapshot(
        snapshot: [DDLItem],
        blankDelayMs: UInt64 = 90
    ) async {
        tasks = []

        try? await Task.sleep(nanoseconds: blankDelayMs * 1_000_000)

        tasks = snapshot
    }
    
    // MARK: - Helpers
    private func sortTasksInPlace() {
        tasks.sort { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted && rhs.isCompleted
            }
            return lhs.endTime < rhs.endTime
        }
    }

    private func rollbackTo(_ original: DDLItem) {
        if let idx = tasks.firstIndex(where: { $0.id == original.id }) {
            tasks[idx] = original
        } else {
            tasks.append(original)
        }
        sortTasksInPlace()
    }

    // MARK: - User Actions

    func delete(_ item: DDLItem) async {
        do {
            try await repo.deleteDDL(item.id)
        } catch {
            errorText = "删除失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Reload Pipeline

    private func scheduleReload(delay: UInt64 = 0) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: delay)
            await self.reload()
        }
    }

    private func reload(force: Bool = false) async {
        if isReloading {
            pendingReload = true
            return
        }

        isReloading = true
        defer {
            isReloading = false
        }

        do {
            let sortedList = try await repo.getDDLsByType(.task)

            // 🟢 核心优化：如果内容（ID序列）没变，且不是强制刷新，则跳过
            if !force && sortedList.map(\.id) == self.tasks.map(\.id) {
                logger.debug("reload: data unchanged, skipping UI update.")
            } else {
                tasks = sortedList
                logger.info("reload: updated tasks count=\(sortedList.count, privacy: .public)")
            }

            errorText = nil
        } catch {
            tasks = []
            errorText = "加载失败：\(error.localizedDescription)"
            logger.error("reload failed: \(error.localizedDescription, privacy: .public)")
        }

        if pendingReload {
            pendingReload = false
            await reload()
        }
    }
    
    private func beginSuppressReload(window: TimeInterval = 0.6) {
        suppressReloadUntil = Date().addingTimeInterval(window)
    }
}
