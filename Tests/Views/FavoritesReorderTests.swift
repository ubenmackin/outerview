//
//  FavoritesReorderTests.swift
//  OuterViewTests
//

import Foundation
@testable import OuterView
import UIKit
import XCTest

final class FavoritesReorderTests: XCTestCase {
    private func makeIDs(_ count: Int) -> [UUID] {
        (0 ..< count).map { _ in UUID() }
    }

    func testCanBeginDragBounds() {
        XCTAssertTrue(FavoritesGridView.canBeginDrag(itemCount: 3, index: 0))
        XCTAssertTrue(FavoritesGridView.canBeginDrag(itemCount: 3, index: 2))
        XCTAssertFalse(FavoritesGridView.canBeginDrag(itemCount: 3, index: 3))
        XCTAssertFalse(FavoritesGridView.canBeginDrag(itemCount: 3, index: -1))
        XCTAssertFalse(FavoritesGridView.canBeginDrag(itemCount: 0, index: 0))
    }

    func testReorderedIDsForward() {
        let ids = makeIDs(4)
        let moved = FavoritesGridView.reorderedIDs(
            currentIDs: ids,
            draggedIDs: [ids[0]],
            destinationIndex: 2
        )
        XCTAssertEqual(moved, [ids[1], ids[2], ids[0], ids[3]])
    }

    func testReorderedIDsBackward() {
        let ids = makeIDs(4)
        let moved = FavoritesGridView.reorderedIDs(
            currentIDs: ids,
            draggedIDs: [ids[3]],
            destinationIndex: 0
        )
        XCTAssertEqual(moved, [ids[3], ids[0], ids[1], ids[2]])
    }

    func testReorderedIDsSameSpotReturnsUnchanged() {
        let ids = makeIDs(4)
        XCTAssertEqual(
            FavoritesGridView.reorderedIDs(currentIDs: ids, draggedIDs: [ids[1]], destinationIndex: 1),
            ids
        )
    }

    func testReorderedIDsOutOfRangeClamps() {
        let ids = makeIDs(4)
        XCTAssertEqual(
            FavoritesGridView.reorderedIDs(currentIDs: ids, draggedIDs: [ids[0]], destinationIndex: 99),
            [ids[1], ids[2], ids[3], ids[0]]
        )
        XCTAssertEqual(
            FavoritesGridView.reorderedIDs(currentIDs: ids, draggedIDs: [ids[3]], destinationIndex: -5),
            [ids[3], ids[0], ids[1], ids[2]]
        )
        XCTAssertEqual(
            FavoritesGridView.reorderedIDs(currentIDs: ids, draggedIDs: [UUID()], destinationIndex: 0),
            ids
        )
        XCTAssertEqual(
            FavoritesGridView.reorderedIDs(currentIDs: ids, draggedIDs: [], destinationIndex: 0),
            ids
        )
    }

    func testReorderedIDsKeepsFirstDraggedID() {
        let ids = makeIDs(4)
        let single = FavoritesGridView.reorderedIDs(
            currentIDs: ids,
            draggedIDs: [ids[1]],
            destinationIndex: 0
        )
        let multi = FavoritesGridView.reorderedIDs(
            currentIDs: ids,
            draggedIDs: [ids[1], ids[2]],
            destinationIndex: 0
        )
        XCTAssertEqual(single, [ids[1], ids[0], ids[2], ids[3]])
        XCTAssertEqual(multi, single)
    }

    @MainActor
    func testApplyOrderedFavoritesMapping() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let store = BookmarkStore(database: database)
        for (index, title) in ["A", "B", "C"].enumerated() {
            let url = try XCTUnwrap(URL(string: "https://example.com/\(title.lowercased())"))
            try store.add(
                title: title,
                url: url,
                isFavorite: true,
                addedDate: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let grid = FavoritesGridView(bookmarkStore: store)
        let initialIDs = grid.favorites.map(\.id)
        XCTAssertEqual(initialIDs.count, 3)
        let ordered = FavoritesGridView.reorderedIDs(
            currentIDs: initialIDs,
            draggedIDs: [initialIDs[0]],
            destinationIndex: 2
        )
        XCTAssertTrue(grid.applyOrderedFavorites(ordered))
        XCTAssertEqual(grid.favorites.map(\.id), ordered)
    }

    @MainActor
    func testApplyOrderedFavoritesMissingIDReturnsFalse() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let store = BookmarkStore(database: database)
        for (index, title) in ["A", "B", "C"].enumerated() {
            let url = try XCTUnwrap(URL(string: "https://example.com/\(title.lowercased())"))
            try store.add(
                title: title,
                url: url,
                isFavorite: true,
                addedDate: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let grid = FavoritesGridView(bookmarkStore: store)
        let initialIDs = grid.favorites.map(\.id)
        XCTAssertEqual(initialIDs.count, 3)
        var bad = initialIDs
        bad[1] = UUID()
        XCTAssertFalse(grid.applyOrderedFavorites(bad))
        XCTAssertEqual(grid.favorites.map(\.id), initialIDs)
    }

    @MainActor
    func testStoreRoundTripReflectsReorder() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let store = BookmarkStore(database: database)
        for (index, title) in ["A", "B", "C"].enumerated() {
            let url = try XCTUnwrap(URL(string: "https://example.com/\(title.lowercased())"))
            try store.add(
                title: title,
                url: url,
                isFavorite: true,
                addedDate: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let initialIDs = store.fetchFavorites().map(\.id)
        XCTAssertEqual(initialIDs.count, 3)

        let ordered = FavoritesGridView.reorderedIDs(
            currentIDs: initialIDs,
            draggedIDs: [initialIDs[0]],
            destinationIndex: 2
        )
        XCTAssertEqual(ordered, [initialIDs[1], initialIDs[2], initialIDs[0]])

        try store.reorderBookmarks(ordered)
        XCTAssertEqual(store.fetchFavorites().map(\.id), ordered)
    }

    @MainActor
    func testStartPageHostOwnsPressDragReorder() throws {
        let startView = try makeStartPageView()
        XCTAssertTrue((startView as Any) is UICollectionViewDragDelegate)
        XCTAssertTrue((startView as Any) is UICollectionViewDropDelegate)
    }

    @MainActor
    func testStartPageCanBeginDragBounds() {
        XCTAssertTrue(StartPageView.canBeginDrag(itemCount: 3, index: 0))
        XCTAssertTrue(StartPageView.canBeginDrag(itemCount: 3, index: 2))
        XCTAssertFalse(StartPageView.canBeginDrag(itemCount: 3, index: 3))
        XCTAssertFalse(StartPageView.canBeginDrag(itemCount: 3, index: -1))
        XCTAssertFalse(StartPageView.canBeginDrag(itemCount: 0, index: 0))
    }

    @MainActor
    func testStartPageReorderedIDsMatchesGrid() {
        let ids = makeIDs(4)
        XCTAssertEqual(
            StartPageView.reorderedIDs(currentIDs: ids, draggedIDs: [ids[0]], destinationIndex: 2),
            FavoritesGridView.reorderedIDs(currentIDs: ids, draggedIDs: [ids[0]], destinationIndex: 2)
        )
        XCTAssertEqual(
            StartPageView.reorderedIDs(currentIDs: ids, draggedIDs: [ids[3]], destinationIndex: 0),
            [ids[3], ids[0], ids[1], ids[2]]
        )
        XCTAssertEqual(
            StartPageView.reorderedIDs(currentIDs: ids, draggedIDs: [ids[0]], destinationIndex: 99),
            [ids[1], ids[2], ids[3], ids[0]]
        )
        XCTAssertEqual(
            StartPageView.reorderedIDs(currentIDs: ids, draggedIDs: [UUID()], destinationIndex: 0),
            ids
        )
    }

    @MainActor
    func testStartPageApplyOrderedFavoritesMapping() throws {
        let startView = try makeStartPageView(titles: ["A", "B", "C"])
        let initialIDs = startView.viewModel.favorites.map(\.id)
        XCTAssertEqual(initialIDs.count, 3)
        let ordered = StartPageView.reorderedIDs(
            currentIDs: initialIDs,
            draggedIDs: [initialIDs[0]],
            destinationIndex: 2
        )
        XCTAssertTrue(startView.applyOrderedFavorites(ordered))
        XCTAssertEqual(startView.viewModel.favorites.map(\.id), ordered)
    }

    @MainActor
    func testStartPageApplyOrderedFavoritesMissingIDReturnsFalse() throws {
        let startView = try makeStartPageView(titles: ["A", "B", "C"])
        let initialIDs = startView.viewModel.favorites.map(\.id)
        XCTAssertEqual(initialIDs.count, 3)
        var bad = initialIDs
        bad[1] = UUID()
        XCTAssertFalse(startView.applyOrderedFavorites(bad))
        XCTAssertEqual(startView.viewModel.favorites.map(\.id), initialIDs)
    }

    @MainActor
    func testStartPagePersistedReorderRoundTrip() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let bookmarkStore = BookmarkStore(database: database)
        let historyStore = HistoryStore(database: database)
        for (index, title) in ["A", "B", "C"].enumerated() {
            let url = try XCTUnwrap(URL(string: "https://example.com/\(title.lowercased())"))
            try bookmarkStore.add(
                title: title,
                url: url,
                isFavorite: true,
                addedDate: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let viewModel = StartPageViewModel(bookmarkStore: bookmarkStore, historyStore: historyStore)
        let initialIDs = viewModel.favorites.map(\.id)
        XCTAssertEqual(initialIDs.count, 3)
        let ordered = StartPageView.reorderedIDs(
            currentIDs: initialIDs,
            draggedIDs: [initialIDs[0]],
            destinationIndex: 2
        )
        XCTAssertEqual(ordered, [initialIDs[1], initialIDs[2], initialIDs[0]])
        XCTAssertTrue(viewModel.applyOrderedFavorites(ordered))
        try viewModel.persistReorderedFavorites(ordered)
        XCTAssertEqual(bookmarkStore.fetchFavorites().map(\.id), ordered)
        viewModel.reload()
        XCTAssertEqual(viewModel.favorites.map(\.id), ordered)
    }

    @MainActor
    private func makeStartPageView(titles: [String] = ["A", "B", "C"]) throws -> StartPageView {
        let database = try OuterViewDatabase(inMemory: true)
        let bookmarkStore = BookmarkStore(database: database)
        let historyStore = HistoryStore(database: database)
        for (index, title) in titles.enumerated() {
            let url = try XCTUnwrap(URL(string: "https://example.com/\(title.lowercased())"))
            try bookmarkStore.add(
                title: title,
                url: url,
                isFavorite: true,
                addedDate: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let viewModel = StartPageViewModel(bookmarkStore: bookmarkStore, historyStore: historyStore)
        return StartPageView(viewModel: viewModel)
    }
}
