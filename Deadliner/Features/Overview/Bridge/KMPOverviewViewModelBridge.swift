//
//  KMPOverviewViewModelBridge.swift
//  Deadliner
//
//  MainActor bridge from the shared Overview StateFlow to SwiftUI.
//

#if canImport(Shared)
import Shared

/// Mirrors the proven task/habit bridge boundary. Keeping the Kotlin callback
/// inside this MainActor-owned object avoids passing an unisolated closure from
/// a SwiftUI view model directly into Kotlin/Native.
@MainActor
final class KMPOverviewViewModelBridge {
    private let bridge: IosOverviewStateBridge

    private init(bridge: IosOverviewStateBridge) {
        self.bridge = bridge
    }

    static func make() async -> KMPOverviewViewModelBridge {
        let bridge = await KMPPersistenceRuntime.shared.overviewStateBridge()
        return KMPOverviewViewModelBridge(bridge: bridge)
    }

    /// Requests one KMP snapshot. Database work and aggregation stay off the
    /// SwiftUI executor; KMP delivers this closure back on the main thread.
    func load(onState: @escaping @MainActor (OverviewUiState) -> Void) {
        bridge.load(onState: { state in
            _Concurrency.Task { @MainActor in onState(state) }
        })
    }

    func loadFocus(onState: @escaping @MainActor (FocusOverviewStatistics) -> Void) {
        bridge.loadFocus { state in _Concurrency.Task { @MainActor in onState(state) } }
    }

    func loadMonth(_ month: String, onState: @escaping @MainActor (OverviewMonthUiState) -> Void,
                   onError: @escaping @MainActor (String) -> Void) {
        bridge.loadMonth(monthStart: month, onState: { state in
            _Concurrency.Task { @MainActor in onState(state) }
        }, onError: { error in _Concurrency.Task { @MainActor in onError(error) } })
    }

    func loadFocusSafely(onState: @escaping @MainActor (FocusOverviewStatistics) -> Void,
                         onError: @escaping @MainActor (String) -> Void) {
        bridge.loadFocusSafely(onState: { state in _Concurrency.Task { @MainActor in onState(state) } },
                               onError: { error in _Concurrency.Task { @MainActor in onError(error) } })
    }

    func loadFocusManagement(onState: @escaping @MainActor ([FocusSession], FocusStatisticsSnapshot) -> Void,
                             onError: @escaping @MainActor (String) -> Void) {
        bridge.loadFocusManagement(onState: { sessions, statistics in
            _Concurrency.Task { @MainActor in onState(sessions, statistics) }
        }, onError: { error in _Concurrency.Task { @MainActor in onError(error) } })
    }

    func mutateFocusSession(uid: String, seconds: Int64?, onResult: @escaping @MainActor (FocusTimerOutcome, String?) -> Void) {
        bridge.mutateFocusSession(sessionUid: uid, durationSeconds: seconds.map { KotlinLong(value: $0) }, onResult: { outcome, error in
            _Concurrency.Task { @MainActor in onResult(outcome, error) }
        })
    }

    func close() {
        bridge.close()
    }

    deinit {
        bridge.close()
    }
}
#endif
