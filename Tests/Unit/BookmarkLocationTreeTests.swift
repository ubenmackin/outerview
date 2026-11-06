// Bookmarks — Location tree option tests.

@testable import OuterView
import XCTest

final class BookmarkLocationTreeTests: XCTestCase {
    func testLocationTreeForBookmarkIncludesFavoritesAndIndents() {
        let f1 = BookmarkFolder(title: "Dev", parentId: nil, sortOrder: 0)
        let f1Sub = BookmarkFolder(title: "Swift", parentId: f1.id, sortOrder: 0)
        let f2 = BookmarkFolder(title: "News", parentId: nil, sortOrder: 1)

        let options = BookmarkLocationTree.optionsForBookmark(folders: [f1, f1Sub, f2])

        XCTAssertEqual(options.count, 5)
        XCTAssertEqual(options[0].location, .favorites)
        XCTAssertEqual(options[0].depth, 0)

        XCTAssertEqual(options[1].location, .root)
        XCTAssertEqual(options[1].depth, 0)

        XCTAssertEqual(options[2].location, .folder(f1.id))
        XCTAssertEqual(options[2].title, "Dev")
        XCTAssertEqual(options[2].depth, 1)

        XCTAssertEqual(options[3].location, .folder(f1Sub.id))
        XCTAssertEqual(options[3].title, "Swift")
        XCTAssertEqual(options[3].depth, 2)

        XCTAssertEqual(options[4].location, .folder(f2.id))
        XCTAssertEqual(options[4].title, "News")
        XCTAssertEqual(options[4].depth, 1)
    }

    func testLocationTreeForFolderIncludesFavoritesAndExcludesDescendants() {
        let root = BookmarkFolder(title: "Root", parentId: nil, sortOrder: 0)
        let child = BookmarkFolder(title: "Child", parentId: root.id, sortOrder: 0)
        let grandchild = BookmarkFolder(title: "Grandchild", parentId: child.id, sortOrder: 0)
        let sibling = BookmarkFolder(title: "Sibling", parentId: nil, sortOrder: 1)

        let options = BookmarkLocationTree.optionsForFolder(
            folderId: root.id,
            folders: [root, child, grandchild, sibling]
        )

        // Favorites and root Bookmarks available; descendants excluded
        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options[0].location, .favorites)
        XCTAssertEqual(options[1].location, .root)
        XCTAssertEqual(options[2].location, .folder(sibling.id))
    }

    func testLocationTreeForFolderWithFavoriteFolders() {
        let favFolder = BookmarkFolder(title: "Work", parentId: nil, sortOrder: 0, isFavorite: true)
        let bmFolder = BookmarkFolder(title: "Reading", parentId: nil, sortOrder: 0, isFavorite: false)

        let options = BookmarkLocationTree.optionsForFolder(
            folderId: nil,
            folders: [favFolder, bmFolder]
        )

        XCTAssertEqual(options.map(\.title), ["Favorites", "Work", "Bookmarks", "Reading"])
        XCTAssertEqual(options[0].location, .favorites)
        XCTAssertEqual(options[1].location, .folder(favFolder.id))
        XCTAssertEqual(options[2].location, .root)
        XCTAssertEqual(options[3].location, .folder(bmFolder.id))
    }

    @MainActor
    func testClampedMoveTargetPreventsCrossSectionMove() {
        let provider: (Int) -> BookmarksBrowserView.Section = { section in
            switch section {
            case 0: .pinnedFavorites
            case 1: .folders
            default: .bookmarks
            }
        }

        // Pinned favorites cannot move
        let favSource = IndexPath(row: 0, section: 0)
        let favTarget = IndexPath(row: 1, section: 0)
        XCTAssertEqual(
            BookmarksBrowserView.clampedMoveTarget(source: favSource, proposed: favTarget, sectionTypeProvider: provider),
            favSource
        )

        // Folder moving within folders section succeeds
        let folderSource = IndexPath(row: 0, section: 1)
        let folderTarget = IndexPath(row: 2, section: 1)
        XCTAssertEqual(
            BookmarksBrowserView.clampedMoveTarget(source: folderSource, proposed: folderTarget, sectionTypeProvider: provider),
            folderTarget
        )

        // Bookmark moving into folders section clamped to source
        let bookmarkSource = IndexPath(row: 0, section: 2)
        let badTarget = IndexPath(row: 0, section: 1)
        XCTAssertEqual(
            BookmarksBrowserView.clampedMoveTarget(source: bookmarkSource, proposed: badTarget, sectionTypeProvider: provider),
            bookmarkSource
        )

        // Bookmark moving into pinned favorites clamped to source
        let badTargetFav = IndexPath(row: 0, section: 0)
        XCTAssertEqual(
            BookmarksBrowserView.clampedMoveTarget(source: bookmarkSource, proposed: badTargetFav, sectionTypeProvider: provider),
            bookmarkSource
        )
    }

    func testPageMenuModel() throws {
        // Without loadable URL
        let emptyModel = PageMenuModel(url: nil)
        XCTAssertFalse(emptyModel.canReload)
        XCTAssertFalse(emptyModel.canShare)
        XCTAssertFalse(emptyModel.canSave)
        XCTAssertFalse(emptyModel.canGoBack)
        XCTAssertFalse(emptyModel.canGoForward)

        // With valid URL
        let validURL = try XCTUnwrap(URL(string: "https://apple.com"))
        let activeModel = PageMenuModel(
            url: validURL,
            canGoBack: true,
            canGoForward: false,
            isFavorite: true
        )
        XCTAssertTrue(activeModel.canReload)
        XCTAssertTrue(activeModel.canShare)
        XCTAssertTrue(activeModel.canSave)
        XCTAssertTrue(activeModel.canGoBack)
        XCTAssertFalse(activeModel.canGoForward)
        XCTAssertTrue(activeModel.isFavorite)
    }
}
