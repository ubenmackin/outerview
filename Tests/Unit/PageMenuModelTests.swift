// ChromeTests — Page-menu ordering plus desktop/accessibility contract tests.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class PageMenuModelTests: XCTestCase {
    private func makeRoot() throws -> BrowserRootViewController {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        TestWindow.attach(root)
        return root
    }

    private func pageURL() throws -> URL {
        try XCTUnwrap(URL(string: "https://example.com/article"))
    }

    private func flattenedTitles(_ menu: UIMenu) -> [String] {
        var titles: [String] = []
        for child in menu.children {
            if let action = child as? UIAction {
                titles.append(action.title)
            } else if let submenu = child as? UIMenu {
                if !submenu.title.isEmpty {
                    titles.append(submenu.title)
                }
                titles.append(contentsOf: flattenedTitles(submenu))
            }
        }
        return titles
    }

    private func allActions(_ menu: UIMenu) -> [UIAction] {
        var actions: [UIAction] = []
        for child in menu.children {
            if let action = child as? UIAction {
                actions.append(action)
            } else if let submenu = child as? UIMenu {
                actions.append(contentsOf: allActions(submenu))
            }
        }
        return actions
    }

    private func submenu(named name: String, in menu: UIMenu) -> UIMenu? {
        for child in menu.children {
            if let childMenu = child as? UIMenu {
                if childMenu.title == name {
                    return childMenu
                }
                if let nested = submenu(named: name, in: childMenu) {
                    return nested
                }
            }
        }
        return nil
    }

    func testNewFieldsDefault() {
        let model = PageMenuModel(url: nil)
        XCTAssertFalse(model.canAddToReadingList)
        XCTAssertFalse(model.isInReadingList)
        XCTAssertFalse(model.isReaderActive)
        XCTAssertFalse(model.isReaderAvailable)
        XCTAssertEqual(model.textZoom, 1.0, accuracy: 0.001)
        XCTAssertFalse(model.canOpenDownloads)
        XCTAssertFalse(model.isDesktopMode)
        XCTAssertFalse(model.canToggleDesktopMode)
    }

    func testConstructionWithNewFields() throws {
        let model = try PageMenuModel(
            url: pageURL(),
            canAddToReadingList: true,
            isInReadingList: true,
            isReaderActive: true,
            isReaderAvailable: true,
            textZoom: 1.5,
            canOpenDownloads: true,
            isDesktopMode: true,
            canToggleDesktopMode: true
        )
        XCTAssertTrue(model.canAddToReadingList)
        XCTAssertTrue(model.isInReadingList)
        XCTAssertTrue(model.isReaderActive)
        XCTAssertTrue(model.isReaderAvailable)
        XCTAssertEqual(model.textZoom, 1.5, accuracy: 0.001)
        XCTAssertTrue(model.canOpenDownloads)
        XCTAssertTrue(model.isDesktopMode)
        XCTAssertTrue(model.canToggleDesktopMode)
    }

    func testReadingListLabelFlip() {
        XCTAssertEqual(PageMenuModel(url: nil).readingListTitle, "Add to Reading List")
        XCTAssertEqual(
            PageMenuModel(url: nil, isInReadingList: true).readingListTitle,
            "Remove from Reading List"
        )
    }

    func testDesktopModeLabelFlip() {
        XCTAssertEqual(PageMenuModel(url: nil).desktopModeTitle, "Request Desktop Website")
        XCTAssertEqual(
            PageMenuModel(url: nil, isDesktopMode: true).desktopModeTitle,
            "Request Mobile Website"
        )
    }

    func testReaderLabelFlipAndVisibility() {
        let hidden = PageMenuModel(url: nil)
        XCTAssertFalse(hidden.showsReaderItem)
        let shown = PageMenuModel(url: nil, isReaderAvailable: true)
        XCTAssertTrue(shown.showsReaderItem)
        XCTAssertEqual(shown.readerTitle, "Show Reader")
        let active = PageMenuModel(url: nil, isReaderActive: true, isReaderAvailable: true)
        XCTAssertEqual(active.readerTitle, "Hide Reader")
    }

    func testMenuOrderingWithReaderAvailable() throws {
        let root = try makeRoot()
        let model = try PageMenuModel(
            url: pageURL(),
            canGoBack: true,
            canGoForward: false,
            isFavorite: false,
            canAddToReadingList: true,
            isInReadingList: false,
            isReaderActive: false,
            isReaderAvailable: true,
            textZoom: 1.0,
            canOpenDownloads: true
        )
        let titles = flattenedTitles(root.makePageMenu(model: model))
        XCTAssertEqual(titles, [
            "Back", "Forward", "Reload", "Share",
            "Add Bookmark", "Add to Favorites", "Add to Reading List", "Show Reader",
            "Find on Page", "Text Zoom", "Zoom In", "Zoom Out", "Reset", "Request Desktop Website", "Print", "Save as PDF", "Downloads",
            "Open Start Page", "Settings…"
        ])
    }

    func testMenuOrderingReaderHiddenWhenUnavailable() throws {
        let root = try makeRoot()
        let model = try PageMenuModel(
            url: pageURL(),
            canAddToReadingList: true,
            isInReadingList: false,
            isReaderAvailable: false,
            canOpenDownloads: true
        )
        let titles = flattenedTitles(root.makePageMenu(model: model))
        XCTAssertFalse(titles.contains("Show Reader"))
        XCTAssertFalse(titles.contains("Hide Reader"))
        XCTAssertEqual(titles, [
            "Back", "Forward", "Reload", "Share",
            "Add Bookmark", "Add to Favorites", "Add to Reading List",
            "Find on Page", "Text Zoom", "Zoom In", "Zoom Out", "Reset", "Request Desktop Website", "Print", "Save as PDF", "Downloads",
            "Open Start Page", "Settings…"
        ])
    }

    func testMenuOrderingLabelFlips() throws {
        let root = try makeRoot()
        let model = try PageMenuModel(
            url: pageURL(),
            isFavorite: true,
            canAddToReadingList: true,
            isInReadingList: true,
            isReaderActive: true,
            isReaderAvailable: true,
            canOpenDownloads: true,
            isDesktopMode: true
        )
        let titles = flattenedTitles(root.makePageMenu(model: model))
        XCTAssertTrue(titles.contains("Remove from Favorites"))
        XCTAssertTrue(titles.contains("Remove from Reading List"))
        XCTAssertTrue(titles.contains("Hide Reader"))
        XCTAssertTrue(titles.contains("Request Mobile Website"))
        XCTAssertFalse(titles.contains("Add to Favorites"))
        XCTAssertFalse(titles.contains("Add to Reading List"))
        XCTAssertFalse(titles.contains("Show Reader"))
        XCTAssertFalse(titles.contains("Request Desktop Website"))
    }

    func testZoomDisabledWithoutPage() throws {
        let root = try makeRoot()
        let emptyMenu = root.makePageMenu(model: PageMenuModel(url: nil))
        let emptyZoom = try XCTUnwrap(submenu(named: "Text Zoom", in: emptyMenu))
        for child in emptyZoom.children {
            let action = try XCTUnwrap(child as? UIAction)
            XCTAssertTrue(action.attributes.contains(.disabled), action.title)
        }
        let pageMenu = try root.makePageMenu(model: PageMenuModel(url: pageURL()))
        let pageZoom = try XCTUnwrap(submenu(named: "Text Zoom", in: pageMenu))
        for child in pageZoom.children {
            let action = try XCTUnwrap(child as? UIAction)
            XCTAssertFalse(action.attributes.contains(.disabled), action.title)
        }
    }

    func testAccessibilityLabelsOnNewControls() throws {
        let root = try makeRoot()
        let model = try PageMenuModel(
            url: pageURL(),
            canAddToReadingList: true,
            isInReadingList: false,
            isReaderAvailable: true,
            canOpenDownloads: true
        )
        let menu = root.makePageMenu(model: model)
        let actions = Dictionary(
            uniqueKeysWithValues: allActions(menu).map { ($0.title, $0) }
        )
        for title in ["Add to Reading List", "Show Reader", "Zoom In", "Zoom Out", "Reset", "Request Desktop Website", "Print", "Downloads"] {
            let action = try XCTUnwrap(actions[title], title)
            XCTAssertFalse(action.accessibilityLabel?.isEmpty ?? true, title)
        }
        let zoomMenu = try XCTUnwrap(submenu(named: "Text Zoom", in: menu))
        XCTAssertFalse(zoomMenu.accessibilityLabel?.isEmpty ?? true)
    }

    func testPrintActionEnabledWithLoadablePage() throws {
        let root = try makeRoot()
        let menuWithPage = try root.makePageMenu(model: PageMenuModel(url: pageURL()))
        let actionsWithPage = Dictionary(uniqueKeysWithValues: allActions(menuWithPage).map { ($0.title, $0) })
        let printWithPage = try XCTUnwrap(actionsWithPage["Print"])
        XCTAssertFalse(printWithPage.attributes.contains(.disabled))

        let menuWithoutPage = root.makePageMenu(model: PageMenuModel(url: nil))
        let actionsWithoutPage = Dictionary(uniqueKeysWithValues: allActions(menuWithoutPage).map { ($0.title, $0) })
        let printWithoutPage = try XCTUnwrap(actionsWithoutPage["Print"])
        XCTAssertTrue(printWithoutPage.attributes.contains(.disabled))
    }
}
