import XCTest

final class LegalCenterUITests: XCTestCase {
    @MainActor
    func testLegalDocumentsAreReachableFromYouAndSettingsAtAccessibilityXXXL() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-selectedTab", "you",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let youLink = app.buttons["you.legalSupport"]
        reveal(youLink, in: app)
        XCTAssertTrue(youLink.waitForExistence(timeout: 15))
        XCTAssertTrue(youLink.isHittable)
        youLink.tap()

        XCTAssertTrue(app.navigationBars["Legal & Support"].waitForExistence(timeout: 5))
        let documents = [
            ("legal.document.privacy", "Privacy", "BiteCast Privacy Notice"),
            ("legal.document.terms", "Terms of Use", "BiteCast Terms of Use"),
            ("legal.document.support", "Support", "BiteCast Support"),
            (
                "legal.document.thirdParty",
                "Third-Party Notices",
                "BiteCast Third-Party Notices"
            ),
        ]
        for (identifier, _, _) in documents {
            let document = app.buttons[identifier]
            reveal(document, in: app)
            XCTAssertTrue(document.exists, "Missing \(identifier)")
            XCTAssertLessThanOrEqual(document.frame.maxX, app.windows.firstMatch.frame.maxX)
        }
        attachScreenshot(named: "task-12e-legal-center-axxxl")

        for (identifier, navigationTitle, bodyTitle) in documents {
            let document = app.buttons[identifier]
            reveal(document, in: app)
            XCTAssertTrue(document.isHittable, "Could not reach \(identifier)")
            document.tap()
            XCTAssertTrue(
                app.navigationBars[navigationTitle].waitForExistence(timeout: 5),
                "Missing navigation title for \(identifier)"
            )
            XCTAssertTrue(
                app.staticTexts[bodyTitle].waitForExistence(timeout: 5),
                "Missing bundled body for \(identifier)"
            )
            if identifier == "legal.document.privacy" {
                attachScreenshot(named: "task-12e-privacy-axxxl")
            }
            backOut(app)
            XCTAssertTrue(app.navigationBars["Legal & Support"].waitForExistence(timeout: 5))
        }

        backOut(app)
        XCTAssertTrue(app.navigationBars["You"].waitForExistence(timeout: 5))

        let settings = app.buttons["Settings"].firstMatch
        reveal(settings, in: app)
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let settingsLink = app.buttons["settings.legalSupport"]
        reveal(settingsLink, in: app)
        XCTAssertTrue(settingsLink.isHittable)
        settingsLink.tap()
        XCTAssertTrue(app.navigationBars["Legal & Support"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 {
            if element.exists, element.isHittable {
                return
            }
            app.swipeUp()
        }
        for _ in 0..<14 {
            if element.exists, element.isHittable {
                return
            }
            app.swipeDown()
        }
    }

    @MainActor
    private func backOut(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
