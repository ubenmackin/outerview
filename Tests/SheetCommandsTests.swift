//
//  SheetCommandsTests.swift
//  OuterViewTests
//

@testable import OuterView
import SwiftUI
import XCTest

@MainActor
final class SheetCommandsTests: XCTestCase {
    private func makeRoot() throws -> BrowserRootViewController {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        TestWindow.attach(root)
        return root
    }

    private struct TestStores {
        let bookmarks: BookmarkStore
        let history: HistoryStore
        let tabs: TabStore
    }

    private func makeStores() throws -> TestStores {
        let database = try OuterViewDatabase(inMemory: true)
        return TestStores(
            bookmarks: BookmarkStore(database: database),
            history: HistoryStore(database: database),
            tabs: TabStore(database: database)
        )
    }

    func testSettingsDefaultsToCompactWithoutToolbar() throws {
        let stores = try makeStores()
        let view = SettingsView(
            bookmarkStore: stores.bookmarks,
            historyStore: stores.history,
            tabStore: stores.tabs
        )
        XCTAssertFalse(view.inlineCommands)
        XCTAssertFalse(view.showsInlineDone)
    }

    func testSettingsShowsInlineDoneWhenFlagTrue() throws {
        let stores = try makeStores()
        let view = SettingsView(
            bookmarkStore: stores.bookmarks,
            historyStore: stores.history,
            tabStore: stores.tabs,
            inlineCommands: true
        )
        XCTAssertTrue(view.inlineCommands)
        XCTAssertTrue(view.showsInlineDone)
    }

    func testDownloadsDefaultsToCompactWithoutToolbar() {
        let view = DownloadsSheetView(manager: DownloadsManager())
        XCTAssertFalse(view.inlineCommands)
        XCTAssertFalse(view.showsInlineDone)
    }

    func testDownloadsShowsInlineDoneWhenFlagTrue() {
        let view = DownloadsSheetView(manager: DownloadsManager(), inlineCommands: true)
        XCTAssertTrue(view.inlineCommands)
        XCTAssertTrue(view.showsInlineDone)
    }

    func testBookmarkEditorDefaultsToCompactWithoutToolbar() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let store = BookmarkStore(database: database)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let model = BookmarkEditorModel(target: .addBookmark(title: "T", url: url))
        let view = BookmarkEditorView(model: model, bookmarkStore: store)
        XCTAssertFalse(view.inlineCommands)
        XCTAssertFalse(view.showsInlineCancel)
        XCTAssertFalse(view.showsInlineSave)
    }

    func testBookmarkEditorShowsInlineCommandsWhenFlagTrue() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let store = BookmarkStore(database: database)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let model = BookmarkEditorModel(target: .addBookmark(title: "T", url: url))
        let view = BookmarkEditorView(model: model, bookmarkStore: store, inlineCommands: true)
        XCTAssertTrue(view.inlineCommands)
        XCTAssertTrue(view.showsInlineCancel)
        XCTAssertTrue(view.showsInlineSave)
    }

    func testSettingsInlineDoneFiresCallback() throws {
        let stores = try makeStores()
        var didCall = false
        let view = SettingsView(
            bookmarkStore: stores.bookmarks,
            historyStore: stores.history,
            tabStore: stores.tabs,
            inlineCommands: true,
            onDone: { didCall = true }
        )
        view.performInlineDone()
        XCTAssertTrue(didCall)
    }

    func testDownloadsInlineDoneFiresCallback() {
        var didCall = false
        let view = DownloadsSheetView(
            manager: DownloadsManager(),
            inlineCommands: true,
            onDone: { didCall = true }
        )
        view.performInlineDone()
        XCTAssertTrue(didCall)
    }

    func testBookmarkEditorInlineCancelAndSaveFireCallbacks() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let store = BookmarkStore(database: database)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        var didCancel = false
        var didSave = false
        let cancelView = BookmarkEditorView(
            model: BookmarkEditorModel(target: .addBookmark(title: "T", url: url)),
            bookmarkStore: store,
            inlineCommands: true,
            onCancel: { didCancel = true },
            onSave: { didSave = true }
        )
        cancelView.performInlineCancel()
        XCTAssertTrue(didCancel)
        XCTAssertFalse(didSave)
        cancelView.performInlineSave()
        XCTAssertTrue(didSave)
    }

    func testRootSettingsWiresInlineCommandsAndDoneDismisses() throws {
        let root = try makeRoot()
        root.presentSettingsSheet()
        let hosting = try XCTUnwrap(root.settingsHosting as? UIHostingController<SettingsView>)
        XCTAssertEqual(hosting.rootView.inlineCommands, root.chromePlacement == .regular)
        XCTAssertEqual(hosting.rootView.showsInlineDone, root.chromePlacement == .regular)
        hosting.rootView.performInlineDone()
        XCTAssertFalse(root.isSettingsVisible)
        XCTAssertNil(root.settingsHosting)
    }

    func testRootDownloadsWiresInlineCommandsAndDoneDismisses() throws {
        let root = try makeRoot()
        root.presentDownloadsSheet()
        let hosting = try XCTUnwrap(root.downloadsHosting as? UIHostingController<DownloadsSheetView>)
        XCTAssertEqual(hosting.rootView.inlineCommands, root.chromePlacement == .regular)
        XCTAssertEqual(hosting.rootView.showsInlineDone, root.chromePlacement == .regular)
        hosting.rootView.performInlineDone()
        XCTAssertFalse(root.isDownloadsVisible)
        XCTAssertNil(root.downloadsHosting)
    }

    func testRootBookmarkEditorWiresInlineCommandsAndCancelSave() throws {
        let root = try makeRoot()
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        root.presentBookmarkEditor(for: .addBookmark(title: "T", url: url))
        let inlineCommands = try XCTUnwrap(root.bookmarkEditorInlineCommands)
        XCTAssertEqual(inlineCommands, root.chromePlacement == .regular)
        XCTAssertEqual(try XCTUnwrap(root.bookmarkEditorShowsInlineCancel), root.chromePlacement == .regular)
        XCTAssertEqual(try XCTUnwrap(root.bookmarkEditorShowsInlineSave), root.chromePlacement == .regular)
        root.performBookmarkEditorCancel()
        XCTAssertFalse(root.isBookmarkEditorVisible)

        root.presentBookmarkEditor(for: .addBookmark(title: "T", url: url))
        root.performBookmarkEditorSave()
        XCTAssertFalse(root.isBookmarkEditorVisible)
    }
}
