import XCTest

/// Walks through one whole set in demo mode (a scripted figure instead of the camera) and saves a screenshot of every screen.
final class FlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testASetFromStartToProgress() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()

        XCTAssertTrue(app.buttons["startSet"].waitForExistence(timeout: 30))
        let inView = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Whole body in view")).firstMatch
        XCTAssertTrue(inView.waitForExistence(timeout: 10))
        shot("01-ready")

        app.buttons["setDetails"].tap()
        XCTAssertTrue(app.navigationBars["Set details"].waitForExistence(timeout: 5))
        shot("02-set-details")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Set details"].waitForNonExistence(timeout: 15))

        // a tap that lands while the sheet is still sliding away is ignored on a slow simulator, so try again if the set has not started
        let count = app.staticTexts["repCount"]
        let start = app.buttons["startSet"]
        for _ in 0..<3 where !count.exists {
            if start.exists && start.isHittable { start.tap() }
            _ = count.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(count.exists)
        expectation(for: NSPredicate(format: "label == %@", "3"), evaluatedWith: count)
        waitForExpectations(timeout: 40)
        shot("03-during-set")

        app.buttons["stopSet"].tap()
        XCTAssertTrue(app.navigationBars["Set summary"].waitForExistence(timeout: 5))
        shot("04-summary")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Set summary"].waitForNonExistence(timeout: 15))

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        shot("05-progress")
    }
}
