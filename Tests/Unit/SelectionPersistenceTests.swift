//
//  SelectionPersistenceTests.swift
//  OuterViewTests
//

@testable import OuterView
import UIKit
import XCTest

/// UserDefaults keys libraryTab as Int, overviewMode as String, and overviewGroup as String.
/// Values are read at init and setup and written on every change; private mode is never
/// written and restores as standard. Unparseable values fall back to bookmarks, standard,
/// and nil; a stored group id resolving to no existing group restores as nil.
@MainActor
final class SelectionPersistenceTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let name = "SelectionPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { [name] in
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        return defaults
    }

    private func makeRoot(defaults: UserDefaults) throws -> BrowserRootViewController {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database, defaults: defaults)
        TestWindow.attach(root)
        return root
    }

    func testLibraryTabDefaultsToBookmarks() throws {
        let defaults = try makeDefaults()
        XCTAssertEqual(LibraryTabBar.storedTab(defaults: defaults), .bookmarks)
        XCTAssertEqual(LibraryTabBar(defaults: defaults).selectedTab, .bookmarks)
        XCTAssertEqual(BookmarksLibraryView(defaults: defaults).currentTab, .bookmarks)
    }

    func testLibraryTabRoundTrip() throws {
        let defaults = try makeDefaults()
        let bar = LibraryTabBar(defaults: defaults)
        TestWindow.attach(bar)
        bar.selectTab(.history)
        XCTAssertEqual(defaults.integer(forKey: LibraryTabBar.libraryTabDefaultsKey), LibraryTab.history.rawValue)
        XCTAssertEqual(LibraryTabBar.storedTab(defaults: defaults), .history)
        XCTAssertEqual(LibraryTabBar(defaults: defaults).selectedTab, .history)

        let library = BookmarksLibraryView(defaults: defaults)
        library.open(tab: .readingList)
        XCTAssertEqual(BookmarksLibraryView.storedTab(defaults: defaults), .readingList)
        XCTAssertEqual(BookmarksLibraryView(defaults: defaults).currentTab, .readingList)
        XCTAssertEqual(library.currentTab, .readingList)
    }

    func testLibraryTabCorruptFallback() throws {
        let defaults = try makeDefaults()
        defaults.set("bogus-value", forKey: LibraryTabBar.libraryTabDefaultsKey)
        XCTAssertEqual(LibraryTabBar.storedTab(defaults: defaults), .bookmarks)
        XCTAssertEqual(LibraryTabBar(defaults: defaults).selectedTab, .bookmarks)
        defaults.set(99, forKey: LibraryTabBar.libraryTabDefaultsKey)
        XCTAssertEqual(LibraryTabBar.storedTab(defaults: defaults), .bookmarks)
    }

    func testOverviewModeRoundTrip() throws {
        let defaults = try makeDefaults()
        XCTAssertEqual(TabOverviewViewController.storedOverviewMode(defaults: defaults), .standard)
        TabOverviewViewController.persistOverviewSelection(mode: .standard, groupID: nil, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: TabOverviewViewController.overviewModeDefaultsKey), "standard")
        XCTAssertEqual(TabOverviewViewController.storedOverviewMode(defaults: defaults), .standard)

        let root = try makeRoot(defaults: defaults)
        XCTAssertEqual(root.overviewMode, .standard)
        root.setOverviewMode(.standard)
        XCTAssertEqual(defaults.string(forKey: TabOverviewViewController.overviewModeDefaultsKey), "standard")
        XCTAssertEqual(TabOverviewViewController.storedOverviewMode(defaults: defaults), .standard)
    }

    func testOverviewGroupRoundTrip() throws {
        let defaults = try makeDefaults()
        XCTAssertNil(TabOverviewViewController.storedOverviewGroupID(defaults: defaults))
        let group = UUID()
        TabOverviewViewController.persistOverviewSelection(mode: .standard, groupID: group, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: TabOverviewViewController.overviewGroupDefaultsKey), group.uuidString)
        XCTAssertEqual(TabOverviewViewController.storedOverviewGroupID(defaults: defaults), group)

        let overview = TabOverviewViewController()
        overview.selectionDefaults = defaults
        TestWindow.attach(overview)
        let tabGroup = TabGroup(name: "Work")
        let fixedID = tabGroup.id
        TabOverviewViewController.persistOverviewSelection(mode: .standard, groupID: fixedID, defaults: defaults)
        overview.setGroups([tabGroup], selectedGroupID: nil)
        overview.applySelectionBatched(mode: .standard, groupID: fixedID, notify: false)
        XCTAssertEqual(defaults.string(forKey: TabOverviewViewController.overviewGroupDefaultsKey), fixedID.uuidString)
        XCTAssertEqual(TabOverviewViewController.storedOverviewGroupID(defaults: defaults), fixedID)
    }

    func testPrivateExclusion() throws {
        let defaults = try makeDefaults()
        TabOverviewViewController.persistOverviewSelection(mode: .standard, groupID: nil, defaults: defaults)
        TabOverviewViewController.persistOverviewSelection(mode: .privateMode, groupID: nil, defaults: defaults)
        XCTAssertEqual(TabOverviewViewController.storedOverviewMode(defaults: defaults), .standard)
        XCTAssertNil(TabOverviewViewController.storedOverviewGroupID(defaults: defaults))
        XCTAssertNotEqual(defaults.string(forKey: TabOverviewViewController.overviewModeDefaultsKey), "private")

        let root = try makeRoot(defaults: defaults)
        root.setOverviewMode(.standard)
        root.setOverviewMode(.privateMode)
        XCTAssertEqual(root.overviewMode, .privateMode)
        XCTAssertEqual(TabOverviewViewController.storedOverviewMode(defaults: defaults), .standard)
        XCTAssertNil(TabOverviewViewController.storedOverviewGroupID(defaults: defaults))

        let overview = TabOverviewViewController()
        overview.selectionDefaults = defaults
        TestWindow.attach(overview)
        overview.applySelectionBatched(mode: .privateMode, groupID: nil, notify: false)
        XCTAssertEqual(TabOverviewViewController.storedOverviewMode(defaults: defaults), .standard)
    }

    func testStaleGroupRestoresNil() throws {
        let defaults = try makeDefaults()
        let stale = UUID()
        defaults.set(stale.uuidString, forKey: TabOverviewViewController.overviewGroupDefaultsKey)
        XCTAssertEqual(TabOverviewViewController.storedOverviewGroupID(defaults: defaults), stale)

        let overview = TabOverviewViewController()
        overview.selectionDefaults = defaults
        TestWindow.attach(overview)
        overview.configure(tabs: [], selectedID: nil, mode: .standard, groups: [], selectedGroupID: stale)
        XCTAssertNil(overview.selectedGroupID)

        let root = try makeRoot(defaults: defaults)
        root.setOverviewVisible(true)
        XCTAssertNil(root.overviewController.selectedGroupID)
        root.setOverviewVisible(false)
    }

    func testCorruptOverviewFallbacks() throws {
        let defaults = try makeDefaults()
        defaults.set("bogus-value", forKey: TabOverviewViewController.overviewModeDefaultsKey)
        XCTAssertEqual(TabOverviewViewController.storedOverviewMode(defaults: defaults), .standard)
        defaults.set("not-a-uuid", forKey: TabOverviewViewController.overviewGroupDefaultsKey)
        XCTAssertNil(TabOverviewViewController.storedOverviewGroupID(defaults: defaults))

        defaults.set("private", forKey: TabOverviewViewController.overviewModeDefaultsKey)
        XCTAssertEqual(TabOverviewViewController.storedOverviewMode(defaults: defaults), .standard)
    }

    func testOpenBookmarksLibraryNilResolvesToStored() throws {
        let defaults = try makeDefaults()
        let root = try makeRoot(defaults: defaults)
        root.openBookmarksLibrary()
        XCTAssertEqual(root.bookmarksLibraryView.currentTab, .bookmarks)

        LibraryTabBar.persist(tab: .history, defaults: defaults)
        root.openBookmarksLibrary()
        XCTAssertEqual(root.bookmarksLibraryView.currentTab, .history)

        root.openBookmarksLibrary(tab: .startPage)
        XCTAssertEqual(root.bookmarksLibraryView.currentTab, .startPage)
        XCTAssertEqual(LibraryTabBar.storedTab(defaults: defaults), .startPage)
    }
}
