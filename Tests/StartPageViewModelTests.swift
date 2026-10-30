//
//  StartPageViewModelTests.swift
//  OuterView
//

@testable import OuterView
import XCTest

@MainActor
final class StartPageViewModelTests: XCTestCase {
    private func makeDatabase() throws -> OuterViewDatabase {
        try OuterViewDatabase(inMemory: true)
    }

    private func record(
        _ store: HistoryStore,
        urlString: String,
        title: String,
        at offset: TimeInterval
    ) throws {
        let url = try XCTUnwrap(URL(string: urlString))
        try store.record(
            visit: PageVisit(url: url, title: title, visitedAt: Date(timeIntervalSince1970: offset))
        )
    }

    func testFiveVisitSequenceCollapsesToThreeRows() throws {
        let database = try makeDatabase()
        let bookmarkStore = BookmarkStore(database: database)
        let historyStore = HistoryStore(database: database)
        try record(historyStore, urlString: "https://example.com", title: "Example old", at: 1)
        try record(historyStore, urlString: "https://apple.com", title: "Apple", at: 2)
        try record(historyStore, urlString: "https://google.com", title: "Google", at: 3)
        try record(historyStore, urlString: "https://example.com", title: "Example mid", at: 4)
        try record(historyStore, urlString: "https://example.com", title: "Example newest", at: 5)

        let viewModel = StartPageViewModel(bookmarkStore: bookmarkStore, historyStore: historyStore)

        XCTAssertEqual(viewModel.recents.count, 3)
        XCTAssertEqual(viewModel.recents.first?.url.absoluteString, "https://example.com")
        XCTAssertEqual(viewModel.recents.first?.title, "Example newest")
        XCTAssertEqual(
            viewModel.recents.map(\.url.absoluteString),
            ["https://example.com", "https://google.com", "https://apple.com"]
        )
        XCTAssertFalse(viewModel.isRecentsEmpty)
    }

    func testNewestVisitWinsTitle() throws {
        let database = try makeDatabase()
        let bookmarkStore = BookmarkStore(database: database)
        let historyStore = HistoryStore(database: database)
        try record(historyStore, urlString: "https://example.com", title: "Old", at: 1)
        try record(historyStore, urlString: "https://example.com", title: "New", at: 2)

        let viewModel = StartPageViewModel(bookmarkStore: bookmarkStore, historyStore: historyStore)

        XCTAssertEqual(viewModel.recents.count, 1)
        XCTAssertEqual(viewModel.recents.first?.title, "New")
    }

    func testDistinctPathsOnSameHostStaySeparate() throws {
        let newerURL = try XCTUnwrap(URL(string: "https://example.com/a"))
        let olderURL = try XCTUnwrap(URL(string: "https://example.com/b"))
        let newer = HistoryEntry(
            title: "A",
            url: newerURL,
            visitedAt: Date(timeIntervalSince1970: 2)
        )
        let older = HistoryEntry(
            title: "B",
            url: olderURL,
            visitedAt: Date(timeIntervalSince1970: 1)
        )

        let recents = StartPageViewModel.sortedRecents([newer, older])

        XCTAssertEqual(recents.count, 2)
        XCTAssertEqual(recents.map(\.title), ["A", "B"])
    }

    func testMoreThanEightUniqueVisitsShowsEightNewestRows() throws {
        let database = try makeDatabase()
        let bookmarkStore = BookmarkStore(database: database)
        let historyStore = HistoryStore(database: database)
        for index in 0 ..< 12 {
            try record(
                historyStore,
                urlString: "https://example.com/\(index)",
                title: "Page \(index)",
                at: TimeInterval(index)
            )
        }

        let viewModel = StartPageViewModel(bookmarkStore: bookmarkStore, historyStore: historyStore)

        XCTAssertEqual(viewModel.recents.count, 8)
        XCTAssertEqual(viewModel.recents.first?.title, "Page 11")
        XCTAssertEqual(viewModel.recents.last?.title, "Page 4")
    }

    func testDuplicatedHeadStillSurfacesUniqueRows() throws {
        let database = try makeDatabase()
        let bookmarkStore = BookmarkStore(database: database)
        let historyStore = HistoryStore(database: database)
        try record(historyStore, urlString: "https://apple.com", title: "Apple", at: 1)
        try record(historyStore, urlString: "https://google.com", title: "Google", at: 2)
        for index in 0 ..< 8 {
            try record(
                historyStore,
                urlString: "https://example.com",
                title: "Example \(index)",
                at: TimeInterval(10 + index)
            )
        }

        let viewModel = StartPageViewModel(bookmarkStore: bookmarkStore, historyStore: historyStore)

        XCTAssertEqual(viewModel.recents.count, 3)
        XCTAssertEqual(viewModel.recents.first?.title, "Example 7")
        XCTAssertEqual(
            viewModel.recents.map(\.url.absoluteString),
            ["https://example.com", "https://google.com", "https://apple.com"]
        )
    }

    func testEmptyHistoryShowsEmptyState() throws {
        let database = try makeDatabase()
        let bookmarkStore = BookmarkStore(database: database)
        let historyStore = HistoryStore(database: database)

        let viewModel = StartPageViewModel(bookmarkStore: bookmarkStore, historyStore: historyStore)

        XCTAssertTrue(viewModel.recents.isEmpty)
        XCTAssertTrue(viewModel.isRecentsEmpty)
        XCTAssertTrue(StartPageViewModel.isRecentsEmpty(viewModel.recents))
        XCTAssertTrue(StartPageViewModel.sortedRecents([]).isEmpty)
    }
}
