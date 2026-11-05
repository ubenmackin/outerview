// Downloads — Sheet layout and toolbar verification.

@testable import OuterView
import SwiftUI
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

    private func railItems(in rail: SideRailView) -> [UIBarButtonItem] {
        rail.subviews
            .compactMap { $0 as? UIStackView }
            .flatMap { $0.arrangedSubviews.compactMap { $0 as? UIToolbar } }
            .compactMap(\.items)
            .flatMap(\.self)
    }

    private func railItem(labeled label: String, in rail: SideRailView) -> UIBarButtonItem? {
        railItems(in: rail).first(where: { $0.accessibilityLabel == label })
    }

    /// Fires the mapped bar action through a control so the UIAction
    /// handler path runs instead of calling the root directly.
    private func fire(_ item: UIBarButtonItem) async {
        guard let action = item.primaryAction else { return }
        let control = UIControl()
        control.addAction(action, for: .touchUpInside)
        control.sendActions(for: .touchUpInside)
        await Task.yield()
        await Task.yield()
    }

    private func waitForClearAllAlert(in root: BrowserRootViewController) async -> UIAlertController? {
        let deadline = Date(timeIntervalSinceNow: 5.0)
        while Date() < deadline {
            if let alert = root.clearAllConfirmationAlert,
               !alert.isBeingPresented, !alert.isBeingDismissed
            {
                return alert
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if let alert = root.clearAllConfirmationAlert, !alert.isBeingPresented {
            return alert
        }
        return nil
    }

    private func waitForClearAllDismissed(in root: BrowserRootViewController) async -> Bool {
        let deadline = Date(timeIntervalSinceNow: 5.0)
        while Date() < deadline {
            if root.clearAllConfirmationAlert == nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return root.clearAllConfirmationAlert == nil
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

        let labels = railItems(in: root.railView).compactMap(\.accessibilityLabel)
        XCTAssertTrue(labels.contains("Files"))
        XCTAssertTrue(labels.contains("Clear All"))
        XCTAssertTrue(labels.contains("Done"))
        root.dismissDownloadsSheet()
    }

    func testClearDisabledWhenRowsEmpty() throws {
        let root = try makeRoot()
        XCTAssertTrue(root.downloadsManager.rows.isEmpty)
        root.presentDownloadsSheet()
        root.updateRailItems()

        let clear = try XCTUnwrap(railItem(labeled: "Clear All", in: root.railView))
        XCTAssertFalse(clear.isEnabled)
        root.dismissDownloadsSheet()
    }

    func testClearEnabledWhenRowsNonEmpty() throws {
        let root = try makeRoot()
        _ = root.downloadsManager.registerRow(name: "a.zip", fileURL: nil)
        root.presentDownloadsSheet()
        root.updateRailItems()

        let clear = try XCTUnwrap(railItem(labeled: "Clear All", in: root.railView))
        XCTAssertTrue(clear.isEnabled)
        root.dismissDownloadsSheet()
    }

    func testDoneButtonDismissesSheet() async throws {
        let root = try makeRoot()
        root.presentDownloadsSheet()
        root.updateRailItems()

        // System owns tap elasticity; firing the mapped Done closes the sheet.
        let done = try XCTUnwrap(railItem(labeled: "Done", in: root.railView))
        XCTAssertNotNil(done.primaryAction)
        await fire(done)

        XCTAssertFalse(root.isDownloadsVisible)
        XCTAssertTrue(root.downloadsContainer.isHidden)
        XCTAssertNil(root.downloadsHosting)
    }

    func testClearAllEmptiesRowsAndFiles() async throws {
        let root = try makeRoot()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Sheet dialog gate: confirm deletes, cancel keeps.
        let sheetFirstURL = tempDir.appendingPathComponent("sheet-first.bin")
        try Data(repeating: 1, count: 256).write(to: sheetFirstURL)
        _ = root.downloadsManager.registerRow(name: "sheet-first.bin", fileURL: sheetFirstURL)
        let sheetSecondURL = tempDir.appendingPathComponent("sheet-second.bin")
        try Data(repeating: 2, count: 256).write(to: sheetSecondURL)
        let sheetSecond = root.downloadsManager.registerRow(name: "sheet-second.bin", fileURL: sheetSecondURL)
        root.downloadsManager.applyProgress(0.5, for: sheetSecond)
        XCTAssertEqual(root.downloadsManager.rows.count, 2)

        root.presentDownloadsSheet()
        let sheetHosting = try XCTUnwrap(root.downloadsHosting as? UIHostingController<DownloadsSheetView>)
        XCTAssertNotNil(sheetHosting.rootView.onClearAll)
        var sheet = sheetHosting.rootView
        XCTAssertFalse(sheet.isShowingClearAllConfirm)
        // Confirm without a request never deletes.
        sheet.confirmClearAll()
        XCTAssertEqual(root.downloadsManager.rows.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sheetFirstURL.path))
        // Cancel keeps rows and files.
        sheet.requestClearAllConfirmation()
        XCTAssertTrue(sheet.isShowingClearAllConfirm)
        sheet.cancelClearAll()
        XCTAssertFalse(sheet.isShowingClearAllConfirm)
        XCTAssertEqual(root.downloadsManager.rows.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sheetFirstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sheetSecondURL.path))
        // Confirm empties rows and files.
        sheet.requestClearAllConfirmation()
        sheet.confirmClearAll()
        XCTAssertTrue(root.downloadsManager.rows.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sheetFirstURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sheetSecondURL.path))
        root.dismissDownloadsSheet()

        // Rail action-sheet gate: cancel keeps, confirm deletes.
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

        // Mapped Clear All prompts instead of deleting outright.
        let clear = try XCTUnwrap(railItem(labeled: "Clear All", in: root.railView))
        XCTAssertTrue(clear.isEnabled)
        await fire(clear)

        let pendingAlert = await waitForClearAllAlert(in: root)
        let pending = try XCTUnwrap(pendingAlert)
        XCTAssertEqual(pending.title, "Clear All Downloads?")
        XCTAssertEqual(pending.message, "This deletes all downloads and their files.")
        let pendingTitles = pending.actions.compactMap(\.title)
        XCTAssertTrue(pendingTitles.contains("Clear All"))
        XCTAssertTrue(pendingTitles.contains("Cancel"))
        XCTAssertEqual(pending.actions.first(where: { $0.title == "Clear All" })?.style, .destructive)
        XCTAssertEqual(root.downloadsManager.rows.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))

        // Cancel keeps rows and files.
        root.cancelPresentedClearAllDownloads()
        let cancelDismissed = await waitForClearAllDismissed(in: root)
        XCTAssertTrue(cancelDismissed)
        XCTAssertEqual(root.downloadsManager.rows.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))

        // Confirm deletes rows and files.
        root.updateRailItems()
        let retry = try XCTUnwrap(railItem(labeled: "Clear All", in: root.railView))
        await fire(retry)
        let confirmingAlert = await waitForClearAllAlert(in: root)
        let confirming = try XCTUnwrap(confirmingAlert)
        XCTAssertEqual(confirming.title, "Clear All Downloads?")
        root.confirmPresentedClearAllDownloads()
        let confirmDismissed = await waitForClearAllDismissed(in: root)
        XCTAssertTrue(confirmDismissed)
        XCTAssertTrue(root.downloadsManager.rows.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))

        root.updateRailItems()
        let refreshed = try XCTUnwrap(railItem(labeled: "Clear All", in: root.railView))
        XCTAssertFalse(refreshed.isEnabled)
        root.dismissDownloadsSheet()
    }

    func testFilesButtonPresentsPicker() async throws {
        let root = try makeRoot()
        root.presentDownloadsSheet()
        root.updateRailItems()

        // Mapped Files opener records the picker for the test host.
        let files = try XCTUnwrap(railItem(labeled: "Files", in: root.railView))
        XCTAssertNotNil(files.primaryAction)
        await fire(files)

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
