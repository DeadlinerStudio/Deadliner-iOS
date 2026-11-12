#if canImport(Shared)
import Combine
import Foundation
import Shared
import UIKit

/// One presentation authority across sheets and both home styles.
@MainActor
final class FocusTimerPresentationModel: ObservableObject {
    static let shared = FocusTimerPresentationModel()
    @Published private(set) var state: FocusTimerUiState?
    @Published private(set) var activeTasks: [DDLItem] = []
    @Published private(set) var activeHabits: [Habit] = []
    @Published var message: String?
    @Published var openRequested = false
    @Published private(set) var pendingChange: FocusPendingChange?
    private var changeWaiter: CheckedContinuation<Bool, Never>?
    @Published private(set) var invalidNotificationRoute = false
    @Published private var notificationSessionUID: String?

    private var bridge: KMPFocusTimerViewModelBridge?
    private var connecting = false
    private var connectionWaiters: [CheckedContinuation<Void, Never>] = []
    private var stateWaiters: [CheckedContinuation<Void, Never>] = []
    private var tickTask: _Concurrency.Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                self.bridge?.reconcile()
                self.startTicking()
                FocusLiveActivityCoordinator.shared.requestSync()
                _Concurrency.Task { await self.loadTargets() }
            }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.disconnect() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .persistenceDataChanged)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                self?.bridge?.reconcile()
                FocusLiveActivityCoordinator.shared.requestSync()
                _Concurrency.Task { await self?.loadTargets() }
            }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .focusNotificationOpened)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                _Concurrency.Task { await self?.connect() }
            }.store(in: &cancellables)
    }

    func connect(selectedTaskUID: String? = nil, selectedHabitUID: String? = nil) async {
        if bridge == nil {
            if connecting {
                await withCheckedContinuation { connectionWaiters.append($0) }
            } else {
                connecting = true
                let created = await KMPFocusTimerViewModelBridge.make()
                bridge = created
                created.start { [weak self] state in self?.receive(state) }
                connecting = false
                let waiters = connectionWaiters
                connectionWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        if state?.isLoading != false {
            await withCheckedContinuation { stateWaiters.append($0) }
        }
        if state?.timer == nil {
            if let selectedHabitUID, !selectedHabitUID.isEmpty { bridge?.selectHabit(selectedHabitUID) }
            else if let selectedTaskUID, !selectedTaskUID.isEmpty { bridge?.selectTask(selectedTaskUID) }
        }
        await loadTargets()
        startTicking()
        if let uid = FocusNotificationRoute.shared.consume() {
            notificationSessionUID = uid
            let available = await KMPPersistenceRuntime.shared.isAvailableFocusSession(uid: uid)
            invalidNotificationRoute = !available
            if available { bridge?.selectSession(uid) }
            else { message = "这条专注记录已删除或不存在" }
            openRequested = true
        }
    }

    func disconnect() { tickTask?.cancel(); tickTask = nil }
    func refresh() { bridge?.reconcile() }
    func selectTask(_ uid: String) { invalidNotificationRoute = false; notificationSessionUID = nil; bridge?.selectTask(uid) }
    func selectHabit(_ uid: String) { invalidNotificationRoute = false; notificationSessionUID = nil; bridge?.selectHabit(uid) }
    func selectSession(_ uid: String) { invalidNotificationRoute = false; notificationSessionUID = nil; bridge?.selectSession(uid) }

    func startStopwatch() {
        invalidNotificationRoute = false
        notificationSessionUID = nil
        guard let target = state?.selectedTarget else { message = "请先选择任务或习惯"; return }
        if target.kind == .habit { bridge?.startHabitStopwatch(habitUID: target.uid) }
        else { bridge?.startStopwatch(taskUID: target.uid) }
    }
    func startCountdown(minutes: Int) {
        invalidNotificationRoute = false
        notificationSessionUID = nil
        guard let target = state?.selectedTarget else { message = "请先选择任务或习惯"; return }
        if target.kind == .habit { bridge?.startHabitCountdown(habitUID: target.uid, durationSeconds: Int64(minutes * 60)) }
        else { bridge?.startCountdown(taskUID: target.uid, durationSeconds: Int64(minutes * 60)) }
    }
    func clearNotificationRoute() {
        invalidNotificationRoute = false
        notificationSessionUID = nil
    }

    func openLiveActivity(sessionUID: String) async {
        await connect()
        let info = await KMPPersistenceRuntime.shared.focusLiveActivityInfo()
        guard info.activeTimer?.sessionUid == sessionUID, info.snapshot != nil else {
            invalidNotificationRoute = true
            notificationSessionUID = sessionUID
            message = "这次专注已结束，请在最近记录中查看"
            openRequested = true
            return
        }
        invalidNotificationRoute = false
        notificationSessionUID = nil
        bridge?.reconcile()
        openRequested = true
    }

    func performLiveActivityAction(sessionUID: String, version: String, action: String) async {
        await connect()
        guard let bridge else { return }
        let next = await bridge.executeLiveActivityAction(sessionUID: sessionUID, version: version, action: action)
        receive(next)
        await FocusLiveActivityCoordinator.shared.synchronize()
    }

    func pause() { bridge?.pause() }
    func resume() { bridge?.resume() }
    func finish() { bridge?.finish() }
    func finishAndCompleteTask() { bridge?.finishAndCompleteTask() }
    func completeSavedTask(_ uid: String) { bridge?.completeSavedTask(uid) }

    func confirmTargetChange(uid: String, habit: Bool, delete: Bool, action: TaskAction? = nil) async -> Bool {
        await connect()
        guard pendingChange == nil, changeWaiter == nil, let timer = state?.timer,
              timer.target?.uid == uid || !habit && timer.taskUid == uid else { return false }
        return await withCheckedContinuation { waiter in
            changeWaiter = waiter
            pendingChange = FocusPendingChange(uid: uid, habit: habit, delete: delete, action: action, sessionUID: timer.sessionUid)
        }
    }
    func cancelTargetChange() {
        guard pendingChange != nil else { return }
        pendingChange = nil
        let waiter = changeWaiter; changeWaiter = nil; waiter?.resume(returning: false)
    }
    func applyTargetChange() {
        guard let request = pendingChange, let bridge else { cancelTargetChange(); return }
        pendingChange = nil
        bridge.resolveConfirmedChange(uid: request.uid, habit: request.habit, delete: request.delete,
                                     action: request.action, sessionUID: request.sessionUID) { [weak self] outcome in
            guard let self else { return }
            let applied = outcome == .applied || outcome == .noOp
            if !applied { self.message = FocusTimerFormatting.outcomeMessage(outcome) ?? "操作未完成，请重试"; self.openRequested = true }
            let waiter = self.changeWaiter; self.changeWaiter = nil; waiter?.resume(returning: applied)
            if applied {
                PersistenceChangePublisher.publish(.init(resourceKinds: [.task, .habit, .habitRecord]))
                _Concurrency.Task { await KMPTaskReminderScheduler.shared.scheduleRefresh(); await KMPHabitReminderScheduler.shared.scheduleRefresh() }
            }
        }
    }
    func discard() { bridge?.discard() }
    func finishAndRecordHabit(sessionUID: String, amount: Int?, updatedAt: String?) {
        bridge?.finishAndRecordHabit(sessionUID: sessionUID, amount: amount, updatedAt: updatedAt)
    }
    func adjustSessionDuration(sessionUID: String, durationSeconds: Int64) {
        bridge?.adjustSessionDuration(sessionUID: sessionUID, durationSeconds: durationSeconds)
    }
    func deleteSession(sessionUID: String) { bridge?.deleteSession(sessionUID: sessionUID) }

    func canPresentCompletedSession(_ uid: String) -> Bool {
        !invalidNotificationRoute && (notificationSessionUID == nil || notificationSessionUID == uid)
    }

    var selectedTargetAvailable: Bool {
        guard let target = state?.selectedTarget else { return false }
        return target.kind == .habit ? activeHabits.contains { $0.id == target.uid } : activeTasks.contains { $0.id == target.uid }
    }

    var selectedTitle: String {
        if let timer = state?.timer { return timer.taskTitle }
        guard let target = state?.selectedTarget else { return "" }
        return target.kind == .habit
            ? activeHabits.first(where: { $0.id == target.uid })?.name ?? state?.selectedTaskTitle ?? "习惯"
            : activeTasks.first(where: { $0.id == target.uid })?.name ?? state?.selectedTaskTitle ?? "任务"
    }

    private func loadTargets() async {
        activeTasks = ((try? await PersistenceStores.tasks.allTasks()) ?? []).filter { $0.type == .task && $0.state == .active }
        activeHabits = ((try? await PersistenceStores.habits.allHabits()) ?? []).filter { $0.status == .active }
    }

    private func receive(_ next: FocusTimerUiState) {
        let old = state
        state = next
        if !next.isLoading {
            let signature: (FocusTimerUiState) -> String = { value in
                guard let timer = value.timer else { return "none" }
                return "\(timer.sessionUid)|\(timer.state)|\(timer.mode)|\(timer.taskTitle)|\(String(describing: timer.warning))|\(String(describing: timer.plannedDurationSeconds))|\(timer.canPause)|\(timer.canResume)|\(timer.canFinish)"
            }
            if old == nil || signature(next) != signature(old!) {
                FocusLiveActivityCoordinator.shared.requestSync()
            }
        }
        if !next.isLoading {
            let waiters = stateWaiters
            stateWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        if let error = next.error { message = error }
        else if next.lastOutcome != old?.lastOutcome || old?.isBusy == true && !next.isBusy {
            message = FocusTimerFormatting.outcomeMessage(next.lastOutcome)
        }
        let savedFactsChanged = old.map { focusFacts($0) != focusFacts(next) } ?? !focusFacts(next).isEmpty
        if !next.isLoading && (savedFactsChanged || old?.timer != nil && next.timer == nil || old?.lastCompletedTaskState != next.lastCompletedTaskState) {
            // Compare saved facts, not transient busy states: StateFlow may conflate them.
            // Also catches an offline countdown saved by foreground reconciliation.
            PersistenceChangePublisher.publish(.init(resourceKinds: [.task, .habit, .habitRecord]))
            _Concurrency.Task {
                await KMPTaskReminderScheduler.shared.scheduleRefresh()
                await KMPHabitReminderScheduler.shared.scheduleRefresh()
            }
        }
    }

    private func focusFacts(_ state: FocusTimerUiState) -> [String] {
        let sessions = state.recentSessions + state.selectedTaskRecentSessions + [state.lastCompletedSession].compactMap { $0 }
        return sessions.map { "\($0.uid)|\($0.updatedAt)|\($0.durationSeconds)|\($0.habitRecordedAmount?.intValue ?? -1)" }.sorted()
    }

    private func startTicking() {
        guard tickTask == nil, UIApplication.shared.applicationState == .active else { return }
        tickTask = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(for: .seconds(1))
                guard !_Concurrency.Task.isCancelled else { return }
                self?.bridge?.tick()
            }
        }
    }
}

struct FocusPendingChange {
    let uid: String
    let habit: Bool
    let delete: Bool
    let action: TaskAction?
    let sessionUID: String
    var operation: String {
        if delete { return "删除" }
        if habit || action == .markArchive { return "归档" }
        return action == .markGiveUp ? "放弃任务" : "完成任务"
    }
}
#endif
