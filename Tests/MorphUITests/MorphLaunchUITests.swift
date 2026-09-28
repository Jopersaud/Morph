import XCTest

/// UI smoke test (SPEC §11).
///
/// M0 only checks that the app launches and shows its window. M1 extends this
/// to drop a fixture on the window and wait for the job to finish.
final class MorphLaunchUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testAppLaunchesAndShowsAWindow() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "Morph did not reach the foreground")
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 10),
            "Morph launched without a window")

        app.terminate()
    }
}
