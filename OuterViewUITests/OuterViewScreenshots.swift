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
        XCTAssertTrue(bookmarksButton.waitForExistence(timeout: 10))
        bookmarksButton.tap()

        let libraryText = app.staticTexts["Bookmarks"].firstMatch
        XCTAssertTrue(libraryText.waitForExistence(timeout: 10))
        snapshot("03-Library")

        // Compact library rail offers Done without Tabs, so exit before reopening overview.
        let libraryDone = app.buttons["Done"].firstMatch
        XCTAssertTrue(libraryDone.waitForExistence(timeout: 10))
        let hittableLibraryDone = app.buttons.allElementsBoundByIndex.first(where: { $0.label == "Done" && $0.isHittable })
        XCTAssertNotNil(hittableLibraryDone)
        hittableLibraryDone?.tap()

        let tabsAgainButton = app.buttons["Tabs"].firstMatch
        XCTAssertTrue(tabsAgainButton.waitForExistence(timeout: 10))
        tabsAgainButton.tap()

        let overviewGridAgain = app.collectionViews["TabOverview.Grid"].firstMatch
        XCTAssertTrue(overviewGridAgain.waitForExistence(timeout: 10))
        snapshot("04-TabOverview")

        // Inline commands appear only on regular; Done chrome exists in both.
        let isRegularPlacement = app.launchArguments.contains("-OuterViewInnerDisplay") || app.windows.firstMatch.frame.width > 500
        if isRegularPlacement {
            let overviewToolbar = app.toolbars["TabOverview.Toolbar"].firstMatch
            XCTAssertTrue(overviewToolbar.waitForExistence(timeout: 10))
            let inlineDone = app.buttons["Done"].firstMatch
            XCTAssertTrue(inlineDone.waitForExistence(timeout: 10))
            let inlineSearch = app.buttons["Search"].firstMatch
            XCTAssertTrue(inlineSearch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["New Tab"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Overview Menu"].firstMatch.waitForExistence(timeout: 10))
            let inlineHittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: inlineDone)
            XCTAssertTrue(XCTWaiter.wait(for: [inlineHittable], timeout: 10) == .completed)
            inlineDone.tap()
        } else {
            XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 10))
            // Inline overview chrome is regular-only; it must never appear on compact.
            XCTAssertFalse(app.toolbars["TabOverview.Toolbar"].firstMatch.isHittable)
            let overviewDone = app.buttons.allElementsBoundByIndex.first(where: { $0.label == "Done" && $0.isHittable })
            XCTAssertNotNil(overviewDone)
            overviewDone?.tap()
        }

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
