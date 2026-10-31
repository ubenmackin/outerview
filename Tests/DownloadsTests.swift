//
//  DownloadsTests.swift
//  OuterView
//

@testable import OuterView
import UIKit
import WebKit
import XCTest

@MainActor
final class DownloadsTests: XCTestCase {
    private func makeManager() throws -> (DownloadsManager, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manager = DownloadsManager(directoryURL: root)
        return (manager, root)
    }

    private func tearDownDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func testDestinationCreatedOnInit() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
        let manager = DownloadsManager(directoryURL: root)
        XCTAssertEqual(manager.directoryURL, root)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        tearDownDirectory(root.deletingLastPathComponent())
    }

    func testDefaultInitUsesDocumentsDownloads() {
        let manager = DownloadsManager()
        XCTAssertEqual(manager.directoryURL.lastPathComponent, "Downloads")
        XCTAssertTrue(manager.directoryURL.path.contains("Documents"))
    }

    func testSanitizedFileNameMatrix() {
        let cases: [(input: String, expected: String)] = [
            ("report.pdf", "report.pdf"),
            ("a/b/report.pdf", "report.pdf"),
            ("/etc/passwd", "passwd"),
            ("a\\b\\report.pdf", "report.pdf"),
            ("", "download"),
            ("   ", "download"),
            ("///", "download"),
            ("..", "download"),
            (".", "download"),
            ("  spaced.pdf  ", "spaced.pdf"),
            ("a/b/../c.pdf", "c.pdf")
        ]
        for item in cases {
            XCTAssertEqual(DownloadsManager.sanitizedFileName(item.input), item.expected, "input: \(item.input)")
        }
        XCTAssertEqual(DownloadsManager.sanitizedFileName("/"), "download")
    }

    func testCollisionMatrix() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }

        // No collision returns the plain name.
        let first = DownloadsManager.uniqueDestinationURL(for: "photo.jpg", in: root)
        XCTAssertEqual(first.lastPathComponent, "photo.jpg")

        // Existing file on disk increments.
        try Data("one".utf8).write(to: root.appendingPathComponent("photo.jpg"))
        let second = DownloadsManager.uniqueDestinationURL(for: "photo.jpg", in: root)
        XCTAssertEqual(second.lastPathComponent, "photo (2).jpg")
        try Data("two".utf8).write(to: second)
        let third = DownloadsManager.uniqueDestinationURL(for: "photo.jpg", in: root)
        XCTAssertEqual(third.lastPathComponent, "photo (3).jpg")

        // Extensionless names increment without a trailing dot.
        try Data("a".utf8).write(to: root.appendingPathComponent("README"))
        let readmeTwo = DownloadsManager.uniqueDestinationURL(for: "README", in: root)
        XCTAssertEqual(readmeTwo.lastPathComponent, "README (2)")

        // Reserved in-flight names (tracked by the manager) also collide.
        let reserved = Set(["movie.mp4"])
        let reservedNext = DownloadsManager.uniqueDestinationURL(
            for: "movie.mp4",
            in: root,
            reservedNames: reserved
        )
        XCTAssertEqual(reservedNext.lastPathComponent, "movie (2).mp4")

        // Manager-level reservation: two rows with the same suggested name get distinct IDs.
        let rowA = manager.registerRow(
            name: "doc.pdf",
            fileURL: root.appendingPathComponent("doc.pdf")
        )
        XCTAssertFalse(rowA.uuidString.isEmpty)
        let diverged = manager.registerRow(
            name: "doc.pdf",
            fileURL: root.appendingPathComponent("doc.pdf")
        )
        XCTAssertNotEqual(rowA, diverged)
    }

    func testRowStateTransitionsFromStubbedProgress() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }

        let fileURL = root.appendingPathComponent("archive.zip")
        try Data(repeating: 7, count: 2048).write(to: fileURL)
        let id = manager.registerRow(name: "archive.zip", fileURL: fileURL)

        manager.applyProgress(0.25, for: id)
        XCTAssertEqual(manager.rows.first(where: { $0.id == id })?.progress, 0.25)
        XCTAssertEqual(manager.rows.first(where: { $0.id == id })?.state, .inProgress)

        manager.applyProgress(2.5, for: id)
        XCTAssertEqual(manager.rows.first(where: { $0.id == id })?.progress, 1.0)

        // Negatives clamp to zero.
        let secondID = manager.registerRow(name: "second.bin", fileURL: nil)
        manager.applyProgress(-0.5, for: secondID)
        XCTAssertEqual(manager.rows.first(where: { $0.id == secondID })?.progress, 0.0)

        // Progress after completion is ignored.
        manager.completeDownload(id: id)
        let finished = try XCTUnwrap(manager.rows.first(where: { $0.id == id }))
        XCTAssertEqual(finished.state, .finished)
        XCTAssertEqual(finished.progress, 1.0)
        XCTAssertFalse(finished.sizeLabel.isEmpty)
        manager.applyProgress(0.1, for: id)
        XCTAssertEqual(manager.rows.first(where: { $0.id == id })?.progress, 1.0)

        // Failure rows carry the reason.
        manager.failDownload(id: secondID, reason: "The network connection was lost.")
        XCTAssertEqual(
            manager.rows.first(where: { $0.id == id })?.state,
            .finished
        )
        XCTAssertEqual(
            manager.rows.first(where: { $0.id == secondID })?.state,
            .failed("The network connection was lost.")
        )
    }

    func testFixtureDownloadLandsWithCorrectNameAndSize() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }

        let payload = Data("fixture-bytes".utf8)
        let destination = DownloadsManager.uniqueDestinationURL(for: "fixture.bin", in: root)
        try payload.write(to: destination)
        let id = manager.registerRow(name: destination.lastPathComponent, fileURL: destination)
        manager.applyProgress(0.5, for: id)
        manager.completeDownload(id: id)

        let row = try XCTUnwrap(manager.rows.first(where: { $0.id == id }))
        XCTAssertEqual(row.name, "fixture.bin")
        XCTAssertEqual(row.state, .finished)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual(attributes[.size] as? Int, payload.count)
        XCTAssertEqual(row.sizeLabel, DownloadsManager.formattedSize(byteCount: payload.count))
    }

    func testDeleteRemovesFileAndRow() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }

        let destination = root.appendingPathComponent("trash.txt")
        try Data("bye".utf8).write(to: destination)
        let id = manager.registerRow(name: "trash.txt", fileURL: destination)
        manager.delete(id: id)
        XCTAssertNil(manager.rows.first(where: { $0.id == id }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testDeleteAllClearsRows() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }

        let first = manager.registerRow(name: "a.zip", fileURL: nil)
        manager.applyProgress(0.4, for: first)
        let second = manager.registerRow(name: "b.zip", fileURL: nil)
        manager.completeDownload(id: second)
        let third = manager.registerRow(name: "c.zip", fileURL: nil)
        manager.failDownload(id: third, reason: "lost")
        XCTAssertEqual(manager.rows.count, 3)

        manager.deleteAll()

        XCTAssertTrue(manager.rows.isEmpty)
        XCTAssertNil(manager.overallProgress)
    }

    func testDeleteAllCancelsInProgressAndRemovesFiles() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }

        let activeURL = root.appendingPathComponent("active.bin")
        try Data(repeating: 3, count: 1024).write(to: activeURL)
        let active = manager.registerRow(name: "active.bin", fileURL: activeURL)
        manager.applyProgress(0.5, for: active)
        XCTAssertEqual(manager.rows.first(where: { $0.id == active })?.state, .inProgress)

        let finishedURL = root.appendingPathComponent("done.bin")
        try Data(repeating: 9, count: 512).write(to: finishedURL)
        let finished = manager.registerRow(name: "done.bin", fileURL: finishedURL)
        manager.completeDownload(id: finished)

        manager.deleteAll()

        XCTAssertTrue(manager.rows.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: activeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: finishedURL.path))
        XCTAssertNil(manager.overallProgress)
    }

    func testDeleteAllWhenEmptyKeepsRowsEmpty() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }
        XCTAssertTrue(manager.rows.isEmpty)
        manager.deleteAll()
        XCTAssertTrue(manager.rows.isEmpty)
        XCTAssertNil(manager.overallProgress)
    }

    func testOpenInFilesPickerTargetsDirectory() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }
        let picker = manager.makeFilesPicker()
        XCTAssertNotNil(picker)
    }

    func testDownloadTakeover102SuppressesError() {
        let controller = WebPageController(configuration: WKWebViewConfiguration())
        // Download handovers interrupt the provisional load; the page stays visible.
        let error = NSError(
            domain: "WebKitErrorDomain",
            code: 102,
            userInfo: [NSLocalizedDescriptionKey: "Frame load interrupted by policy change"]
        )
        let webView = controller.webView
        controller.webView(webView, didFailProvisionalNavigation: nil, withError: error)
        XCTAssertNil(controller.snapshot.lastError)
        XCTAssertNil(controller.snapshot.lastErrorCode)
    }

    func testCancellationSuppressesError() {
        let controller = WebPageController(configuration: WKWebViewConfiguration())
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCancelled,
            userInfo: [NSLocalizedDescriptionKey: "cancelled"]
        )
        let webView = controller.webView
        controller.webView(webView, didFailProvisionalNavigation: nil, withError: error)
        XCTAssertNil(controller.snapshot.lastError)
        XCTAssertNil(controller.snapshot.lastErrorCode)
    }

    func testGenuineFailureSurfacesError() {
        let controller = WebPageController(configuration: WKWebViewConfiguration())
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [NSLocalizedDescriptionKey: "timed out"]
        )
        let webView = controller.webView
        controller.webView(webView, didFailProvisionalNavigation: nil, withError: error)
        XCTAssertNotNil(controller.snapshot.lastError)
        XCTAssertEqual(controller.snapshot.lastErrorCode, NSURLErrorTimedOut)
    }

    func testFileSharingEnabled() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool, true)
    }

    func testOverallProgressNilWhenEmpty() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }
        XCTAssertNil(manager.overallProgress)
    }

    func testOverallProgressNilWhenAllFinished() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }
        let id = manager.registerRow(name: "a.zip", fileURL: nil)
        manager.applyProgress(0.9, for: id)
        manager.completeDownload(id: id)
        XCTAssertNil(manager.overallProgress)
    }

    func testOverallProgressSingleRow() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }
        let id = manager.registerRow(name: "a.zip", fileURL: nil)
        manager.applyProgress(0.4, for: id)
        XCTAssertEqual(manager.overallProgress ?? -1, 0.4, accuracy: 0.001)
    }

    func testOverallProgressMeanAcrossRows() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }
        let first = manager.registerRow(name: "a.zip", fileURL: nil)
        let second = manager.registerRow(name: "b.zip", fileURL: nil)
        manager.applyProgress(0.2, for: first)
        manager.applyProgress(0.8, for: second)
        XCTAssertEqual(manager.overallProgress ?? -1, 0.5, accuracy: 0.001)
    }

    func testOverallProgressExcludesFinishedAndFailed() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }
        let active = manager.registerRow(name: "active.zip", fileURL: nil)
        let finished = manager.registerRow(name: "done.zip", fileURL: nil)
        let failed = manager.registerRow(name: "bad.zip", fileURL: nil)
        manager.applyProgress(0.6, for: active)
        manager.applyProgress(0.9, for: finished)
        manager.applyProgress(0.9, for: failed)
        manager.completeDownload(id: finished)
        manager.failDownload(id: failed, reason: "lost")
        XCTAssertEqual(manager.overallProgress ?? -1, 0.6, accuracy: 0.001)
    }

    func testDownloadRingReplacesReloadWhenIdle() {
        let pill = AddressBarView(frame: CGRect(x: 0, y: 0, width: 360, height: 44))
        TestWindow.attach(pill)
        pill.configure(url: URL(string: "https://example.com"), isSecure: true, isLoading: false)
        XCTAssertFalse(pill.isDownloadRingVisible)
        XCTAssertEqual(pill.actionAccessibilityLabel, "Reload page")
        pill.configureDownloadProgress(0.5)
        XCTAssertTrue(pill.isDownloadRingVisible)
        XCTAssertFalse(pill.isActionButtonVisible)
        XCTAssertEqual(pill.downloadProgress ?? -1, 0.5, accuracy: 0.001)
    }

    func testLoadingTakesPrecedenceOverRing() {
        let pill = AddressBarView(frame: CGRect(x: 0, y: 0, width: 360, height: 44))
        TestWindow.attach(pill)
        pill.configure(url: URL(string: "https://example.com"), isSecure: true, isLoading: true)
        pill.configureDownloadProgress(0.5)
        XCTAssertFalse(pill.isDownloadRingVisible)
        XCTAssertTrue(pill.isActionButtonVisible)
        XCTAssertEqual(pill.actionAccessibilityLabel, "Stop loading")
    }

    func testRingTapForwardsToDownloads() {
        let pill = AddressBarView(frame: CGRect(x: 0, y: 0, width: 360, height: 44))
        TestWindow.attach(pill)
        pill.configure(url: URL(string: "https://example.com"), isSecure: true, isLoading: false)
        var tapped = false
        pill.onDownloadsTap = { tapped = true }
        pill.configureDownloadProgress(0.3)
        XCTAssertTrue(pill.isDownloadRingVisible)
        guard let button = findDownloadsButton(in: pill) else {
            XCTFail("Downloads button not found")
            return
        }
        button.sendActions(for: .touchUpInside)
        XCTAssertTrue(tapped)
    }

    func testCompletionRestoresReload() {
        let pill = AddressBarView(frame: CGRect(x: 0, y: 0, width: 360, height: 44))
        TestWindow.attach(pill)
        pill.configure(url: URL(string: "https://example.com"), isSecure: true, isLoading: false)
        pill.configureDownloadProgress(0.8)
        XCTAssertTrue(pill.isDownloadRingVisible)
        pill.configureDownloadProgress(nil)
        XCTAssertFalse(pill.isDownloadRingVisible)
        XCTAssertTrue(pill.isActionButtonVisible)
        XCTAssertEqual(pill.actionAccessibilityLabel, "Reload page")
    }

    func testDownloadRingSize() {
        XCTAssertEqual(AddressBarView.downloadRingSize, 24)
    }

    func testRootUpdateDownloadProgressDrivesPill() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        TestWindow.attach(root)
        root.updateDownloadProgress()
        XCTAssertFalse(root.pillView.isDownloadRingVisible)
        XCTAssertNotNil(root.pillView.onDownloadsTap)
        let id = root.downloadsManager.registerRow(name: "a.zip", fileURL: nil)
        root.downloadsManager.applyProgress(0.5, for: id)
        root.updateDownloadProgress()
        XCTAssertTrue(root.pillView.isDownloadRingVisible)
        XCTAssertEqual(root.pillView.downloadProgress ?? -1, 0.5, accuracy: 0.001)
        root.downloadsManager.completeDownload(id: id)
        root.updateDownloadProgress()
        XCTAssertFalse(root.pillView.isDownloadRingVisible)
        XCTAssertEqual(root.pillView.actionAccessibilityLabel, "Reload page")
    }

    private func findDownloadsButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityLabel == "Downloads" {
            return button
        }
        for subview in view.subviews {
            if let found = findDownloadsButton(in: subview) {
                return found
            }
        }
        return nil
    }
}
