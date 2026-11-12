//
//  KMPFocusTimerViewModelBridge.swift
//  Deadliner
//
//  MainActor bridge from the shared FocusTimerViewModel to SwiftUI.
//

#if canImport(Shared)
import Shared

@MainActor
final class KMPFocusTimerViewModelBridge {
    private let bridge: IosFocusTimerStateBridge

    private init(bridge: IosFocusTimerStateBridge) {
        self.bridge = bridge
    }

    static func make() async -> KMPFocusTimerViewModelBridge {
        let bridge = await KMPPersistenceRuntime.shared.focusTimerStateBridge()
        return KMPFocusTimerViewModelBridge(bridge: bridge)
    }

    func start(onState: @escaping @MainActor (FocusTimerUiState) -> Void) {
        bridge.start { state in _Concurrency.Task { @MainActor in onState(state) } }
    }

    func refresh() { bridge.refresh() }
    func reconcile() { bridge.reconcile() }
    func tick() { bridge.tick() }
    func selectTask(_ taskUID: String?) { bridge.selectTask(taskUid: taskUID) }
    func selectHabit(_ habitUID: String?) { bridge.selectHabit(habitUid: habitUID) }
    func selectSession(_ uid: String) { bridge.selectSession(sessionUid: uid) }
    func startHabitStopwatch(habitUID: String) { bridge.startHabitStopwatch(habitUid: habitUID) }
    func startHabitCountdown(habitUID: String, durationSeconds: Int64) { bridge.startHabitCountdown(habitUid: habitUID, plannedDurationSeconds: durationSeconds) }
    func finishAndRecordHabit(sessionUID: String, amount: Int?, updatedAt: String?) { bridge.finishAndRecordHabit(sessionUid: sessionUID, amount: amount.map { KotlinInt(value: Int32($0)) }, expectedHabitUpdatedAt: updatedAt) }
    func resolveHabitChange(uid: String, delete: Bool) { bridge.resolveHabitChange(habitUid: uid, delete: delete) }
    func startStopwatch(taskUID: String) { bridge.startStopwatch(taskUid: taskUID) }
    func startCountdown(taskUID: String, durationSeconds: Int64) {
        bridge.startCountdown(taskUid: taskUID, plannedDurationSeconds: durationSeconds)
    }
    func pause() { bridge.pause() }
    func resume() { bridge.resume() }
    func finish() { bridge.finish() }
    func executeLiveActivityAction(sessionUID: String, version: String, action: String) async -> FocusTimerUiState {
        await withCheckedContinuation { continuation in
            bridge.executeLiveActivityAction(action: action, sessionUid: sessionUID, version: version) { state in
                continuation.resume(returning: state)
            }
        }
    }
    func finishAndCompleteTask() { bridge.finishAndCompleteTask() }
    func completeSavedTask(_ uid: String) { bridge.completeSavedTask(sessionUid: uid) }
    func resolveConfirmedChange(uid: String, habit: Bool, delete: Bool, action: TaskAction?, sessionUID: String,
                                completion: @escaping @MainActor (FocusTimerOutcome) -> Void) {
        bridge.resolveConfirmedChange(targetUid: uid, habit: habit, delete: delete, taskAction: action, sessionUid: sessionUID) {
            outcome in _Concurrency.Task { @MainActor in completion(outcome) }
        }
    }
    func discard() { bridge.discard() }
    func adjustSessionDuration(sessionUID: String, durationSeconds: Int64) {
        bridge.adjustSessionDuration(sessionUid: sessionUID, durationSeconds: durationSeconds)
    }
    func deleteSession(sessionUID: String) { bridge.deleteSession(sessionUid: sessionUID) }

    deinit {
        bridge.close()
    }
}
#endif
