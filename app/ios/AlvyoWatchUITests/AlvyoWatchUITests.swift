import XCTest

/// The watch app's buttons, tapped in the watch simulator (in German).
///
/// `testButtons` runs on its own, with a made-up phone (`-fakePhone`).
/// `testWithPhone` drives a hike on the paired iPhone simulator over
/// WatchConnectivity; it runs only with `TEST_RUNNER_ALVYO_PHONE=1` while
/// the phone's `integration_test/watch_test.dart` runs with
/// `--dart-define=WATCH_FROM_WATCH=true` (app/README.md).
final class AlvyoWatchUITests: XCTestCase {
  private func launch(_ arguments: [String] = []) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_CH"] + arguments
    app.launch()
    return app
  }

  /// «Beenden» and its question.
  private func stop(_ app: XCUIApplication) {
    app.buttons["stop"].tap()
    let confirm = app.buttons["Beenden"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
  }

  func testButtons() {
    let app = launch(["-fakePhone"])
    XCTAssertTrue(app.buttons["record"].waitForExistence(timeout: 10))
    app.buttons["tour-r1"].tap()

    // The hike: the map with the next turn, then the controls swiped up.
    XCTAssertTrue(app.descendants(matching: .any)["map"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Links abbiegen"].exists)
    app.swipeUp()
    let pause = app.buttons["pause"]
    XCTAssertTrue(pause.waitForExistence(timeout: 5))
    XCTAssertEqual(pause.label, "Pause")
    pause.tap()
    XCTAssertTrue(waitFor(pause, label: "Weiter"))
    pause.tap()
    XCTAssertTrue(waitFor(pause, label: "Pause"))

    stop(app)
    XCTAssertTrue(app.buttons["record"].waitForExistence(timeout: 5), "back at the tours")
  }

  func testWithPhone() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["ALVYO_PHONE"] == "1", "needs the phone's watch_test")
    let app = launch()
    // The phone starts the hike; the watch follows.
    let pause = app.buttons["pause"]
    let map = app.descendants(matching: .any)["map"]
    XCTAssertTrue(map.waitForExistence(timeout: 180), "no hike from the phone")
    app.swipeUp()
    XCTAssertTrue(pause.waitForExistence(timeout: 5))
    pause.tap()
    XCTAssertTrue(waitFor(pause, label: "Weiter", timeout: 20), "the phone did not pause")
    pause.tap()
    XCTAssertTrue(waitFor(pause, label: "Pause", timeout: 20), "the phone did not carry on")
    stop(app)
    XCTAssertTrue(app.buttons["record"].waitForExistence(timeout: 30), "the phone did not finish")
  }

  private func waitFor(_ e: XCUIElement, label: String, timeout: TimeInterval = 5) -> Bool {
    let done = expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: e)
    return XCTWaiter.wait(for: [done], timeout: timeout) == .completed
  }
}
