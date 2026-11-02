//
//  DownloadsSheetTests.swift
//  OuterViewTests
//

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class DownloadsSheetTests: XCTestCase {
    private var window: UIWindow?

    private func makeRoot() throws -> BrowserRootViewController {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        root.loadViewIfNeeded()
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = TestWindow.defaultFrame
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        self.window = window
        return root
    }

    private func railButtons(in rail: SideRailView) -> [UIButton] {
        rail.subviews
            .compactMap { $0 as? UIStackView }
            .flatMap { $0.arrangedSubviews.compactMap { $0 as? UIButton } }
    }

    private func railButton(labeled label: String, in rail: SideRailView) -> UIButton? {
        railButtons(in: rail).first(where: { $0.accessibilityLabel == label })
    }

    func testPresentSetsFlagShowsContainerAndRailMode() throws {
        let root = try makeRoot()
        XCTAssertFalse(root.isDownloadsVisible)
        XCTAssertTrue(root.downloadsContainer.isHidden)

        root.presentDownloadsSheet()

        XCTAssertTrue(root.isDownloadsVisible)
        XCTAssertFalse(root.downloadsContainer.isHidden)
        XCTAssertNotNil(root.downloadsHosting)
        XCTAssertEqual(root.currentRailMode, .downloads)
    }

    func testDismissClearsFlagHidesContainerAndRestoresRailMode() throws {
        let root = try makeRoot()
        root.presentDownloadsSheet()
        XCTAssertEqual(root.currentRailMode, .downloads)

        root.dismissDownloadsSheet()

        XCTAssertFalse(root.isDownloadsVisible)
        XCTAssertTrue(root.downloadsContainer.isHidden)
        XCTAssertNil(root.downloadsHosting)
        XCTAssertEqual(root.currentRailMode, .browsing)
    }

    func testRailModeResolvesAfterSettingsBeforeLibrary() throws {
        let root = try makeRoot()
        root.openBookmarksLibrary(tab: .bookmarks)
        XCTAssertEqual(root.currentRailMode, .library(.bookmarks))

        root.presentDownloadsSheet()
        XCTAssertEqual(root.currentRailMode, .downloads)

        root.presentSettingsSheet()
        XCTAssertEqual(root.currentRailMode, .settings)

        root.dismissSettingsSheet()
        XCTAssertEqual(root.currentRailMode, .downloads)

        root.dismissDownloadsSheet()
        XCTAssertEqual(root.currentRailMode, .library(.bookmarks))

        root.closeBookmarksLibrary()
        XCTAssertEqual(root.currentRailMode, .browsing)
    }

    func testDownloadsRailShowsFilesClearAndDone() throws {
        let root = try makeRoot()
        root.presentDownloadsSheet()
        root.updateRailItems()

        let files = try XCTUnwrap(railButton(labeled: "Files", in: root.railView))
        let clear = try XCTUnwrap(railButton(labeled: "Clear All", in: root.railView))
        let done = try XCTUnwrap(railButton(labeled: "Done", in: root.railView))
        XCTAssertNotNil(files)
        XCTAssertNotNil(clear)
        XCTAssertNotNil(done)
        root.dismissDownloadsSheet()
    }

    func testClearDisabledWhenRowsEmpty() throws {
        let root = try makeRoot()
        XCTAssertTrue(root.downloadsManager.rows.isEmpty)
        root.presentDownloadsSheet()
        root.updateRailItems()

        let clear = try XCTUnwrap(railButton(labeled: "Clear All", in: root.railView))
        XCTAssertFalse(clear.isEnabled)
        root.dismissDownloadsSheet()
    }

    func testClearEnabledWhenRowsNonEmpty() throws {
        let root = try makeRoot()
        _ = root.downloadsManager.registerRow(name: "a.zip", fileURL: nil)
        root.presentDownloadsSheet()
        root.updateRailItems()

        let clear = try XCTUnwrap(railButton(labeled: "Clear All", in: root.railView))
        XCTAssertTrue(clear.isEnabled)
        root.dismissDownloadsSheet()
    }

    func testDoneButtonDismissesSheet() throws {
        let root = try makeRoot()
        root.presentDownloadsSheet()
        root.updateRailItems()

        let done = try XCTUnwrap(railButton(labeled: "Done", in: root.railView))
        done.sendActions(for: .touchUpInside)

        XCTAssertFalse(root.isDownloadsVisible)
        XCTAssertTrue(root.downloadsContainer.isHidden)
        XCTAssertNil(root.downloadsHosting)
    }

    func testClearAllEmptiesRowsAndFiles() throws {
        let root = try makeRoot()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first.bin")
        try Data(repeating: 1, count: 256).write(to: firstURL)
        _ = root.downloadsManager.registerRow(name: "first.bin", fileURL: firstURL)
        let secondURL = tempDir.appendingPathComponent("second.bin")
        try Data(repeating: 2, count: 256).write(to: secondURL)
        let second = root.downloadsManager.registerRow(name: "second.bin", fileURL: secondURL)
        root.downloadsManager.applyProgress(0.5, for: second)
        XCTAssertEqual(root.downloadsManager.rows.count, 2)

        root.presentDownloadsSheet()
        root.updateRailItems()

        let clear = try XCTUnwrap(railButton(labeled: "Clear All", in: root.railView))
        XCTAssertTrue(clear.isEnabled)
        clear.sendActions(for: .touchUpInside)

        XCTAssertTrue(root.downloadsManager.rows.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))

        root.updateRailItems()
        let refreshed = try XCTUnwrap(railButton(labeled: "Clear All", in: root.railView))
        XCTAssertFalse(refreshed.isEnabled)
        root.dismissDownloadsSheet()
    }

    func testFilesButtonPresentsPicker() throws {
        let root = try makeRoot()
        root.presentDownloadsSheet()
        root.updateRailItems()

        let files = try XCTUnwrap(railButton(labeled: "Files", in: root.railView))
        files.sendActions(for: .touchUpInside)

        let picker = try XCTUnwrap(root.presentedDownloadsPicker)
        XCTAssertNotNil(picker)
        if let presented = root.presentedViewController {
            XCTAssertTrue(presented === picker)
        }
    }

    func testHostingCleanupRemovesView() throws {
        let root = try makeRoot()
        root.presentDownloadsSheet()
        let hosting = try XCTUnwrap(root.downloadsHosting)
        let hostedView: UIView = hosting.view
        XCTAssertTrue(hostedView.superview === root.downloadsContainer)

        root.dismissDownloadsSheet()

        XCTAssertNil(root.downloadsHosting)
        XCTAssertNil(hostedView.superview)
        XCTAssertNil(hosting.parent)
        XCTAssertTrue(root.downloadsContainer.isHidden)
    }

    func testPresentFromMenuDoesNotPresentModally() throws {
        let root = try makeRoot()
        root.presentDownloadsFromMenu()

        XCTAssertTrue(root.isDownloadsVisible)
        XCTAssertFalse(root.downloadsContainer.isHidden)
        XCTAssertNil(root.presentedViewController)

        root.dismissDownloadsSheet()
        XCTAssertNil(root.presentedViewController)
    }

    func testDownloadsContainerFillsDisplayEdgeToEdge() throws {
        let root = try makeRoot()
        root.view.layoutIfNeeded()
        XCTAssertEqual(root.downloadsContainer.frame, root.view.bounds)

        root.presentDownloadsSheet()
        root.view.layoutIfNeeded()

        XCTAssertEqual(root.downloadsContainer.frame, root.view.bounds)
        let hosting = try XCTUnwrap(root.downloadsHosting)
        XCTAssertTrue(hosting.view.superview === root.downloadsContainer)
        XCTAssertTrue(root.downloadsContainer.subviews.contains(hosting.view))
    }
}
