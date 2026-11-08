// Tests — Coverage for the canonical bookmark folder context menu builder.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class BookmarkFolderContextMenuTests: XCTestCase {
    private enum Fixture {
        static let url1 = URL(string: "https://example.com/one")!
        static let url2 = URL(string: "https://example.com/two")!
    }

    func testEmptyFolderMenuOptionsAndDisabledStates() throws {
        let folder = BookmarkFolder(title: "Empty Folder")
        let actions = BookmarkFolderContextActions(
            onOpenInNewTab: { _ in },
            onOpenURLsInBackground: { _ in },
            onOpenURLsInTabGroup: { _, _ in },
            onOpenURLsInNewTabGroup: { _, _ in },
            onRequestEdit: { _ in },
            onDelete: { _ in },
            presentNewTabGroupPrompt: { _, _ in }
        )

        let menu = BookmarkFolderContextMenu.build(
            for: folder,
            urls: [],
            tabGroups: [],
            actions: actions
        )

        XCTAssertEqual(menu.children.count, 5)

        // Open (disabled)
        let openAction = try XCTUnwrap(menu.children[0] as? UIAction)
        XCTAssertEqual(openAction.title, "Open")
        XCTAssertEqual(openAction.image, UIImage(systemName: "safari"))
        XCTAssertTrue(openAction.attributes.contains(.disabled))

        // Open in Background (disabled)
        let openBgAction = try XCTUnwrap(menu.children[1] as? UIAction)
        XCTAssertEqual(openBgAction.title, "Open in Background")
        XCTAssertEqual(openBgAction.image, UIImage(systemName: "plus.square.on.square"))
        XCTAssertTrue(openBgAction.attributes.contains(.disabled))

        // Open in Tab Group (disabled action when empty)
        let tabGroupAction = try XCTUnwrap(menu.children[2] as? UIAction)
        XCTAssertEqual(tabGroupAction.title, "Open in Tab Group")
        XCTAssertEqual(tabGroupAction.image, UIImage(systemName: "square.grid.2x2"))
        XCTAssertTrue(tabGroupAction.attributes.contains(.disabled))

        // Edit… (enabled)
        let editAction = try XCTUnwrap(menu.children[3] as? UIAction)
        XCTAssertEqual(editAction.title, "Edit…")
        XCTAssertEqual(editAction.image, UIImage(systemName: "pencil"))
        XCTAssertFalse(editAction.attributes.contains(.disabled))

        // Delete (destructive)
        let deleteAction = try XCTUnwrap(menu.children[4] as? UIAction)
        XCTAssertEqual(deleteAction.title, "Delete")
        XCTAssertEqual(deleteAction.image, UIImage(systemName: "trash"))
        XCTAssertTrue(deleteAction.attributes.contains(.destructive))
    }

    func testPopulatedFolderMenuWithTabGroupsSubmenu() throws {
        let folder = BookmarkFolder(title: "Work Links")
        let group1 = TabGroup(id: UUID(), name: "Beta Group")
        let group2 = TabGroup(id: UUID(), name: "Alpha Group")

        let actions = BookmarkFolderContextActions(
            onOpenInNewTab: { _ in },
            onOpenURLsInBackground: { _ in },
            onOpenURLsInTabGroup: { _, _ in },
            onOpenURLsInNewTabGroup: { _, _ in },
            onRequestEdit: { _ in },
            onDelete: { _ in },
            presentNewTabGroupPrompt: { _, _ in }
        )

        let menu = BookmarkFolderContextMenu.build(
            for: folder,
            urls: [Fixture.url1, Fixture.url2],
            tabGroups: [group1, group2],
            actions: actions
        )

        XCTAssertEqual(menu.children.count, 5)

        // Open (enabled)
        let openAction = try XCTUnwrap(menu.children[0] as? UIAction)
        XCTAssertFalse(openAction.attributes.contains(.disabled))

        // Open in Background (enabled)
        let openBgAction = try XCTUnwrap(menu.children[1] as? UIAction)
        XCTAssertFalse(openBgAction.attributes.contains(.disabled))

        // Open in Tab Group (submenu)
        let tabGroupMenu = try XCTUnwrap(menu.children[2] as? UIMenu)
        XCTAssertEqual(tabGroupMenu.title, "Open in Tab Group")
        XCTAssertEqual(tabGroupMenu.image, UIImage(systemName: "square.grid.2x2"))

        // Submenu should have: New Tab Group… + sorted existing groups (Alpha, then Beta)
        XCTAssertEqual(tabGroupMenu.children.count, 3)
        let newGroup = try XCTUnwrap(tabGroupMenu.children[0] as? UIAction)
        XCTAssertEqual(newGroup.title, "New Tab Group…")
        XCTAssertEqual(newGroup.image, UIImage(systemName: "plus"))

        let alphaGroup = try XCTUnwrap(tabGroupMenu.children[1] as? UIAction)
        XCTAssertEqual(alphaGroup.title, "Alpha Group")
        XCTAssertEqual(alphaGroup.image, UIImage(systemName: "square.on.square"))

        let betaGroup = try XCTUnwrap(tabGroupMenu.children[2] as? UIAction)
        XCTAssertEqual(betaGroup.title, "Beta Group")
        XCTAssertEqual(betaGroup.image, UIImage(systemName: "square.on.square"))
    }

    func testStartPageViewFolderContextMenuConfiguration() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let bookmarkStore = BookmarkStore(database: database)
        let historyStore = HistoryStore(database: database)

        let folder = try bookmarkStore.createFolder(title: "Dev Tools", isFavorite: true)
        _ = try bookmarkStore.add(title: "Doc 1", url: Fixture.url1, folderId: folder.id)

        let viewModel = StartPageViewModel(bookmarkStore: bookmarkStore, historyStore: historyStore)
        let startPage = StartPageView(viewModel: viewModel)

        // Verify folder loadable URLs
        let urls = viewModel.loadableURLs(in: folder)
        XCTAssertEqual(urls, [Fixture.url1])

        // Verify folder menu generates properly from StartPageView
        let menu = try XCTUnwrap(startPage.folderContextMenu(for: folder))
        XCTAssertEqual(menu.children.count, 5)
        XCTAssertEqual(
            menu.children.map(\.title),
            ["Open", "Open in Background", "Open in Tab Group", "Edit…", "Delete"]
        )
    }
}
