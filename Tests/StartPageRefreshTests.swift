//
//  StartPageRefreshTests.swift
//  OuterView
//

@testable import OuterView
import XCTest

@MainActor
final class StartPageRefreshTests: XCTestCase {
    func testUpdateStartPageContentRefetchesFavoritesAndRecents() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let rootVC = BrowserRootViewController(database: database)
        TestWindow.attach(rootVC)
        let startPage = try XCTUnwrap(rootVC.startPageView)
        XCTAssertTrue(startPage.viewModel.favorites.isEmpty)
        XCTAssertTrue(startPage.viewModel.recents.isEmpty)

        let bookmarkStore = try XCTUnwrap(rootVC.bookmarkStore)
        let historyStore = try XCTUnwrap(rootVC.historyStore)
        let favoriteA = try XCTUnwrap(URL(string: "https://example.com/a"))
        let favoriteB = try XCTUnwrap(URL(string: "https://example.com/b"))
        try bookmarkStore.upsertFavorite(url: favoriteA, title: "Example A")
        try bookmarkStore.upsertFavorite(url: favoriteB, title: "Example B")
        let historyA = try XCTUnwrap(URL(string: "https://example.com/history-a"))
        let historyB = try XCTUnwrap(URL(string: "https://example.org/history-b"))
        let historyC = try XCTUnwrap(URL(string: "https://example.net/history-c"))
        try historyStore.record(visit: PageVisit(url: historyA, title: "History A", visitedAt: Date(timeIntervalSince1970: 1)))
        try historyStore.record(visit: PageVisit(url: historyB, title: "History B", visitedAt: Date(timeIntervalSince1970: 2)))
        try historyStore.record(visit: PageVisit(url: historyC, title: "History C", visitedAt: Date(timeIntervalSince1970: 3)))

        rootVC.updateStartPageContent()

        let favorites = startPage.viewModel.favorites
        XCTAssertEqual(favorites.count, 2)
        XCTAssertEqual(Set(favorites.map(\.url)), [favoriteA, favoriteB])
        let recents = startPage.viewModel.recents
        XCTAssertEqual(recents.map(\.url), [historyC, historyB, historyA])
        XCTAssertFalse(startPage.viewModel.isFavoritesEmpty)
        XCTAssertFalse(startPage.viewModel.isRecentsEmpty)
    }

    func testEmptyStoresRenderEmptyState() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let rootVC = BrowserRootViewController(database: database)
        TestWindow.attach(rootVC)
        let startPage = try XCTUnwrap(rootVC.startPageView)

        rootVC.updateStartPageContent()

        XCTAssertTrue(startPage.viewModel.favorites.isEmpty)
        XCTAssertTrue(startPage.viewModel.recents.isEmpty)
        XCTAssertTrue(startPage.viewModel.isFavoritesEmpty)
        XCTAssertTrue(startPage.viewModel.isRecentsEmpty)
    }
}
