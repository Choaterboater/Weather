import XCTest

/// Walks the permanent destinations and their key local flows, attaching
/// screenshots so the navigation contract and visual shell can be reviewed.
final class GlassPassUITests: XCTestCase {

    @MainActor
    func testProForecastMatrixAtLargeDynamicType() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiPreview", "proForecast",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let matrix = app.descendants(matching: .any)["proForecast.matrix"]
        XCTAssertTrue(
            matrix.waitForExistence(timeout: 15),
            "Pro Forecast preview did not become reachable"
        )
        let screen = app.windows.firstMatch.frame
        let heading = app.staticTexts["Pro Forecast"]
        let sourceLabel = app.staticTexts["Hourly source data"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3))
        XCTAssertTrue(sourceLabel.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(heading.frame.maxX, screen.maxX)
        XCTAssertLessThanOrEqual(sourceLabel.frame.maxX, screen.maxX)
        XCTAssertTrue(app.buttons["proForecast.horizon.day"].exists)
        XCTAssertFalse(app.buttons["proForecast.horizon.week"].exists)
        XCTAssertFalse(app.staticTexts["Month"].exists)

        let currentHour = app.buttons["proForecast.hour.1800000000"]
        XCTAssertTrue(currentHour.waitForExistence(timeout: 3))
        XCTAssertEqual(currentHour.value as? String, "Now, selected")
        XCTAssertLessThanOrEqual(currentHour.frame.maxX, screen.maxX)
        let nowStatus = app.staticTexts[
            "proForecast.hour.1800000000.status.now"
        ]
        let selectedStatus = app.staticTexts[
            "proForecast.hour.1800000000.status.selected"
        ]
        XCTAssertTrue(nowStatus.waitForExistence(timeout: 3))
        XCTAssertTrue(selectedStatus.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(nowStatus.frame.minX, currentHour.frame.minX)
        XCTAssertLessThanOrEqual(nowStatus.frame.maxX, currentHour.frame.maxX)
        XCTAssertGreaterThanOrEqual(selectedStatus.frame.minX, currentHour.frame.minX)
        XCTAssertLessThanOrEqual(selectedStatus.frame.maxX, currentHour.frame.maxX)

        let nextHour = app.buttons["proForecast.hour.1800003600"]
        XCTAssertTrue(
            nextHour.waitForExistence(timeout: 5),
            "The second forecast hour is not reachable at large Dynamic Type"
        )
        if !nextHour.isHittable {
            matrix.swipeLeft()
        }
        XCTAssertTrue(nextHour.isHittable)
        nextHour.tap()
        XCTAssertEqual(nextHour.value as? String, "Selected")
        let selectedDetail = app.staticTexts["proForecast.selectedDetail"]
        XCTAssertTrue(selectedDetail.waitForExistence(timeout: 3))
        let detailBeforeScroll = selectedDetail.label
        let hourlyColumns = app.scrollViews["proForecast.columns"]
        XCTAssertTrue(hourlyColumns.waitForExistence(timeout: 3))
        hourlyColumns.swipeLeft()
        XCTAssertEqual(
            selectedDetail.label,
            detailBeforeScroll,
            "Scrolling the matrix must not mutate the shared selected hour"
        )

        let fishingGroup = app.buttons["Collapse Fishing group"]
        let weatherGroup = app.buttons["Collapse Weather group"]
        let fishingMenu = app.buttons["Reorder Fishing group"]
        XCTAssertTrue(fishingMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(weatherGroup.exists)
        fishingMenu.tap()
        let moveFishingLater = app.buttons["Move Fishing later"]
        XCTAssertTrue(moveFishingLater.waitForExistence(timeout: 3))
        moveFishingLater.tap()
        XCTAssertGreaterThan(
            fishingGroup.frame.minY,
            weatherGroup.frame.minY,
            "Visible-group reorder should take effect even when provider groups are omitted"
        )

        let fishingToggle = app.buttons["Collapse Fishing group"]
        XCTAssertTrue(fishingToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["proForecast.row.biteScore"].exists
        )
        fishingToggle.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["proForecast.row.biteScore"]
                .waitForNonExistence(timeout: 3)
        )
        let fishingExpand = app.buttons["Expand Fishing group"]
        XCTAssertTrue(fishingExpand.waitForExistence(timeout: 3))
        fishingExpand.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["proForecast.row.biteScore"].waitForExistence(timeout: 3)
        )

        snap(name: "6-pro-forecast-large-type")
    }

    @MainActor
    func testWalkDestinationsAndCentralLogCatch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-selectedTab", "biteTime",
            "-selectedSpecies", "all",
            "-selectedSpotID", "",
            "-spotMapStyle", "standard",
        ]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "Tab bar never appeared — still on the location gate?")
        XCTAssertEqual(
            tabBar.buttons.count,
            4,
            "The tab bar must expose only the four labeled destinations"
        )

        let biteTimeTab = app.buttons["tab.biteTime"]
        XCTAssertTrue(biteTimeTab.waitForExistence(timeout: 5), "BiteTime destination is unreachable")
        XCTAssertTrue(biteTimeTab.isSelected, "BiteTime launch selection was not applied")
        XCTAssertTrue(app.buttons["tab.community"].exists)
        XCTAssertTrue(app.buttons["tab.map"].exists)
        XCTAssertTrue(app.buttons["tab.you"].exists)

        let logCatch = app.buttons["action.logCatch"]
        XCTAssertTrue(logCatch.waitForExistence(timeout: 5), "Central Log Catch action is unreachable")
        logCatch.tap()
        XCTAssertTrue(app.navigationBars["Log Catch"].waitForExistence(timeout: 5))
        snap(name: "1-log-catch")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(logCatch.waitForExistence(timeout: 5), "Log Catch did not dismiss")
        XCTAssertTrue(biteTimeTab.isSelected, "Log Catch changed the selected destination")

        // The action must leave the selected destination and its navigation
        // state alone. Plan the Week remains reachable on BiteTime.
        let planLink = app.staticTexts["Plan the Week"].firstMatch
        XCTAssertTrue(planLink.waitForExistence(timeout: 12), "BiteTime was no longer selected after Log Catch")
        snap(name: "2-bite-time")

        planLink.tap()
        XCTAssertTrue(
            app.navigationBars["Plan the Week"].waitForExistence(timeout: 5),
            "Weekly Trip Planner did not open"
        )
        snap(name: "2b-planner")
        backOut(app)

        openDestination(app, id: "tab.map")
        // The overview map is gated on the device location resolving; wait for
        // it rather than a fixed sleep, then let tiles paint.
        let overviewMap = app.descendants(matching: .any)["Map of nearby spots and ramps"]
        XCTAssertTrue(
            overviewMap.waitForExistence(timeout: 15),
            "Nearby-spots map is unreachable"
        )
        snap(name: "3-map")

        // Flip the overview map to satellite imagery and re-capture.
        let satellite = app.buttons["Satellite"]
        XCTAssertTrue(satellite.waitForExistence(timeout: 3), "Satellite map control is unreachable")
        satellite.tap()
        XCTAssertTrue(satellite.waitForExistence(timeout: 3))
        XCTAssertTrue(satellite.isSelected, "Satellite map style was not selected")
        snap(name: "3b-map-satellite")

        openDestination(app, id: "tab.you")
        XCTAssertTrue(app.navigationBars["You"].waitForExistence(timeout: 5))
        snap(name: "4-you")

        assertPush(app, row: "Catch Log", navigationTitle: "Catch Log")
        assertPush(app, row: "Species Guide", navigationTitle: "Species Guide")
        assertPush(app, row: "Scout the Water", navigationTitle: "Scout the Water")
        assertPush(app, row: "Saved Spots", navigationTitle: "Saved Spots")

        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Settings is unreachable from You")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["You"].waitForExistence(timeout: 5))

        openDestination(app, id: "tab.community")
        XCTAssertTrue(app.navigationBars["Community"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Private by design"].waitForExistence(timeout: 5))
        snap(name: "5-community")
    }

    @MainActor
    private func openDestination(_ app: XCUIApplication, id: String) {
        let destination = app.buttons[id]
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "Could not reach \(id)")
        destination.tap()
    }

    @MainActor
    private func assertPush(
        _ app: XCUIApplication,
        row: String,
        navigationTitle: String
    ) {
        let link = app.buttons[row].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "\(row) is unreachable from You")
        link.tap()
        XCTAssertTrue(app.navigationBars[navigationTitle].waitForExistence(timeout: 5))
        backOut(app)
    }

    @MainActor
    private func backOut(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
    }

    @MainActor
    private func snap(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
