import XCTest

final class OverviewDashboardUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testMonthBoundariesAndIndependentRoutes() throws {
        let app = XCUIApplication()
        app.launch()
        let overview = app.buttons["概览"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 40))
        overview.tap()
        XCTAssertTrue(app.staticTexts["月度活动"].waitForExistence(timeout: 30))
        let forward = app.buttons["下个月"]
        XCTAssertTrue(forward.exists)
        XCTAssertFalse(forward.isEnabled)
        capture(app, "overview-current-month")

        app.buttons["上个月"].tap()
        XCTAssertTrue(forward.isEnabled)
        capture(app, "overview-previous-month")
        forward.tap()
        XCTAssertFalse(forward.isEnabled)
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let day = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", today + "，")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 10))
        day.tap()
        XCTAssertTrue(app.alerts["当日活动"].waitForExistence(timeout: 5))
        capture(app, "overview-day-summary")
        app.alerts["当日活动"].buttons["完成"].tap()
        app.buttons["上个月"].tap()
        XCTAssertTrue(forward.isEnabled)

        try openCard("专注管理", in: app)
        XCTAssertTrue(app.staticTexts["累计"].waitForExistence(timeout: 15))
        capture(app, "overview-focus-management")
        back(app)
        try openCard("归档", in: app)
        capture(app, "overview-archive")
        back(app)
        try openCard("任务统计", in: app)
        XCTAssertTrue(app.staticTexts["今日概况"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["今日专注"].exists)
        capture(app, "overview-task-detail")
        back(app)
        try openCard("趋势", in: app)
        let yearly = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "年度任务贡献")).firstMatch
        for _ in 0..<10 where !yearly.exists { app.swipeUp() }
        XCTAssertTrue(yearly.exists)
        capture(app, "overview-trend-detail")
        back(app)
        capture(app, "overview-return-scroll-position")
        try openCard("月度复盘", in: app)
        XCTAssertTrue(app.staticTexts["AI 月度洞察"].waitForExistence(timeout: 15))
        capture(app, "overview-review-detail")
        app.buttons["分享"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["分享月度复盘"].waitForExistence(timeout: 10))
        capture(app, "overview-review-export")
        let preview = app.buttons["查看完整预览"]
        for _ in 0..<10 where !preview.isHittable { app.swipeUp() }
        XCTAssertTrue(preview.isHittable)
        app.buttons["查看完整预览"].tap()
        XCTAssertTrue(app.navigationBars["复盘预览"].waitForExistence(timeout: 10))
        capture(app, "overview-review-image-preview")
        app.buttons["完成"].firstMatch.tap()
        app.buttons["完成"].firstMatch.tap()
        back(app)
        XCTAssertTrue(app.buttons["下个月"].isEnabled)
        app.buttons["下个月"].tap()
        XCTAssertFalse(app.buttons["下个月"].isEnabled)
        for _ in 0..<12 where !app.staticTexts["月度活动"].isHittable { app.swipeDown() }
        capture(app, "overview-validated-root")
    }

    @MainActor
    func testDashboardAccessibilityLayout() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let overview = app.buttons["概览"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 40))
        overview.tap()
        XCTAssertTrue(app.staticTexts["月度活动"].waitForExistence(timeout: 30))
        let dateCells = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "[0-9]{4}-[0-9]{2}-[0-9]{2}，.*"))
        let heights = dateCells.allElementsBoundByIndex.map { $0.frame.height }
        XCTAssertFalse(heights.isEmpty)
        XCTAssertLessThan((heights.max() ?? 0) - (heights.min() ?? 0), 5, "Two-digit dates must stay on one line")
        capture(app, "overview-accessibility-calendar")
        for title in ["专注管理", "归档", "任务统计", "趋势", "月度复盘"] {
            let card = cardButton(title, in: app)
            for _ in 0..<15 where !card.isHittable { app.swipeUp() }
            XCTAssertTrue(card.isHittable, "Missing accessible card: \(title)")
            capture(app, "overview-accessibility-" + title)
        }
    }

    @MainActor private func cardButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }
    @MainActor private func openCard(_ title: String, in app: XCUIApplication) throws {
        let card = cardButton(title, in: app)
        for _ in 0..<12 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.isHittable, "Cannot reach \(title)")
        card.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15))
    }
    @MainActor private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
