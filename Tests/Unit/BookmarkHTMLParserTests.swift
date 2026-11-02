//
//  BookmarkHTMLParserTests.swift
//  OuterView
//

@testable import OuterView
import XCTest

final class BookmarkHTMLParserTests: XCTestCase {
    func testFixtureParsesExpectedCounts() throws {
        let result = try BookmarkHTMLParser.parse(ImportFixtures.safariExport())
        XCTAssertEqual(result.bookmarks.count, 6)
        XCTAssertEqual(result.skippedInvalid, 1)
        XCTAssertEqual(result.truncated, 0)
    }

    func testFixtureTitlesUrlsAndOrder() throws {
        let result = try BookmarkHTMLParser.parse(ImportFixtures.safariExport())
        XCTAssertEqual(result.bookmarks.map(\.title), [
            "Long Article",
            "Nested Docs",
            "Deep Page",
            "News & Notes",
            "News & Notes Copy",
            "Top Direct"
        ])
        XCTAssertEqual(result.bookmarks.map(\.url.absoluteString), [
            "https://example.com/article&more",
            "https://outer.example.dev/deep",
            "https://deep.example.net/page",
            "https://news.example.org/home",
            "https://news.example.org/home",
            "https://top.example.io/direct"
        ])
    }

    func testFixtureFolderPaths() throws {
        let result = try BookmarkHTMLParser.parse(ImportFixtures.safariExport())
        XCTAssertEqual(result.bookmarks.first { $0.title == "Long Article" }?.folderPath, ["Reading"])
        XCTAssertEqual(result.bookmarks.first { $0.title == "Deep Page" }?.folderPath, ["Reading", "Inner"])
        XCTAssertEqual(result.bookmarks.first { $0.title == "News & Notes" }?.folderPath, ["Bookmarks Bar"])
        XCTAssertEqual(result.bookmarks.first { $0.title == "Top Direct" }?.folderPath, [])
    }

    func testFixtureAddDateParsesEpochSeconds() throws {
        let result = try BookmarkHTMLParser.parse(ImportFixtures.safariExport())
        let nested = try XCTUnwrap(result.bookmarks.first { $0.title == "Nested Docs" })
        XCTAssertEqual(nested.addedDate, Date(timeIntervalSince1970: 1_700_000_000))
        let undated = try XCTUnwrap(result.bookmarks.first { $0.title == "Long Article" })
        XCTAssertNil(undated.addedDate)
    }

    func testNonWebSchemesAreSkippedAndCounted() throws {
        let html = """
        <DL><p>
        <DT><A HREF="ftp://files.example.com/pub">Files</A>
        <DT><A HREF="mailto:hi@example.com">Mail</A>
        <DT><A HREF="https://kept.example.com/ok">Kept</A>
        </DL><p>
        """
        let result = try BookmarkHTMLParser.parse(html.data(using: .utf8) ?? Data())
        XCTAssertEqual(result.bookmarks.map(\.title), ["Kept"])
        XCTAssertEqual(result.skippedInvalid, 2)
    }

    func testTruncatesAtEntryLimitAndReportsOverflow() throws {
        var html = "<DL><p>\n"
        for index in 0 ..< 5002 {
            html += "<DT><A HREF=\"https://example.com/entry/\(index)\">Entry \(index)</A>\n"
        }
        html += "</DL><p>\n"
        let result = try BookmarkHTMLParser.parse(html.data(using: .utf8) ?? Data())
        XCTAssertEqual(result.bookmarks.count, 5000)
        XCTAssertEqual(result.truncated, 2)
        XCTAssertEqual(result.skippedInvalid, 0)
    }

    func testOversizeInputFailsWithFileTooLarge() {
        let payload = Data(repeating: 0x20, count: 10 * 1024 * 1024 + 1)
        XCTAssertThrowsError(try BookmarkHTMLParser.parse(payload)) { error in
            XCTAssertEqual(error as? BookmarkParseError, .fileTooLarge)
        }
    }

    func testMalformedInputYieldsNoBookmarksWithoutCrashing() throws {
        let garbage = Data([0xFF, 0xFE, 0x3C, 0x00, 0x93, 0x81])
        let result = try BookmarkHTMLParser.parse(garbage)
        XCTAssertEqual(result.bookmarks.count, 0)
        XCTAssertEqual(result.skippedInvalid, 0)
        let junk = try BookmarkHTMLParser.parse(Data("<<<<>> not a bookmark file".utf8))
        XCTAssertEqual(junk.bookmarks.count, 0)
    }
}
