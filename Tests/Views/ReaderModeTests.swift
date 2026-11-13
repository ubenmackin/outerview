//
//  ReaderModeTests.swift
//  OuterView
//

@testable import OuterView
import XCTest

final class ReaderModeTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let name = "ReaderModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { [name] in
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        return defaults
    }

    private static func stubJSON(title: String, byline: String?, body: String) throws -> String {
        var payload: [String: Any] = [
            "title": title,
            "html": "<p>" + body + "</p>"
        ]
        payload["byline"] = byline ?? NSNull()
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private static func longBody() -> String {
        String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 8)
    }

    func testReadableArticleParsesTitleBylineAndBody() throws {
        let json = try Self.stubJSON(title: "Sample Article", byline: "By Jane Doe", body: Self.longBody())
        let article = try XCTUnwrap(ReaderMode.parsedArticle(from: json))
        XCTAssertEqual(article.title, "Sample Article")
        XCTAssertEqual(article.byline, "By Jane Doe")
        XCTAssertTrue(article.html.contains("Lorem ipsum"))
    }

    func testArticleWithoutBylineStillParses() throws {
        let json = try Self.stubJSON(title: "Sample Article", byline: nil, body: Self.longBody())
        let article = try XCTUnwrap(ReaderMode.parsedArticle(from: json))
        XCTAssertNil(article.byline)
    }

    func testShortPayloadIsNotReaderable() throws {
        let json = try Self.stubJSON(title: "Search", byline: nil, body: "Brief note.")
        XCTAssertNil(ReaderMode.parsedArticle(from: json))
        XCTAssertNil(ReaderMode.parsedArticle(from: nil))
        XCTAssertNil(ReaderMode.parsedArticle(from: ""))
        XCTAssertNil(ReaderMode.parsedArticle(from: "not-json"))
    }

    func testFontSizeClampsToBounds() {
        XCTAssertEqual(ReaderMode.clampedFontSize(13), 14)
        XCTAssertEqual(ReaderMode.clampedFontSize(29), 28)
        XCTAssertEqual(ReaderMode.clampedFontSize(14), 14)
        XCTAssertEqual(ReaderMode.clampedFontSize(28), 28)
        XCTAssertEqual(ReaderMode.clampedFontSize(20), 20)
        XCTAssertEqual(ReaderMode.defaultFontSize, 20)
    }

    func testScriptsCarryNamespaceThemeAndSize() {
        XCTAssertTrue(ReaderMode.extractionScript().contains("window.__outerviewReader"))

        let dark = ReaderMode.replaceBodyScript(theme: .dark, fontSize: 20)
        XCTAssertTrue(dark.contains(ReaderTheme.dark.backgroundHex))
        XCTAssertTrue(dark.contains(ReaderTheme.dark.foregroundHex))
        XCTAssertTrue(dark.contains("20px"))

        XCTAssertTrue(ReaderMode.replaceBodyScript(theme: .light, fontSize: 13).contains("14px"))
        XCTAssertTrue(ReaderMode.replaceBodyScript(theme: .light, fontSize: 29).contains("28px"))
    }

    @MainActor
    func testPreferencesRoundTripThroughDefaults() throws {
        let defaults = try makeDefaults()
        XCTAssertEqual(ReaderMode.storedTheme(defaults: defaults), .light)
        XCTAssertEqual(ReaderMode.storedFontSize(defaults: defaults), ReaderMode.defaultFontSize)

        ReaderMode.persist(theme: .sepia, defaults: defaults)
        ReaderMode.persist(fontSize: 24, defaults: defaults)
        XCTAssertEqual(ReaderMode.storedTheme(defaults: defaults), .sepia)
        XCTAssertEqual(ReaderMode.storedFontSize(defaults: defaults), 24)

        ReaderMode.persist(fontSize: 29, defaults: defaults)
        XCTAssertEqual(ReaderMode.storedFontSize(defaults: defaults), 28)

        defaults.set("unknown-theme", forKey: ReaderMode.themeDefaultsKey)
        XCTAssertEqual(ReaderMode.storedTheme(defaults: defaults), .light)
    }
}
