//
//  SettingsSheetTests.swift
//  OuterViewTests
//

@testable import OuterView
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SettingsSheetTests: XCTestCase {
    private func makeRoot() throws -> BrowserRootViewController {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        TestWindow.attach(root)
        return root
    }

    private func doneButton(in rail: SideRailView) -> UIButton? {
        let stacks = rail.subviews.compactMap { $0 as? UIStackView }
        for stack in stacks {
            for button in stack.arrangedSubviews.compactMap({ $0 as? UIButton }) where button.accessibilityLabel == "Done" {
                return button
            }
        }
        return nil
    }

    func testPresentSetsFlagShowsContainerAndRailMode() throws {
        let root = try makeRoot()
        XCTAssertFalse(root.isSettingsVisible)
        XCTAssertTrue(root.settingsContainer.isHidden)

        root.presentSettingsSheet()

        XCTAssertTrue(root.isSettingsVisible)
        XCTAssertFalse(root.settingsContainer.isHidden)
        XCTAssertNotNil(root.settingsHosting)
        XCTAssertEqual(root.currentRailMode, .settings)
    }

    func testDismissClearsFlagHidesContainerAndRestoresRailMode() throws {
        let root = try makeRoot()
        root.presentSettingsSheet()
        XCTAssertEqual(root.currentRailMode, .settings)

        root.dismissSettingsSheet()

        XCTAssertFalse(root.isSettingsVisible)
        XCTAssertTrue(root.settingsContainer.isHidden)
        XCTAssertNil(root.settingsHosting)
        XCTAssertEqual(root.currentRailMode, .browsing)
    }

    func testRailModePrefersSettingsOverLibraryAndStartPage() throws {
        let root = try makeRoot()
        root.openBookmarksLibrary(tab: .bookmarks)
        XCTAssertEqual(root.currentRailMode, .library(.bookmarks))

        root.presentSettingsSheet()
        XCTAssertEqual(root.currentRailMode, .settings)

        root.dismissSettingsSheet()
        XCTAssertEqual(root.currentRailMode, .library(.bookmarks))

        root.closeBookmarksLibrary()
        root.isEditingAddress = true
        XCTAssertEqual(root.currentRailMode, .startPage)

        root.presentSettingsSheet()
        XCTAssertEqual(root.currentRailMode, .settings)

        root.dismissSettingsSheet()
        XCTAssertEqual(root.currentRailMode, .startPage)
        root.isEditingAddress = false
        root.updateRailItems()
    }

    func testBookmarkEditorPrecedesSettings() throws {
        let root = try makeRoot()
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        root.presentSettingsSheet()
        XCTAssertEqual(root.currentRailMode, .settings)

        root.presentBookmarkEditor(for: .addBookmark(title: "Example", url: url))
        XCTAssertEqual(root.currentRailMode, .bookmarkEditor)

        root.dismissBookmarkEditor()
        XCTAssertEqual(root.currentRailMode, .settings)

        root.dismissSettingsSheet()
        XCTAssertEqual(root.currentRailMode, .browsing)
    }

    func testDoneButtonDismissesSheet() throws {
        let root = try makeRoot()
        root.presentSettingsSheet()
        root.updateRailItems()

        let done = try XCTUnwrap(doneButton(in: root.railView))
        done.sendActions(for: .touchUpInside)

        XCTAssertFalse(root.isSettingsVisible)
        XCTAssertTrue(root.settingsContainer.isHidden)
        XCTAssertNil(root.settingsHosting)
    }

    func testHostingCleanupRemovesView() throws {
        let root = try makeRoot()
        root.presentSettingsSheet()
        let hosting = try XCTUnwrap(root.settingsHosting)
        let hostedView: UIView = hosting.view
        XCTAssertTrue(hostedView.superview === root.settingsContainer)

        root.dismissSettingsSheet()

        XCTAssertNil(root.settingsHosting)
        XCTAssertNil(hostedView.superview)
        XCTAssertNil(hosting.parent)
        XCTAssertTrue(root.settingsContainer.isHidden)
    }

    func testPresentSettingsDoesNotPresentModally() throws {
        let root = try makeRoot()
        root.presentSettings()

        XCTAssertTrue(root.isSettingsVisible)
        XCTAssertFalse(root.settingsContainer.isHidden)
        XCTAssertNil(root.presentedViewController)

        root.dismissSettingsSheet()
        XCTAssertNil(root.presentedViewController)
    }

    func testSettingsContainerFillsDisplayEdgeToEdge() throws {
        let root = try makeRoot()
        root.view.layoutIfNeeded()
        XCTAssertEqual(root.settingsContainer.frame, root.view.bounds)

        root.presentSettingsSheet()
        root.view.layoutIfNeeded()

        XCTAssertEqual(root.settingsContainer.frame, root.view.bounds)
        let hosting = try XCTUnwrap(root.settingsHosting)
        XCTAssertTrue(hosting.view.superview === root.settingsContainer)
        XCTAssertTrue(root.settingsContainer.subviews.contains(hosting.view))
    }

    func testLibraryFillsDisplayEdgeToEdge() throws {
        let root = try makeRoot()
        root.view.layoutIfNeeded()
        XCTAssertTrue(root.bookmarksLibraryView.superview === root.view)
        XCTAssertEqual(root.bookmarksLibraryView.frame, root.view.bounds)

        root.openBookmarksLibrary(tab: .bookmarks)
        root.view.layoutIfNeeded()

        XCTAssertFalse(root.bookmarksLibraryView.isHidden)
        XCTAssertEqual(root.bookmarksLibraryView.frame, root.view.bounds)
        XCTAssertTrue(root.bookmarksLibraryView.superview === root.view)

        root.closeBookmarksLibrary()
        XCTAssertTrue(root.bookmarksLibraryView.isHidden)
    }

    func testSettingsCallbacksRemainWired() throws {
        let root = try makeRoot()
        root.presentSettingsSheet()
        let hosting = try XCTUnwrap(root.settingsHosting as? UIHostingController<SettingsView>)
        XCTAssertNotNil(hosting.rootView.onDidClearHistory)
        XCTAssertNotNil(hosting.rootView.onDidClearTabs)
    }
}
