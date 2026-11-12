import ActivityKit
import AppIntents
import Foundation
import Shared
import Testing
import UIKit
import XCTest
@testable import Deadliner

@Suite(.serialized)
@MainActor
struct FocusLiveActivityTests {
    @Test func routesDecodeSessionAndRejectUnrelatedOrAmbiguousURLs() {
        let uid = "session/a+b &c"
        let url = FocusLiveActivityAttributes(sessionUID: uid).url
        #expect(FocusLiveActivityAttributes.sessionUID(from: url) == uid)
        for raw in ["https://focus?session=a", "deadliner://add?session=a", "deadliner://focus?session=", "deadliner://focus?session=a&session=b", "deadliner://focus?session=a&action=finish"] {
            #expect(FocusLiveActivityAttributes.sessionUID(from: URL(string: raw)!) == nil)
        }
    }

    @Test func nativeIntentsRoundTripToKMPAndDoNotResurrectDismissedActivity() async throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "DeadlinerFocusValidation" else {
            throw XCTSkip("Requires isolated focus validation simulator")
        }
        let model = FocusTimerPresentationModel.shared
        await model.connect()
        guard model.state?.timer == nil else { throw XCTSkip("Preserve existing focus session") }
        let task = try await PersistenceStores.tasks.createTask(TaskInsertParams(
            name: "Live Activity integration fixture", startTime: "", endTime: "", state: .active, completeTime: "",
            note: "", isStared: false, subTasks: [], calendarEventId: nil))
        model.selectTask(task)
        try await eventually { model.state?.selectedTarget?.uid == task }
        model.startStopwatch()
        try await eventually { model.state?.timer != nil }
        await FocusLiveActivityCoordinator.shared.synchronize()
        let first = try #require(await KMPPersistenceRuntime.shared.focusLiveActivityInfo().activeTimer)
        let activity = Activity<FocusLiveActivityAttributes>.activities.first { $0.attributes.sessionUID == first.sessionUid }
        #expect(activity != nil)
        if let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
            await FocusLiveActivityCoordinator.shared.synchronize()
            #expect(!Activity<FocusLiveActivityAttributes>.activities.contains { $0.attributes.sessionUID == first.sessionUid && $0.activityState == .active })
        }
        _ = try await FocusLiveActivityActionIntent(sessionUID: first.sessionUid, version: first.updatedAt, action: "pause").perform()
        let paused = try #require(await KMPPersistenceRuntime.shared.focusLiveActivityInfo().activeTimer)
        #expect(paused.state == .paused)
        _ = try await FocusLiveActivityActionIntent(sessionUID: first.sessionUid, version: first.updatedAt, action: "finish").perform()
        #expect(await KMPPersistenceRuntime.shared.focusLiveActivityInfo().activeTimer?.state == .paused)
        _ = try await FocusLiveActivityActionIntent(sessionUID: paused.sessionUid, version: paused.updatedAt, action: "resume").perform()
        try await eventually { (model.state?.timer?.elapsedSeconds ?? 0) >= 1 }
        let resumed = try #require(await KMPPersistenceRuntime.shared.focusLiveActivityInfo().activeTimer)
        #expect(resumed.state == .running)
        _ = try await FocusLiveActivityActionIntent(sessionUID: resumed.sessionUid, version: resumed.updatedAt, action: "finish").perform()
        #expect(await KMPPersistenceRuntime.shared.focusLiveActivityInfo().activeTimer == nil)
        #expect(!Activity<FocusLiveActivityAttributes>.activities.contains { $0.attributes.sessionUID == first.sessionUid && $0.activityState == .active })
        model.startStopwatch()
        try await eventually { model.state?.timer != nil }
        let second = try #require(await KMPPersistenceRuntime.shared.focusLiveActivityInfo().activeTimer)
        #expect(second.sessionUid != first.sessionUid)
        _ = try await FocusLiveActivityActionIntent(sessionUID: first.sessionUid, version: resumed.updatedAt, action: "finish").perform()
        #expect(await KMPPersistenceRuntime.shared.focusLiveActivityInfo().activeTimer?.sessionUid == second.sessionUid)
        model.discard()
        try await eventually { model.state?.timer == nil }
        await FocusLiveActivityCoordinator.shared.synchronize()
        model.startCountdown(minutes: 1)
        try await eventually { model.state?.timer?.mode == .countdown }
        await FocusLiveActivityCoordinator.shared.synchronize()
        let countdownUID = try #require(model.state?.timer?.sessionUid)
        let countdown = try #require(Activity<FocusLiveActivityAttributes>.activities.first { $0.attributes.sessionUID == countdownUID })
        #expect(countdown.content.state.isCountdown)
        #expect(countdown.content.state.timerEnd.timeIntervalSinceNow > 55)
        #expect(countdown.content.state.timerEnd.timeIntervalSinceNow <= 60)
        model.pause()
        try await eventually { model.state?.timer?.state == .paused }
        await FocusLiveActivityCoordinator.shared.synchronize()
        #expect(countdown.content.state.isPaused)
        #expect(countdown.content.state.frozenSeconds == model.state?.timer?.remainingSeconds?.int64Value)
        model.discard()
        try await eventually { model.state?.timer == nil }
        await FocusLiveActivityCoordinator.shared.synchronize()
        try await PersistenceStores.tasks.deleteTask(id: task)
        let tasks = try await PersistenceStores.tasks.allTasks()
        if !tasks.contains(where: { $0.name == "Live Activity UI fixture" && $0.state == .active }) {
            _ = try await PersistenceStores.tasks.createTask(TaskInsertParams(
                name: "Live Activity UI fixture", startTime: "", endTime: "", state: .active, completeTime: "",
                note: "", isStared: false, subTasks: [], calendarEventId: nil))
        }
        UserDefaults.standard.set(true, forKey: OnboardingStorageKey.hasSeen)
        UserDefaults.standard.set(false, forKey: OnboardingStorageKey.showOnNextLaunch)
        UserDefaults.standard.set(HomeStyleOption.rich.rawValue, forKey: "settings.home.style")
        print("LiveActivity system activity created: \(activity != nil)")
    }

    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "FocusLiveActivityTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "KMP state delivery timed out"])
    }
}
