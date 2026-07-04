import XCTest

/// Walks every tab (and the two detail screens with standalone glass buttons)
/// attaching a screenshot of each, so a reviewer can eyeball the Liquid Glass
/// rendering without driving the simulator by hand.
final class GlassPassUITests: XCTestCase {

    @MainActor
    func testWalkTabsAndDetailScreens() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "Tab bar never appeared — still on the location gate?")

        // Let the first weather fetch settle so cards render.
        Thread.sleep(forTimeInterval: 6)
        snap(name: "1-weather")

        openTab(app, "Fishing")
        Thread.sleep(forTimeInterval: 3)
        snap(name: "2-fishing")

        // Open the Weekly Trip Planner and capture whatever state it reaches
        // (loading/outlook on device; error on the simulator where WeatherKit
        // is unavailable). Confirms the link and navigation are wired.
        let planLink = app.buttons["Plan the Week"]
        if planLink.waitForExistence(timeout: 3) {
            planLink.tap()
            Thread.sleep(forTimeInterval: 4)
            snap(name: "2b-planner")
            backOut(app)
        }

        openTab(app, "Spots")
        // The overview map is gated on the device location resolving; wait for
        // it rather than a fixed sleep, then let tiles paint.
        let overviewMap = app.descendants(matching: .any)["Map of nearby spots and ramps"]
        _ = overviewMap.waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 4)
        snap(name: "3-spots")

        // Flip the overview map to satellite imagery and re-capture.
        let satellite = app.buttons["Satellite"]
        if satellite.waitForExistence(timeout: 3) {
            satellite.tap()
            Thread.sleep(forTimeInterval: 4)   // imagery tiles stream in
            snap(name: "3b-spots-satellite")
        }

        openTab(app, "Guide")
        Thread.sleep(forTimeInterval: 2)
        snap(name: "4-guide")

        // Drill into a species card by name; only back out if the detail
        // screen actually appeared (a blind "first button" tap can hit a
        // filter chip or toolbar button instead).
        let bassCard = app.scrollViews.staticTexts["Bass"].firstMatch
        if bassCard.waitForExistence(timeout: 3) {
            bassCard.tap()
            let detailMarker = app.buttons["Set as Fishing tab focus"]
            if detailMarker.waitForExistence(timeout: 5) {
                Thread.sleep(forTimeInterval: 2)
                snap(name: "4b-species-detail")
                backOut(app)
            }
        }

        openTab(app, "Log")
        Thread.sleep(forTimeInterval: 1)
        snap(name: "5-log")

        openTab(app, "Scout")
        Thread.sleep(forTimeInterval: 1)
        snap(name: "6-scout")
    }

    /// Taps a tab by name, falling through to the More list when the tab bar
    /// has overflowed.
    @MainActor
    private func openTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.exists {
            tab.tap()
            return
        }
        let more = app.tabBars.buttons["More"]
        if more.exists {
            more.tap()
            let row = app.tables.staticTexts[name].firstMatch
            if row.waitForExistence(timeout: 3) {
                row.tap()
                return
            }
        }
        XCTFail("Could not reach tab \(name)")
    }

    @MainActor
    private func backOut(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        Thread.sleep(forTimeInterval: 1)
    }

    @MainActor
    private func snap(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
