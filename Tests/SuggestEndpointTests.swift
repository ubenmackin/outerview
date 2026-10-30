//
//  SuggestEndpointTests.swift
//  OuterView
//

import Foundation
@testable import OuterView
import XCTest

final class SuggestEndpointTests: XCTestCase {
    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }

    func testGoogleSuggestURLEncodesQuery() {
        let url = GoogleSuggestService.suggestURL(for: .google, query: "hello world")
        XCTAssertEqual(
            url?.absoluteString,
            "https://suggestqueries.google.com/complete/search?client=safari&q=hello%20world"
        )
    }

    func testBingSuggestURLEncodesQuery() {
        let url = GoogleSuggestService.suggestURL(for: .bing, query: "hello world")
        XCTAssertEqual(url?.absoluteString, "https://api.bing.com/osjson.aspx?query=hello%20world")
    }

    func testDuckDuckGoSuggestURLEncodesQuery() {
        let url = GoogleSuggestService.suggestURL(for: .duckduckgo, query: "hello world")
        XCTAssertEqual(url?.absoluteString, "https://duckduckgo.com/ac/?q=hello%20world")
    }

    func testBraveSuggestURLIsNil() {
        XCTAssertNil(GoogleSuggestService.suggestURL(for: .brave, query: "hello world"))
    }

    func testSuggestURLEncodesReservedCharacters() {
        let url = GoogleSuggestService.suggestURL(for: .google, query: "a+b&c#d")
        XCTAssertEqual(
            url?.absoluteString,
            "https://suggestqueries.google.com/complete/search?client=safari&q=a%2Bb%26c%23d"
        )
    }

    func testSuggestURLRejectsBlankQuery() {
        XCTAssertNil(GoogleSuggestService.suggestURL(for: .google, query: "   "))
        XCTAssertNil(GoogleSuggestService.suggestURL(for: .bing, query: ""))
        XCTAssertNil(GoogleSuggestService.suggestURL(for: .duckduckgo, query: "  "))
    }

    func testParseGoogleOpenSearchStringArray() {
        let payload = data(#"["swift",["swift","swiftui tutorial","swift language"]]"#)
        XCTAssertEqual(
            GoogleSuggestService.parseSuggestions(payload, engine: .google),
            ["swift", "swiftui tutorial", "swift language"]
        )
    }

    func testParseBingOpenSearchStringArray() {
        let payload = data(#"["swift",["swift","swiftui tutorial"]]"#)
        XCTAssertEqual(
            GoogleSuggestService.parseSuggestions(payload, engine: .bing),
            ["swift", "swiftui tutorial"]
        )
    }

    func testParseGoogleSafariArrayOfArrays() {
        let payload = data(#"["test",[["test","",[512]],["testosterone","",[512]]]]"#)
        XCTAssertEqual(
            GoogleSuggestService.parseSuggestions(payload, engine: .google),
            ["test", "testosterone"]
        )
    }

    func testParseDuckDuckGoPhraseShape() {
        let payload = data(#"[{"phrase":"swift"},{"phrase":"swiftui tutorial"}]"#)
        XCTAssertEqual(
            GoogleSuggestService.parseSuggestions(payload, engine: .duckduckgo),
            ["swift", "swiftui tutorial"]
        )
    }

    func testParseDuckDuckGoSkipsBlankPhrases() {
        let payload = data(#"[{"phrase":"  "},{"phrase":"swift"},{"nope":1}]"#)
        XCTAssertEqual(GoogleSuggestService.parseSuggestions(payload, engine: .duckduckgo), ["swift"])
    }

    func testParseMalformedPayloadsYieldEmpty() {
        let invalid = data("not json")
        for engine in SearchEngine.allCases {
            XCTAssertEqual(
                GoogleSuggestService.parseSuggestions(invalid, engine: engine),
                [],
                "engine \(engine) should yield empty for invalid JSON"
            )
        }
        // OpenSearch shape carries no phrases, so DuckDuckGo yields empty.
        let openSearch = data(#"["swift",["swift"]]"#)
        XCTAssertEqual(GoogleSuggestService.parseSuggestions(openSearch, engine: .duckduckgo), [])
        // Phrase shape carries no OpenSearch rows, so Google yields empty.
        let phrases = data(#"[{"phrase":"swift"}]"#)
        XCTAssertEqual(GoogleSuggestService.parseSuggestions(phrases, engine: .google), [])
        XCTAssertEqual(GoogleSuggestService.parseSuggestions(phrases, engine: .bing), [])
    }

    func testParseBraveAlwaysEmpty() {
        let payload = data(#"["swift",["swift"]]"#)
        XCTAssertEqual(GoogleSuggestService.parseSuggestions(payload, engine: .brave), [])
    }

    func testRemoteSubtitleUsesEngineDisplayName() {
        for engine in SearchEngine.allCases {
            let suggestion = Suggestion(kind: .googleSuggest(query: "swift"))
            let viewModel = SuggestionRowViewModel.make(for: suggestion, engine: engine)
            XCTAssertEqual(viewModel.primary, "swift")
            XCTAssertEqual(viewModel.secondary, "\(engine.displayName) Suggestions")
        }
    }

    func testFetchBraveReturnsEmptyWithoutNetwork() async {
        let results = await GoogleSuggestService.shared.fetchSuggestions(for: "swift", engine: .brave)
        XCTAssertEqual(results, [])
    }

    func testFetchBlankQueryReturnsEmpty() async {
        let results = await GoogleSuggestService.shared.fetchSuggestions(for: "   ", engine: .google)
        XCTAssertEqual(results, [])
    }
}
