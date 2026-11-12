import XCTest

final class FocusNativeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testConfirmationCancellationAndSavedTaskCompletion() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "DeadlinerFocusValidation" else {
            throw XCTSkip("Requires isolated focus validation simulator")
        }
        let app = XCUIApplication()
        app.launch()
        openFocus(app, name: "Focus parity result fixture", habit: false)
        app.buttons["focus.start.stopwatch"].tap()
        XCTAssertTrue(app.buttons["focus.pause"].waitForExistence(timeout: 10))
        closeFocus(app)
        let row = app.buttons["Focus parity result fixture"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        revealTaskActions(row)
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(app.buttons["结束计时并完成任务"].waitForExistence(timeout: 10))
        let cancel = app.buttons["取消"].firstMatch
        if cancel.exists { cancel.tap() }
        else {
            // Native iOS popovers omit the cancel row and cancel through their dismissal region.
            let dismissal = app.otherElements["PopoverDismissRegion"]
            XCTAssertTrue(dismissal.exists)
            dismissal.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).tap()
        }
        XCTAssertTrue(app.buttons["focus.global.open"].waitForExistence(timeout: 10))
        app.buttons["focus.global.open"].tap()
        XCTAssertTrue(app.buttons["focus.finish"].waitForExistence(timeout: 10))
        app.buttons["focus.finish"].tap()
        let complete = app.buttons["focus.result.complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()
        XCTAssertTrue(app.staticTexts["任务已完成"].waitForExistence(timeout: 10))
        XCTAssertFalse(complete.exists)
        screenshot(app, "focus-result-complete-task")
        closeFocus(app)
        XCTAssertFalse(app.buttons["focus.global.open"].exists)

        openFocus(app, name: "Focus parity confirmation fixture", habit: false)
        app.buttons["focus.start.stopwatch"].tap()
        XCTAssertTrue(app.buttons["focus.pause"].waitForExistence(timeout: 10))
        closeFocus(app)
        let confirmedRow = app.buttons["Focus parity confirmation fixture"].firstMatch
        revealTaskActions(confirmedRow)
        app.buttons["完成"].firstMatch.tap()
        let confirm = app.buttons["结束计时并完成任务"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.buttons["Focus parity confirmation fixture、已完成"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["focus.global.open"].exists)
        screenshot(app, "focus-confirmed-completion")
    }

    @MainActor
    func testHabitFocusArchiveAndDeleteConfirmations() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "DeadlinerFocusValidation" else {
            throw XCTSkip("Requires isolated focus validation simulator")
        }
        let app = XCUIApplication()
        app.launch()
        for (name, deleting) in [("Focus parity archive habit fixture", false), ("Focus parity delete habit fixture", true)] {
            openFocus(app, name: name, habit: true)
            app.buttons["focus.start.stopwatch"].tap()
            XCTAssertTrue(app.buttons["focus.pause"].waitForExistence(timeout: 10))
            closeFocus(app)
            let row = app.buttons[name].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            if deleting {
                row.swipeLeft()
                app.buttons["删除"].firstMatch.tap()
                XCTAssertTrue(app.alerts["确认删除习惯？"].waitForExistence(timeout: 10))
                app.alerts["确认删除习惯？"].buttons["删除"].tap()
            } else {
                row.swipeRight()
                app.buttons["归档"].firstMatch.tap()
            }
            let confirm = app.buttons[deleting ? "结束计时并删除" : "结束计时并归档"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 10))
            confirm.tap()
            let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
            XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
            XCTAssertFalse(app.buttons["focus.global.open"].exists)
            screenshot(app, deleting ? "habit-focus-delete-confirmed" : "habit-focus-archive-confirmed")
        }
    }

    @MainActor
    func testTaskSwipeOrderAndFullSwipeCompletion() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "DeadlinerFocusValidation" else {
            throw XCTSkip("Requires isolated DeadlinerFocusValidation simulator fixtures")
        }
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["清单"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["清单"].firstMatch.tap()
        app.buttons["任务"].firstMatch.tap()
        let taskName = "Focus full swipe task fixture"
        let row = app.buttons.matching(NSPredicate(format: "label == %@", taskName)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        revealTaskActions(row)
        let complete = app.buttons["完成"].firstMatch
        let focus = app.buttons["focus.entry.task"].firstMatch
        let giveUp = app.buttons["放弃"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        XCTAssertTrue(focus.exists)
        XCTAssertTrue(giveUp.exists)
        XCTAssertLessThan(complete.frame.midX, focus.frame.midX)
        XCTAssertLessThan(focus.frame.midX, giveUp.frame.midX)
        screenshot(app, "task-swipe-complete-focus-giveup")
        focus.tap()
        XCTAssertTrue(app.buttons["focus.start.stopwatch"].waitForExistence(timeout: 10))
        closeFocus(app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let rowY = row.frame.midY
        origin.withOffset(CGVector(dx: 24, dy: rowY)).press(forDuration: 0.05,
            thenDragTo: origin.withOffset(CGVector(dx: app.frame.width - 8, dy: rowY)))
        XCTAssertFalse(app.buttons["focus.start.stopwatch"].exists)
        let noActiveRow = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [noActiveRow], timeout: 10), .completed)
        let completedRow = app.buttons.matching(NSPredicate(format: "label == %@", taskName + "、已完成")).firstMatch
        XCTAssertTrue(completedRow.waitForExistence(timeout: 10))
        XCTAssertTrue(completedRow.staticTexts["已完成"].exists)
        XCTAssertFalse(app.buttons["focus.entry.task"].exists)
        screenshot(app, "task-full-swipe-completed")
    }

    @MainActor
    private func revealTaskActions(_ row: XCUIElement) {
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)))
    }

    @MainActor
    func testTaskHabitAndAccessoryFlows() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "DeadlinerFocusValidation" else {
            throw XCTSkip("Requires isolated DeadlinerFocusValidation simulator fixtures")
        }
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            let allow = alert.buttons["Allow"].exists ? alert.buttons["Allow"] : alert.buttons["允许"]
            if allow.exists { allow.tap(); return true }
            return false
        }
        app.launch()
        if app.buttons["跳过"].waitForExistence(timeout: 3) { app.buttons["跳过"].tap() }
        XCTAssertFalse(app.buttons["focus.management.open"].exists)
        XCTAssertFalse(app.buttons["focus.global.open"].exists)
        openFocus(app, name: "Focus native task fixture", habit: false)
        screenshot(app, "task-stopwatch-setup")
        app.buttons["focus.start.stopwatch"].tap()
        XCTAssertTrue(app.buttons["focus.pause"].waitForExistence(timeout: 10))
        screenshot(app, "task-active-dial")
        app.buttons["focus.pause"].tap()
        XCTAssertTrue(app.buttons["focus.resume"].waitForExistence(timeout: 10))
        closeFocus(app)
        XCTAssertTrue(app.buttons["focus.global.open"].waitForExistence(timeout: 10))
        screenshot(app, "task-paused-accessory")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["focus.global.open"].waitForExistence(timeout: 30))
        app.buttons["focus.global.open"].tap()
        app.buttons["focus.resume"].tap()
        XCTAssertTrue(app.buttons["focus.pause"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        app.buttons["focus.finish.complete"].tap()
        XCTAssertTrue(app.staticTexts["本轮已结束"].waitForExistence(timeout: 10))
        closeFocus(app)
        XCTAssertFalse(app.buttons["focus.global.open"].exists)

        openFocus(app, name: "Focus native quantity fixture", habit: true)
        app.buttons["focus.start.stopwatch"].tap()
        XCTAssertTrue(app.buttons["focus.pause"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        app.buttons["focus.finish.record"].tap()
        let amount = app.textFields["focus.habit.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["focus.habit.confirm"].isEnabled)
        amount.tap()
        amount.typeText("12")
        screenshot(app, "habit-quantity-confirm")
        app.buttons["focus.habit.confirm"].tap()
        XCTAssertTrue(app.staticTexts["本轮已结束"].waitForExistence(timeout: 10))
        screenshot(app, "habit-completed-history")
        closeFocus(app)
        XCTAssertFalse(app.buttons["focus.global.open"].exists)

        openFocus(app, name: "Focus native binary fixture", habit: true)
        app.buttons["倒计时"].tap()
        screenshot(app, "habit-countdown-setup")
        app.buttons["focus.start.countdown"].tap()
        XCTAssertTrue(app.buttons["focus.pause"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        app.buttons["focus.finish.record"].tap()
        XCTAssertTrue(app.buttons["focus.habit.confirm"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["focus.habit.amount"].exists)
        app.buttons["focus.habit.confirm"].tap()
        XCTAssertTrue(app.staticTexts["本轮已结束"].waitForExistence(timeout: 10))
        screenshot(app, "habit-binary-countdown-actual-history")
        closeFocus(app)
        XCTAssertFalse(app.buttons["focus.global.open"].exists)
    }

    @MainActor
    func testZHistoryAndStatisticsFlows() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "DeadlinerFocusValidation" else {
            throw XCTSkip("Requires isolated DeadlinerFocusValidation simulator fixtures")
        }
        let app = XCUIApplication()
        app.launch()
        openFocus(app, name: "Focus native binary fixture", habit: true)
        app.buttons["focus.start.stopwatch"].tap()
        XCTAssertTrue(app.buttons["focus.pause"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        app.buttons["focus.finish"].tap()
        XCTAssertTrue(app.staticTexts["本轮已结束"].waitForExistence(timeout: 10))
        app.swipeUp()
        let prefix = NSPredicate(format: "identifier BEGINSWITH %@", "focus.history.")
        let history = app.descendants(matching: .any).matching(prefix).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        let recordID = history.identifier
        XCTAssertTrue(history.isHittable)
        history.press(forDuration: 1)
        app.buttons["更正时长"].tap()
        let correction = app.alerts["更正记录时长"]
        XCTAssertTrue(correction.waitForExistence(timeout: 5))
        let seconds = correction.textFields.firstMatch
        seconds.tap()
        seconds.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (seconds.value as? String ?? "").count) + "1")
        correction.buttons["更正"].tap()
        screenshot(app, "history-corrected-one-second")
        history.press(forDuration: 1)
        app.buttons["删除记录"].tap()
        app.buttons["删除"].tap()
        let deletedRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", recordID)).firstMatch
        XCTAssertFalse(deletedRow.waitForExistence(timeout: 2))
        screenshot(app, "history-deleted-checkin-preserved")
        closeFocus(app)
        XCTAssertFalse(app.buttons["focus.global.open"].exists)
        let overview = app.buttons["概览"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        overview.tap()
        let summary = app.staticTexts["今日专注"]
        for _ in 0..<8 where !summary.isHittable { app.swipeUp() }
        XCTAssertTrue(summary.exists)
        screenshot(app, "overview-focus-summary")
        for tab in ["趋势", "上月"] {
            let button = app.buttons[tab].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            let title = app.staticTexts[tab == "趋势" ? "近 7 天专注" : "上月专注"]
            for _ in 0..<8 where !title.isHittable { app.swipeUp() }
            XCTAssertTrue(title.exists)
            screenshot(app, "overview-" + tab)
        }
    }

    @MainActor
    func testLiveActivityIslandControlsAndDeepLink() throws {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "DeadlinerFocusValidation" else {
            throw XCTSkip("Requires isolated focus validation simulator")
        }
        let app = XCUIApplication()
        app.launch()
        openFocus(app, name: "Live Activity UI fixture", habit: false)
        app.buttons["focus.start.stopwatch"].tap()
        XCTAssertTrue(app.buttons["focus.pause"].waitForExistence(timeout: 10))
        defer {
            app.activate()
            if app.buttons["focus.finish"].exists { app.buttons["focus.finish"].tap() }
        }
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.028)).press(forDuration: 1.2)
        let pause = springboard.buttons["暂停"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 10), springboard.debugDescription)
        screenshot(springboard, "live-activity-expanded-running")
        pause.tap()
        let resume = springboard.buttons["继续"].firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        screenshot(springboard, "live-activity-expanded-paused")
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        // Tapping the compact presentation must return directly to this focus session.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.028)).tap()
        XCTAssertTrue(app.buttons["focus.finish"].waitForExistence(timeout: 10))
        screenshot(app, "live-activity-deep-link-current-focus")
        app.buttons["focus.finish"].tap()
        XCTAssertTrue(app.staticTexts["本轮已结束"].waitForExistence(timeout: 10))
        closeFocus(app)
        XCTAssertFalse(app.buttons["focus.global.open"].exists)
    }

    @MainActor
    private func openFocus(_ app: XCUIApplication, name: String, habit: Bool) {
        let home = app.buttons["清单"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30))
        home.tap()
        app.buttons[habit ? "习惯" : "任务"].firstMatch.tap()
        let row = app.buttons[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        if habit { row.swipeRight() } else { revealTaskActions(row) }
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus.entry.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        screenshot(app, habit ? "habit-swipe-entry" : "task-swipe-entry")
        entry.tap()
        XCTAssertTrue(app.buttons["focus.start.stopwatch"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func closeFocus(_ app: XCUIApplication) {
        let close = app.buttons["focus.done"]
        for _ in 0..<6 where !close.isHittable { app.swipeUp() }
        XCTAssertTrue(close.isHittable)
        close.tap()
    }

    @MainActor
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        // Allow the system's remote-view transition to settle before visual evidence.
        if name.hasPrefix("live-activity-") { Thread.sleep(forTimeInterval: 0.5) }
        let capture = name.hasPrefix("live-activity-") ? XCUIScreen.main.screenshot() : app.screenshot()
        if name.hasPrefix("live-activity-") {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
            try? capture.pngRepresentation.write(to: file)
            print("LIVE_ACTIVITY_SCREENSHOT " + file.path)
        }
        let attachment = XCTAttachment(screenshot: capture)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
