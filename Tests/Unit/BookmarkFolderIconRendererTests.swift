// Favorites — Tests for folder and star badge renderer.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class BookmarkFolderIconRendererTests: XCTestCase {
    func testFavoritesBadgeRendersAtRequestedSize() {
        let image = BookmarkFolderIconRenderer.favoritesBadge(size: 30, cornerRadius: 6)
        XCTAssertEqual(image.size.width, 30)
        XCTAssertEqual(image.size.height, 30)
    }

    func testFolderBadgeEmptyFolderRenders() {
        let folder = BookmarkFolder(title: "Empty")
        let image = BookmarkFolderIconRenderer.folderBadge(for: folder, previewBookmarks: [], size: 30, cornerRadius: 6)
        XCTAssertEqual(image.size.width, 30)
        XCTAssertEqual(image.size.height, 30)
    }

    func testFolderBadgeWithPreviewsRendersAtTileSize() throws {
        let folder = BookmarkFolder(title: "Previews")
        let bookmarks = try [
            Bookmark(title: "One", url: XCTUnwrap(URL(string: "https://one.example.com")), addedAt: Date()),
            Bookmark(title: "Two", url: XCTUnwrap(URL(string: "https://two.example.com")), addedAt: Date()),
            Bookmark(title: "Three", url: XCTUnwrap(URL(string: "https://three.example.com")), addedAt: Date()),
            Bookmark(title: "Four", url: XCTUnwrap(URL(string: "https://four.example.com")), addedAt: Date())
        ]
        let tileImage = BookmarkFolderIconRenderer.folderBadge(
            for: folder,
            previewBookmarks: bookmarks,
            size: 76,
            cornerRadius: 18
        )
        XCTAssertEqual(tileImage.size.width, 76)
        XCTAssertEqual(tileImage.size.height, 76)
    }
}
