import XCTest

final class TaskDetailNativeUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor
  func testPlanPersistenceAndPostponeCancellation() throws {
    guard
      ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "DeadlinerDetailValidation"
    else {
      throw XCTSkip("Requires isolated detail validation simulator")
    }
    let app = XCUIApplication()
    app.launch()
    try openDetail(app)
    XCTAssertTrue(app.buttons["detail.primary"].waitForExistence(timeout: 10))
    capture(app, "detail-native-default")
    let add = app.buttons["detail.plan.add"]
    reveal(add, app: app)
    add.tap()
    let draft =
      app.textFields["detail.plan.draft"].exists
      ? app.textFields["detail.plan.draft"] : app.textViews["detail.plan.draft"]
    XCTAssertTrue(draft.waitForExistence(timeout: 5))
    draft.tap()
    draft.typeText("新增验证步骤")
    capture(app, "detail-native-keyboard")
    app.buttons["detail.plan.save"].tap()
    XCTAssertTrue(app.staticTexts["新增验证步骤"].waitForExistence(timeout: 10))
    app.buttons["取消添加"].tap()
    let edit = app.buttons["编辑子任务：新增验证步骤"]
    reveal(edit, app: app)
    edit.tap()
    XCTAssertTrue(app.navigationBars["编辑子任务"].waitForExistence(timeout: 5))
    capture(app, "detail-native-edit")
    let editDraft =
      app.textViews["detail.plan.editDraft"].exists
      ? app.textViews["detail.plan.editDraft"] : app.textFields["detail.plan.editDraft"]
    editDraft.tap()
    editDraft.typeText("已保存")
    app.buttons["保存"].tap()
    let savedEdit = app.buttons["编辑子任务：新增验证步骤已保存"]
    reveal(savedEdit, app: app)
    savedEdit.tap()
    let cancelDraft =
      app.textViews["detail.plan.editDraft"].exists
      ? app.textViews["detail.plan.editDraft"] : app.textFields["detail.plan.editDraft"]
    cancelDraft.tap()
    cancelDraft.typeText("取消草稿")
    app.buttons["取消"].tap()
    XCTAssertFalse(app.staticTexts["新增验证步骤已保存取消草稿"].exists)
    reveal(savedEdit, app: app)
    savedEdit.tap()
    app.buttons["删除子任务"].tap()
    XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 5))
    app.buttons["detail.close"].tap()
    try openDetail(app)
    let addAgain = app.buttons["detail.plan.add"]
    reveal(addAgain, app: app)
    XCTAssertFalse(app.staticTexts["新增验证步骤已保存"].exists)
    app.buttons["detail.more"].tap()
    capture(app, "detail-native-menu")
    app.buttons["延后…"].tap()
    let original = app.staticTexts["detail.postpone.original"]
    XCTAssertTrue(original.waitForExistence(timeout: 5))
    let originalValue = original.label
    capture(app, "detail-native-postpone")
    app.buttons["取消"].tap()
    app.buttons["detail.more"].tap()
    app.buttons["延后…"].tap()
    XCTAssertTrue(original.waitForExistence(timeout: 5))
    XCTAssertEqual(original.label, originalValue)
    app.buttons["detail.postpone.confirm"].tap()
    XCTAssertTrue(app.buttons["detail.more"].waitForExistence(timeout: 10))
    app.buttons["detail.more"].tap()
    app.buttons["延后…"].tap()
    XCTAssertTrue(original.waitForExistence(timeout: 5))
    XCTAssertNotEqual(original.label, originalValue)
    app.buttons["取消"].tap()
    capture(app, "detail-native-after-postpone")
  }

  @MainActor
  func testPostponeOpensOnSingleSelectionAndHasTwoWheels() throws {
    guard
      ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "DeadlinerDetailValidation"
    else {
      throw XCTSkip("Requires isolated detail validation simulator")
    }
    let app = XCUIApplication()
    app.launch()
    try openDetail(app)
    for attempt in 0..<5 {
      app.buttons["detail.more"].tap()
      let postpone = app.buttons["延后…"]
      XCTAssertTrue(postpone.waitForExistence(timeout: 5))
      if attempt == 0 { capture(app, "detail-native-red-delete-menu") }
      postpone.tap()
      let title = app.navigationBars["延后截止时间"]
      XCTAssertTrue(
        title.waitForExistence(timeout: 5),
        "Single selection must present on attempt \(attempt + 1)")
      XCTAssertEqual(app.pickerWheels.count, 2)
      if attempt == 0 {
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "168")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "天")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 0).value as? String, "7")
        capture(app, "detail-native-two-wheel-postpone")
      }
      app.buttons["取消"].tap()
      let dismissed = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "exists == false"), object: title)
      XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }
  }

  @MainActor
  func testDarkLargeTextLayout() throws {
    guard
      ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "DeadlinerDetailValidation"
    else {
      throw XCTSkip("Requires isolated detail validation simulator")
    }
    let app = XCUIApplication()
    app.launchArguments += [
      "-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName",
      "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    try openDetail(app)
    XCTAssertTrue(app.buttons["detail.primary"].waitForExistence(timeout: 10))
    capture(app, "detail-native-dark-large-text")
    let add = app.buttons["detail.plan.add"]
    reveal(add, app: app)
    capture(app, "detail-native-dark-large-plan")
  }

  @MainActor private func openDetail(_ app: XCUIApplication) throws {
    let list = app.buttons["清单"].firstMatch
    XCTAssertTrue(list.waitForExistence(timeout: 30))
    list.tap()
    app.buttons["任务"].firstMatch.tap()
    let task = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "详情对齐验证")).firstMatch
    XCTAssertTrue(task.waitForExistence(timeout: 15))
    task.tap()
    XCTAssertTrue(app.navigationBars["任务详情"].waitForExistence(timeout: 10))
  }

  @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<6 where !element.isHittable { app.swipeUp() }
    XCTAssertTrue(element.isHittable)
  }

  @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
