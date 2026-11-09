// UITests — Store listing capture driving the seeded browser.
import XCTest

/// Drives the seeded browser through portrait and landscape captures across form factors.
final class OuterViewScreenshots: XCTestCase {
    override static var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    @MainActor
    func testScreenshots() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-OuterViewScreenshots"]
        setupSnapshot(app)
        app.launch()

        let isMode4 = app.launchArguments.contains(where: { $0.contains("-OuterViewInnerPortrait") }) ||
            ProcessInfo.processInfo.arguments.contains(where: { $0.contains("-OuterViewInnerPortrait") })
        let isLandscape = app.launchArguments.contains(where: { $0.contains("-landscape") }) ||
            ProcessInfo.processInfo.arguments.contains(where: { $0.contains("-landscape") })

        if isLandscape {
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(1)
        } else {
            XCUIDevice.shared.orientation = .portrait
            sleep(1)
        }

        let startPageText = app.staticTexts["Favorites"]
        XCTAssertTrue(startPageText.waitForExistence(timeout: 10))
        snapshot(isMode4 ? "Mode4-01-StartPage" : "01-StartPage")

        let tabsButton = app.buttons["Tabs"].firstMatch
        XCTAssertTrue(tabsButton.waitForExistence(timeout: 10))
        tabsButton.tap()

        let overviewGrid = app.collectionViews["TabOverview.Grid"].firstMatch
        XCTAssertTrue(overviewGrid.waitForExistence(timeout: 10))
        // Seed tabs are Start Page then fixture; order selects the fixture.
        let fixtureCell = overviewGrid.cells.element(boundBy: 1)
        XCTAssertTrue(fixtureCell.waitForExistence(timeout: 10))
        fixtureCell.tap()

        let fixtureText = app.staticTexts["Swift (programming language)"].firstMatch
        XCTAssertTrue(fixtureText.waitForExistence(timeout: 10))
        snapshot(isMode4 ? "Mode4-02-Browsing" : "02-Browsing")

        let bookmarksButton = app.buttons["Bookmarks"].firstMatch
        if bookmarksButton.waitForExistence(timeout: 1) {
            bookmarksButton.tap()
        } else {
            // Mode 3 (iPhone non-Duo phone) opens Library via the address pill
            let addressPill = app.buttons["AddressBar.DomainContainer"].firstMatch
            if addressPill.waitForExistence(timeout: 5) {
                addressPill.tap()
            } else {
                app.otherElements["AddressBar.Pill"].tap()
            }
            let bookmarksTab = app.buttons.matching(
                NSPredicate(format: "identifier == 'LibraryTab.Bookmarks' OR label == 'Bookmarks'")
            ).firstMatch
            XCTAssertTrue(bookmarksTab.waitForExistence(timeout: 10))
            bookmarksTab.tap()
        }

        let libraryText = app.staticTexts["Bookmarks"].firstMatch
        XCTAssertTrue(libraryText.waitForExistence(timeout: 10))
        snapshot(isMode4 ? "Mode4-03-Library" : "03-Library")

        // Library rail offers Done (on Duo) or Dismiss (on iPhone non-Duo phone and Mode 4).
        let doneOrDismiss = app.buttons.matching(NSPredicate(format: "label == 'Done' OR label == 'Dismiss'")).firstMatch
        XCTAssertTrue(doneOrDismiss.waitForExistence(timeout: 10))
        let hittableLibraryExit = app.buttons.allElementsBoundByIndex.first(where: {
            ($0.label == "Done" || $0.label == "Dismiss") && $0.isHittable
        })
        XCTAssertNotNil(hittableLibraryExit)
        hittableLibraryExit?.tap()

        let tabsAgainButton = app.buttons["Tabs"].firstMatch
        XCTAssertTrue(tabsAgainButton.waitForExistence(timeout: 10))
        tabsAgainButton.tap()

        let overviewGridAgain = app.collectionViews["TabOverview.Grid"].firstMatch
        XCTAssertTrue(overviewGridAgain.waitForExistence(timeout: 10))
        snapshot(isMode4 ? "Mode4-04-TabOverview" : "04-TabOverview")

        // Overview chrome provides Search, New Tab, Menu, and Done across all form factors.
        let overviewDone = app.buttons.matching(NSPredicate(format: "label == 'Done'")).firstMatch
        XCTAssertTrue(overviewDone.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Search"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["New Tab"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Overview Menu"].firstMatch.waitForExistence(timeout: 10))
        let hittableOverviewDone = app.buttons.allElementsBoundByIndex.first(where: { $0.label == "Done" && $0.isHittable })
        XCTAssertNotNil(hittableOverviewDone)
        hittableOverviewDone?.tap()

        let isRegularPlacement = (app.launchArguments.contains(where: { $0.contains("-OuterViewInnerDisplay") }) || app.windows.firstMatch.frame.width > 500) && !isMode4

        let browsingSettled = app.staticTexts["Swift (programming language)"].firstMatch
        XCTAssertTrue(browsingSettled.waitForExistence(timeout: 10))
        if isRegularPlacement, !isLandscape {
            XCUIDevice.shared.orientation = .landscapeLeft
            let landscapeSettled = app.staticTexts["Swift (programming language)"].firstMatch
            XCTAssertTrue(landscapeSettled.waitForExistence(timeout: 10))
            snapshot("05-Browsing-Landscape")
            XCUIDevice.shared.orientation = .portrait
            let portraitSettled = app.staticTexts["Swift (programming language)"].firstMatch
            XCTAssertTrue(portraitSettled.waitForExistence(timeout: 10))
        }
    }
}
