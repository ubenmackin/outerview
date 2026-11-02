// UITests — Store listing capture driving the seeded browser.
import XCTest

/// Drives the seeded browser through portrait captures, adding landscape on regular.
final class OuterViewScreenshots: XCTestCase {
    // XCTest declares this as class var, so override keeps dispatch correct.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
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

        let fixtureText = app.staticTexts["OuterView Fixture"].firstMatch
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
        let inlineDone = app.buttons["TabOverview.InlineDone"].firstMatch
        XCTAssertTrue(inlineDone.waitForExistence(timeout: 10))
        // Existence precedes settled layout, so await hittability before classifying placement.
        let inlineHittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: inlineDone)
        let isRegularPlacement = XCTWaiter.wait(for: [inlineHittable], timeout: 10) == .completed
        let inlineSearch = app.textFields["TabOverview.InlineSearchField"].firstMatch
        XCTAssertTrue(inlineSearch.waitForExistence(timeout: 10))
        if isRegularPlacement {
            let searchHittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: inlineSearch)
            XCTAssertTrue(XCTWaiter.wait(for: [searchHittable], timeout: 10) == .completed)
        } else {
            XCTAssertFalse(inlineSearch.isHittable)
        }
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 10))
        if isRegularPlacement {
            XCTAssertTrue(inlineDone.isHittable)
            inlineDone.tap()
        } else {
            XCTAssertFalse(inlineDone.isHittable)
            let overviewDone = app.buttons.allElementsBoundByIndex.first(where: { $0.label == "Done" && $0.isHittable })
            XCTAssertNotNil(overviewDone)
            overviewDone?.tap()
        }

        let browsingSettled = app.staticTexts["OuterView Fixture"].firstMatch
        XCTAssertTrue(browsingSettled.waitForExistence(timeout: 10))
        if isRegularPlacement {
            XCUIDevice.shared.orientation = .landscapeLeft
            let landscapeSettled = app.staticTexts["OuterView Fixture"].firstMatch
            XCTAssertTrue(landscapeSettled.waitForExistence(timeout: 10))
            snapshot("05-Browsing-Landscape")
            XCUIDevice.shared.orientation = .portrait
            let portraitSettled = app.staticTexts["OuterView Fixture"].firstMatch
            XCTAssertTrue(portraitSettled.waitForExistence(timeout: 10))
        }
    }
}
