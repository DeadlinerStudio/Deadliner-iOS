#if canImport(Shared)
import ActivityKit
import Foundation
import Shared
import UIKit

/// Serializes ActivityKit mutations and always reads fresh KMP metadata before publishing.
@MainActor
final class FocusLiveActivityCoordinator {
    static let shared = FocusLiveActivityCoordinator()
    private let defaults = UserDefaults.standard
    private let shownSessionKey = "focus.live-activity.shown-session"
    private var needsSync = false
    private var worker: _Concurrency.Task<Void, Never>?

    func requestSync() {
        needsSync = true
        guard worker == nil else { return }
        worker = _Concurrency.Task { [weak self] in
            guard let self else { return }
            while self.needsSync {
                self.needsSync = false
                await self.reconcile()
            }
            self.worker = nil
        }
    }

    func synchronize() async {
        requestSync()
        await worker?.value
    }

    private func reconcile() async {
        let info = await KMPPersistenceRuntime.shared.focusLiveActivityInfo()
        let activities = Activity<FocusLiveActivityAttributes>.activities
        guard let active = info.activeTimer, let snapshot = info.snapshot,
              snapshot.warning != .clockAnomaly,
              let started = FocusAlarmPortAdapter.parseDate(active.startedAt),
              let state = content(active: active, snapshot: snapshot),
              started.addingTimeInterval(8 * 3_600) > Date() else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let matching = activities.filter {
            $0.attributes.sessionUID == active.sessionUid && [.active, .stale].contains($0.activityState)
        }
        for activity in activities where activity.id != matching.first?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let staleAt = min(started.addingTimeInterval(8 * 3_600),
                          state.isCountdown && !state.isPaused ? state.timerEnd : Date.distantFuture)
        let next = ActivityContent(state: state, staleDate: staleAt)
        if let activity = matching.first {
            defaults.set(active.sessionUid, forKey: shownSessionKey)
            if activity.content.state != state || activity.content.staleDate != staleAt {
                await activity.update(next)
            }
            return
        }
        // A previously shown session that disappeared was dismissed or expired. Never resurrect it.
        guard defaults.string(forKey: shownSessionKey) != active.sessionUid,
              ActivityAuthorizationInfo().areActivitiesEnabled,
              UIApplication.shared.applicationState == .active else { return }
        do {
            _ = try Activity.request(attributes: FocusLiveActivityAttributes(sessionUID: active.sessionUid),
                                     content: next, pushType: nil)
            defaults.set(active.sessionUid, forKey: shownSessionKey)
        } catch {
            AppLog.event("focus.live-activity.start-failed", domain: .kmp,
                         context: ["error": String(describing: error)])
        }
    }

    private func content(active: ActiveFocusTimer, snapshot: FocusTimerSnapshot) -> FocusLiveActivityAttributes.ContentState? {
        let paused = snapshot.state == .paused
        let countdown = snapshot.mode == .countdown
        let segment = active.runningSegmentStartedAt.flatMap(FocusAlarmPortAdapter.parseDate)
        guard paused || segment != nil else { return nil }
        // Convert persisted KMP timing anchors to system-rendered SwiftUI timer dates.
        // Session state, elapsed duration and allowed actions remain KMP decisions.
        let timerStart = segment?.addingTimeInterval(-Double(active.accumulatedSeconds)) ?? Date(timeIntervalSince1970: 0)
        let timerEnd = countdown
            ? (segment ?? timerStart).addingTimeInterval(Double((active.plannedDurationSeconds?.int64Value ?? 0) - active.accumulatedSeconds))
            : timerStart.addingTimeInterval(8 * 3_600)
        return .init(version: active.updatedAt, isCountdown: countdown, isPaused: paused,
                     timerStart: timerStart, timerEnd: timerEnd,
                     frozenSeconds: countdown ? snapshot.remainingSeconds?.int64Value ?? 0 : snapshot.elapsedSeconds,
                     canPause: snapshot.canPause, canResume: snapshot.canResume, canFinish: snapshot.canFinish)
    }
}
#endif
