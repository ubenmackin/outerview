// UITests — Store listing capture driving the seeded browser.
import XCTest

/// Drives the seeded browser through portrait captures, adding landscape on regular.
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

        let startPageText = app.staticTexts["Favorites"]
        XCTAssertTrue(startPageText.waitForExistence(timeout: 10))
        snapshot("01-StartPage")

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
        snapshot("02-Browsing")

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
        snapshot("03-Library")

        // Library rail offers Done (on Duo) or Dismiss (on iPhone non-Duo phone).
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
        snapshot("04-TabOverview")

        // Overview chrome provides Search, New Tab, Menu, and Done across all form factors.
        let overviewDone = app.buttons.matching(NSPredicate(format: "label == 'Done'")).firstMatch
        XCTAssertTrue(overviewDone.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Search"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["New Tab"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Overview Menu"].firstMatch.waitForExistence(timeout: 10))
        let hittableOverviewDone = app.buttons.allElementsBoundByIndex.first(where: { $0.label == "Done" && $0.isHittable })
        XCTAssertNotNil(hittableOverviewDone)
        hittableOverviewDone?.tap()

        let isRegularPlacement = app.launchArguments.contains("-OuterViewInnerDisplay") || app.windows.firstMatch.frame.width > 500

        let browsingSettled = app.staticTexts["Swift (programming language)"].firstMatch
        XCTAssertTrue(browsingSettled.waitForExistence(timeout: 10))
        if isRegularPlacement {
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
