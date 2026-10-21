import XCTest

@MainActor
final class RadioMacUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(theme: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-showWindow",
            "-skip-lastfm-keychain",
            "-theme_preference", theme,
        ] + extra
        app.launch()
        return app
    }

    func testMainSearchAndSettings() {
        let app = launch(theme: "light")
        let search = app.textFields["station-search"]
        if !search.waitForExistence(timeout: 15) {
            print(app.debugDescription)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "ui-failure"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCTAssertTrue(search.exists)
        search.click()
        search.typeText("jazz")
        let jazz = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "jazz"))
            .firstMatch
        XCTAssertTrue(jazz.waitForExistence(timeout: 5))
        jazz.click()
        app.terminate()

        let settingsApp = launch(theme: "light", extra: ["-showSettings"])
        if !settingsApp.staticTexts["Настройки"].waitForExistence(timeout: 15) {
            print(settingsApp.debugDescription)
        }
        XCTAssertTrue(settingsApp.staticTexts["Настройки"].exists)
        settingsApp.terminate()
    }

    func testLightAndDarkSnapshots() {
        var images: [String: Data] = [:]
        for theme in ["light", "dark"] {
            let app = launch(theme: theme)
            XCTAssertTrue(app.textFields["station-search"].waitForExistence(timeout: 15))
            let screenshot = XCUIScreen.main.screenshot()
            images[theme] = screenshot.pngRepresentation
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "main-\(theme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        XCTAssertNotNil(images["light"])
        XCTAssertNotNil(images["dark"])
        XCTAssertNotEqual(images["light"], images["dark"])
    }
}
