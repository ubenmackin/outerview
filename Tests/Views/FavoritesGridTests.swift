//
//  FavoritesGridTests.swift
//  OuterView
//

import CoreGraphics
@testable import OuterView
import XCTest

final class FavoritesGridTests: XCTestCase {
    func testItemSizeOuterPortraitFourColumns() {
        let size = FavoritesGridView.itemSize(forContentWidth: 434, columns: 4)
        XCTAssertEqual(size, CGSize(width: 96, height: 132))
    }

    func testItemSizeInnerLandscapeSixColumns() {
        let size = FavoritesGridView.itemSize(forContentWidth: 919, columns: 6)
        XCTAssertEqual(size, CGSize(width: 139, height: 175))
    }

    func testItemSizeClampsToMinimumTile() {
        let narrow = FavoritesGridView.itemSize(forContentWidth: 100, columns: 4)
        XCTAssertEqual(narrow, CGSize(width: 76, height: 112))

        let singleColumnNarrow = FavoritesGridView.itemSize(forContentWidth: 50, columns: 1)
        XCTAssertEqual(singleColumnNarrow, CGSize(width: 76, height: 112))
    }

    func testItemSizeHeightEqualsWidthPlus36() {
        let widths: [CGFloat] = [200, 434, 600, 919]
        let columns = [2, 4, 4, 6]
        for (width, column) in zip(widths, columns) {
            let size = FavoritesGridView.itemSize(forContentWidth: width, columns: column)
            XCTAssertEqual(size.height, size.width + 36)
        }
    }

    @MainActor
    func testAttachedGridBouncesVertically() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let store = BookmarkStore(database: database)
        let grid = FavoritesGridView(bookmarkStore: store)
        grid.frame = TestWindow.defaultFrame
        TestWindow.attach(grid)

        let collectionView = try XCTUnwrap(
            grid.subviews.first(where: { $0 is UICollectionView }) as? UICollectionView
        )
        XCTAssertTrue(collectionView.alwaysBounceVertical)
    }

    @MainActor
    func testAttachedGridRecomputesTileSize() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let store = BookmarkStore(database: database)
        let grid = FavoritesGridView(bookmarkStore: store)
        grid.frame = TestWindow.defaultFrame
        TestWindow.attach(grid)
        grid.layoutIfNeeded()

        let collectionView = try XCTUnwrap(
            grid.subviews.first(where: { $0 is UICollectionView }) as? UICollectionView
        )
        let layout = try XCTUnwrap(collectionView.collectionViewLayout as? UICollectionViewFlowLayout)
        let columns = StartPageViewModel.columnCount(for: grid.traitCollection)
        let expected = FavoritesGridView.itemSize(
            forContentWidth: grid.bounds.width - 32,
            columns: columns
        )
        XCTAssertEqual(layout.itemSize, expected)
    }
}
