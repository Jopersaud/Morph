import XCTest

/// UI smoke test (SPEC §11): launch, hand the window a fixture, convert it,
/// and check the output landed beside the source.
///
/// XCUITest can't drag from Finder, and a `morph://` URL opened from a test
/// starts a second copy of the app, so Debug builds read the fixture from
/// `MORPH_UI_TEST_FILES` and the handoff from `MORPH_UI_TEST_HANDOFF`.
@MainActor
final class MorphLaunchUITests: XCTestCase {

    private var folder: URL?

    override func setUp() async throws {
        continueAfterFailure = false
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MorphUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
    }

    override func tearDown() async throws {
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// The app with onboarding already done, so its sheet isn't in the way.
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingCompleted", "YES"]
        return app
    }

    /// A fresh copy of the HEIC fixture in the test's folder.
    private func copyFixture(as name: String) throws -> URL {
        let folder = try XCTUnwrap(folder)
        let fixture = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "heic-64x48", withExtension: "heic"),
            "the HEIC fixture isn't in the test bundle")
        let source = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: fixture, to: source)
        return source
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    func testFirstLaunchShowsOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingCompleted", "NO"]
        app.launch()

        let next = app.buttons["onboarding-continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "no onboarding on first launch")
        next.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["extension-status"].waitForExistence(timeout: 5))
        app.buttons["onboarding-done"].click()
        XCTAssertTrue(app.staticTexts["Drop files to convert"].waitForExistence(timeout: 5))

        app.terminate()
    }

    func testAppLaunchesAndShowsAWindow() throws {
        let app = makeApp()
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
        let source = try copyFixture(as: "photo.heic")

        let app = makeApp()
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

    /// What the Finder extension does when a menu item is picked.
    func testFinderHandoffConvertsInTheBackground() throws {
        let folder = try XCTUnwrap(folder)
        let source = try copyFixture(as: "from finder.heic")
        var components = URLComponents(string: "morph://convert?target=png")
        components?.queryItems?.append(URLQueryItem(name: "path", value: source.path))

        let app = makeApp()
        app.launchEnvironment["MORPH_UI_TEST_HANDOFF"] = try XCTUnwrap(components?.url)
            .absoluteString
        app.launch()

        XCTAssertTrue(
            waitForFile(folder.appendingPathComponent("from finder.png")),
            "the handoff didn't produce from finder.png")
        app.terminate()
    }

    /// `More Options…` and the Services menu open the Picker panel; type to
    /// filter, return to convert.
    func testPickerPanelConvertsFromTheKeyboard() throws {
        let folder = try XCTUnwrap(folder)
        let source = try copyFixture(as: "picked.heic")
        var components = URLComponents(string: "morph://pick")
        components?.queryItems = [URLQueryItem(name: "path", value: source.path)]

        let app = makeApp()
        app.launchEnvironment["MORPH_UI_TEST_HANDOFF"] = try XCTUnwrap(components?.url)
            .absoluteString
        app.launch()

        let search = app.textFields["picker-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "the Picker panel didn't open")
        XCTAssertTrue(app.buttons["picker-tiff"].exists, "TIFF should be on offer for a HEIC")
        search.typeText("tif\r")

        XCTAssertTrue(
            waitForFile(folder.appendingPathComponent("picked.tiff")),
            "the picker didn't produce picked.tiff")
        XCTAssertFalse(search.exists, "the panel should close after converting")
        app.terminate()
    }
}
