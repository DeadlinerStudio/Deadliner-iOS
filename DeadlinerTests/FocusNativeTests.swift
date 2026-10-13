import Foundation
import Testing
import Shared
@testable import Deadliner

@MainActor
struct FocusNativeTests {
    @Test func targetChangeLabelsAndDistinctWarnings() {
        #expect(FocusPendingChange(uid: "a", habit: false, delete: false, action: .markComplete, sessionUID: "s").operation == "完成任务")
        #expect(FocusPendingChange(uid: "a", habit: false, delete: false, action: .markGiveUp, sessionUID: "s").operation == "放弃任务")
        #expect(FocusPendingChange(uid: "a", habit: true, delete: false, action: nil, sessionUID: "s").operation == "归档")
        #expect(FocusPendingChange(uid: "a", habit: true, delete: true, action: nil, sessionUID: "s").operation == "删除")
        let messages = [FocusTimerWarning.clockAnomaly, .longRunning, .excessiveDuration, .alarmUnavailable].compactMap(FocusTimerFormatting.warningMessage)
        #expect(messages.count == 4)
        #expect(Set(messages).count == 4)
        #expect(messages[1].contains("12 小时"))
    }
    @Test func durationAndAmountValidation() {
        #expect(FocusTimerFormatting.clock(65) == "01:05")
        #expect(FocusTimerFormatting.clock(3_661) == "01:01:01")
        #expect(FocusTimerFormatting.clock(-1) == "00:00")
        #expect(FocusTimerFormatting.duration(45) == "45 秒")
        #expect(FocusTimerFormatting.validAmount("12") == 12)
        #expect(FocusTimerFormatting.validAmount("0") == nil)
        #expect(FocusTimerFormatting.validAmount("-2") == nil)
        #expect(FocusTimerFormatting.validAmount("1.5") == nil)
        #expect(FocusTimerFormatting.validAmount("2147483648") == nil)
    }

    @Test func reminderAcceptsCoreTimestampPrecision() {
        #expect(FocusAlarmPortAdapter.parseDate("2026-10-12T05:00:00Z") != nil)
        #expect(FocusAlarmPortAdapter.parseDate("2026-10-12T05:00:00.123Z") != nil)
        #expect(FocusAlarmPortAdapter.parseDate("bad-date") == nil)
    }

    @Test func notificationRouteRetainsAndConsumesOnlyOnce() {
        FocusNotificationRoute.shared.open("notification-session-fixture")
        #expect(FocusNotificationRoute.shared.consume() == "notification-session-fixture")
        #expect(FocusNotificationRoute.shared.consume() == nil)
    }

    /// Fixtures are independently named in the new, isolated validation simulator only.
    @Test func seedNativeFocusFixtures() async throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "DeadlinerFocusValidation" else { return }
        let existing = try await PersistenceStores.tasks.allTasks()
        await FocusTimerPresentationModel.shared.connect()
        if let timer = FocusTimerPresentationModel.shared.state?.timer,
           existing.contains(where: { $0.id == timer.taskUid && ["Focus parity result fixture", "Focus parity confirmation fixture"].contains($0.name) }) {
            FocusTimerPresentationModel.shared.discard()
            for _ in 0..<100 {
                if FocusTimerPresentationModel.shared.state?.timer == nil { break }
                try await _Concurrency.Task.sleep(for: .milliseconds(50))
            }
            #expect(FocusTimerPresentationModel.shared.state?.timer == nil)
        }
        for taskName in ["Focus native task fixture", "Focus full swipe task fixture", "Focus parity result fixture", "Focus parity confirmation fixture"] {
            if !existing.contains(where: { $0.name == taskName && $0.state == .active }) {
                _ = try await PersistenceStores.tasks.createTask(TaskInsertParams(
                    name: taskName, startTime: "", endTime: "", state: .active, completeTime: "",
                    note: "", isStared: false, subTasks: [], calendarEventId: nil))
            }
        }
        let habits = try await PersistenceStores.habits.allHabits()
        if let timer = FocusTimerPresentationModel.shared.state?.timer, timer.target?.kind == .habit,
           habits.contains(where: { $0.id == timer.target?.uid && ["Focus parity archive habit fixture", "Focus parity delete habit fixture"].contains($0.name) }) {
            FocusTimerPresentationModel.shared.discard()
            for _ in 0..<100 {
                if FocusTimerPresentationModel.shared.state?.timer == nil { break }
                try await _Concurrency.Task.sleep(for: .milliseconds(50))
            }
            #expect(FocusTimerPresentationModel.shared.state?.timer == nil)
        }
        for (name, count) in [("Focus native quantity fixture", 20), ("Focus native binary fixture", 1),
                              ("Focus parity archive habit fixture", 1), ("Focus parity delete habit fixture", 1)] {
            if !habits.contains(where: { $0.name == name && $0.status == .active }) {
                _ = try await PersistenceStores.habits.createHabitWithCarrier(
                    name: name, period: .daily, weekdaysMask: 127, timesPerPeriod: count,
                    goalType: .perPeriod, totalTarget: nil, description: "", color: nil,
                    iconKey: nil, categoryUID: nil, sortOrder: 0, alarmTime: nil)
            }
        }
        // Reset only these private simulator fixture records between UI runs.
        let seededHabits = try await PersistenceStores.habits.allHabits()
        for habit in seededHabits where ["Focus native quantity fixture", "Focus native binary fixture"].contains(habit.name) {
            try await PersistenceStores.habits.clearHabitRecords(habitID: habit.id, date: Date())
        }
        UserDefaults.standard.set(true, forKey: OnboardingStorageKey.hasSeen)
        UserDefaults.standard.set(false, forKey: OnboardingStorageKey.showOnNextLaunch)
        UserDefaults.standard.set(HomeStyleOption.rich.rawValue, forKey: "settings.home.style")
    }
}
