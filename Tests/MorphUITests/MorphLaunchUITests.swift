import XCTest

/// UI smoke test (SPEC §11): launch, hand the window a fixture, convert it,
/// and check the output landed beside the source.
///
/// XCUITest can't drag from Finder, so the fixture arrives through
/// `MORPH_UI_TEST_FILES`, which Debug builds read at launch.
final class MorphLaunchUITests: XCTestCase {

    private var folder: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MorphUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
    }

    override func tearDownWithError() throws {
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
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

    func testConvertsADroppedFileBesideItsSource() throws {
        let folder = try XCTUnwrap(folder)
        let fixture = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "heic-64x48", withExtension: "heic"),
            "the HEIC fixture isn't in the test bundle")
        let source = folder.appendingPathComponent("photo.heic")
        try FileManager.default.copyItem(at: fixture, to: source)

        let app = XCUIApplication()
        app.launchEnvironment["MORPH_UI_TEST_FILES"] = source.path
        app.launch()

        let summary = app.staticTexts["source-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "the file never reached the drop zone")
        // On macOS a static text's string is its value, not its label.
        let text = summary.value as? String ?? summary.label
        XCTAssertTrue(text.hasPrefix("1 image"), "summary was \(text)")

        let jpeg = app.buttons["target-jpg"]
        XCTAssertTrue(jpeg.waitForExistence(timeout: 5), "no JPEG chip")
        jpeg.click()

        XCTAssertTrue(
            app.buttons["reveal"].waitForExistence(timeout: 30), "the job never finished")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("photo.jpg").path),
            "photo.jpg isn't beside photo.heic")

        app.terminate()
    }
}
