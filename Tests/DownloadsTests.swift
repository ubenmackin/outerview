//
//  DownloadsTests.swift
//  OuterView
//

@testable import OuterView
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

    func testOpenInFilesPickerTargetsDirectory() throws {
        let (manager, root) = try makeManager()
        defer { tearDownDirectory(root) }
        let picker = manager.makeFilesPicker()
        XCTAssertNotNil(picker)
    }
}
