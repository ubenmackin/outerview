//
//  URLNormalizerTests.swift
//  OuterView
//

@testable import OuterView
import XCTest

final class URLNormalizerTests: XCTestCase {
    private struct SuccessCase {
        let label: String
        let input: String
        let engine: SearchEngine
        let expected: String
    }

    private struct FailureCase {
        let label: String
        let input: String
        let expected: URLNormalizer.NormalizerFailure
    }

    private static let successTable: [SuccessCase] = [
        SuccessCase(
            label: "about:blank passes through",
            input: "about:blank",
            engine: .google,
            expected: "about:blank"
        ),
        SuccessCase(
            label: "about:blank survives surrounding whitespace",
            input: "  about:blank  ",
            engine: .google,
            expected: "about:blank"
        ),
        SuccessCase(
            label: "explicit http passes through",
            input: "http://example.com",
            engine: .google,
            expected: "http://example.com"
        ),
        SuccessCase(
            label: "explicit https with path passes through",
            input: "https://example.com/path?q=1",
            engine: .google,
            expected: "https://example.com/path?q=1"
        ),
        SuccessCase(
            label: "scheme-less dotted host gains https",
            input: "example.com",
            engine: .google,
            expected: "https://example.com"
        ),
        SuccessCase(
            label: "scheme-less input is trimmed before prefixing",
            input: "  example.com  ",
            engine: .google,
            expected: "https://example.com"
        ),
        SuccessCase(
            label: "scheme-less dotted path gains https",
            input: "example.com/path?q=1",
            engine: .google,
            expected: "https://example.com/path?q=1"
        ),
        SuccessCase(
            label: "spaced input routes to the configured engine",
            input: "hello world",
            engine: .google,
            expected: "https://google.com/search?q=hello%20world"
        ),
        SuccessCase(
            label: "spaced dotted input is still a search query",
            input: "example.com a",
            engine: .google,
            expected: "https://google.com/search?q=example.com%20a"
        ),
        SuccessCase(
            label: "dot-less word routes to search",
            input: "localhost",
            engine: .google,
            expected: "https://google.com/search?q=localhost"
        ),
        SuccessCase(
            label: "search query is trimmed before encoding",
            input: "  hello world  ",
            engine: .duckduckgo,
            expected: "https://duckduckgo.com/?q=hello%20world"
        ),
        SuccessCase(
            label: "duckduckgo base",
            input: "hello world",
            engine: .duckduckgo,
            expected: "https://duckduckgo.com/?q=hello%20world"
        ),
        SuccessCase(
            label: "bing base",
            input: "hello world",
            engine: .bing,
            expected: "https://bing.com/search?q=hello%20world"
        ),
        SuccessCase(
            label: "brave base",
            input: "hello world",
            engine: .brave,
            expected: "https://search.brave.com/search?q=hello%20world"
        ),
        SuccessCase(
            label: "reserved characters cannot alter the query structure",
            input: "a&b+c#d",
            engine: .google,
            expected: "https://google.com/search?q=a%26b%2Bc%23d"
        )
    ]

    private static let failureTable: [FailureCase] = [
        FailureCase(label: "empty string", input: "", expected: .empty),
        FailureCase(label: "whitespace only", input: "   \n\t ", expected: .empty),
        FailureCase(
            label: "raw input over 2048 chars",
            input: String(repeating: "a", count: 2049),
            expected: .tooLong
        ),
        FailureCase(
            label: "embedded control scalar",
            input: "exa\u{01}mple.com",
            expected: .invalidCharacters
        ),
        FailureCase(
            label: "trailing delete scalar",
            input: "example.com\u{7F}",
            expected: .invalidCharacters
        ),
        FailureCase(
            label: "ftp scheme",
            input: "ftp://files.example.com/pub",
            expected: .unsupportedScheme("ftp")
        ),
        FailureCase(
            label: "unsupported scheme lowercases before reporting",
            input: "FTP://files.example.com/pub",
            expected: .unsupportedScheme("ftp")
        ),
        FailureCase(
            label: "mailto scheme",
            input: "mailto:hi@example.com",
            expected: .unsupportedScheme("mailto")
        ),
        FailureCase(
            label: "only about:blank is a valid about page",
            input: "about:config",
            expected: .unsupportedScheme("about")
        ),
        FailureCase(
            label: "javascript scheme",
            input: "javascript:alert(1)",
            expected: .unsupportedScheme("javascript")
        ),
        FailureCase(
            label: "explicit https with a space cannot parse",
            input: "https://exa mple.com",
            expected: .malformed
        )
    ]

    func testSuccessTable() {
        for row in Self.successTable {
            let result = URLNormalizer.normalize(row.input, engine: row.engine)
            switch result {
            case let .success(url):
                XCTAssertEqual(url.absoluteString, row.expected, row.label)
            case let .failure(failure):
                XCTFail("\(row.label): expected success, got \(failure)")
            }
        }
    }

    func testFailureTable() {
        for row in Self.failureTable {
            let result = URLNormalizer.normalize(row.input, engine: .google)
            switch result {
            case let .success(url):
                XCTFail("\(row.label): expected \(row.expected), got \(url)")
            case let .failure(failure):
                XCTAssertEqual(failure, row.expected, row.label)
            }
        }
    }

    func testUppercaseSchemeIsAccepted() {
        let result = URLNormalizer.normalize("HTTPS://example.com/", engine: .google)
        switch result {
        case let .success(url):
            XCTAssertEqual(url.scheme?.lowercased(), "https")
            XCTAssertEqual(url.host?.lowercased(), "example.com")
        case let .failure(failure):
            XCTFail("expected success, got \(failure)")
        }
    }

    func testBoundaryLength() {
        let max = String(repeating: "a", count: 2048)
        switch URLNormalizer.normalize(max, engine: .google) {
        case .success:
            break
        case let .failure(failure):
            XCTFail("2048 chars should succeed, got \(failure)")
        }
        // The length rule applies to the raw input, before trimming.
        let padded = " " + max
        XCTAssertEqual(
            URLNormalizer.normalize(padded, engine: .google),
            .failure(.tooLong)
        )
    }

    func testColonWithoutSchemeMarkerRoutesToSearch() {
        let result = URLNormalizer.normalize("localhost:", engine: .google)
        switch result {
        case let .success(url):
            XCTAssertEqual(url.absoluteString, "https://google.com/search?q=localhost%3A")
        case let .failure(failure):
            XCTFail("expected search, got \(failure)")
        }
    }

    func testSearchEngineEncodingTable() {
        XCTAssertEqual(
            SearchEngine.google.searchURL("hello world").absoluteString,
            "https://google.com/search?q=hello%20world"
        )
        XCTAssertEqual(
            SearchEngine.duckduckgo.searchURL("hello world").absoluteString,
            "https://duckduckgo.com/?q=hello%20world"
        )
        XCTAssertEqual(
            SearchEngine.bing.searchURL("hello world").absoluteString,
            "https://bing.com/search?q=hello%20world"
        )
        XCTAssertEqual(
            SearchEngine.brave.searchURL("hello world").absoluteString,
            "https://search.brave.com/search?q=hello%20world"
        )
    }
}
