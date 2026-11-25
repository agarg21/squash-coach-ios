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

        app.buttons["startSet"].tap()
        let count = app.staticTexts["repCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == %@", "3"), evaluatedWith: count)
        waitForExpectations(timeout: 40)
        shot("03-during-set")

        app.buttons["stopSet"].tap()
        XCTAssertTrue(app.navigationBars["Set summary"].waitForExistence(timeout: 5))
        shot("04-summary")
        app.buttons["Done"].tap()

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        shot("05-progress")
    }
}
