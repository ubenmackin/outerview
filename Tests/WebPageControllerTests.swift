//
//  WebPageControllerTests.swift
//  OuterView
//

@testable import OuterView
import XCTest

final class WebPageControllerTests: XCTestCase {
    private struct MappingCase {
        let name: String
        let url: URL?
        let title: String?
        let progress: Double
        let canGoBack: Bool
        let canGoForward: Bool
        let lastError: String?
        let hasFailedServerTrustChallenge: Bool
        let expectedIsSecure: Bool
    }

    func testSnapshotMappingDictionary() {
        let cases: [MappingCase] = [
            MappingCase(
                name: "https without a denied challenge is secure",
                url: URL(string: "https://example.com/"),
                title: "Example",
                progress: 1,
                canGoBack: false,
                canGoForward: false,
                lastError: nil,
                hasFailedServerTrustChallenge: false,
                expectedIsSecure: true
            ),
            MappingCase(
                name: "http fixture is not secure",
                url: URL(string: "http://fixture.local/page"),
                title: "Fixture",
                progress: 0.5,
                canGoBack: false,
                canGoForward: false,
                lastError: nil,
                hasFailedServerTrustChallenge: false,
                expectedIsSecure: false
            ),
            MappingCase(
                name: "a denied server-trust challenge makes https insecure",
                url: URL(string: "https://example.com/"),
                title: nil,
                progress: 0,
                canGoBack: false,
                canGoForward: false,
                lastError: nil,
                hasFailedServerTrustChallenge: true,
                expectedIsSecure: false
            ),
            MappingCase(
                name: "no url is never secure",
                url: nil,
                title: nil,
                progress: 0,
                canGoBack: false,
                canGoForward: false,
                lastError: nil,
                hasFailedServerTrustChallenge: false,
                expectedIsSecure: false
            ),
            MappingCase(
                name: "ftp is not secure",
                url: URL(string: "ftp://fixture.local/file"),
                title: nil,
                progress: 0,
                canGoBack: false,
                canGoForward: false,
                lastError: nil,
                hasFailedServerTrustChallenge: false,
                expectedIsSecure: false
            ),
            MappingCase(
                name: "scheme case is normalized",
                url: URL(string: "HTTPS://example.com/"),
                title: nil,
                progress: 0,
                canGoBack: false,
                canGoForward: false,
                lastError: nil,
                hasFailedServerTrustChallenge: false,
                expectedIsSecure: true
            ),
            MappingCase(
                name: "navigation state and error are carried through",
                url: URL(string: "https://example.com/"),
                title: "Example",
                progress: 0.75,
                canGoBack: true,
                canGoForward: true,
                lastError: "The request timed out.",
                hasFailedServerTrustChallenge: false,
                expectedIsSecure: true
            )
        ]

        for testCase in cases {
            let snapshot = WebPageSnapshot.make(
                url: testCase.url,
                title: testCase.title,
                progress: testCase.progress,
                canGoBack: testCase.canGoBack,
                canGoForward: testCase.canGoForward,
                lastError: testCase.lastError,
                hasFailedServerTrustChallenge: testCase.hasFailedServerTrustChallenge
            )
            let expected = WebPageSnapshot(
                url: testCase.url,
                title: testCase.title,
                progress: testCase.progress,
                canGoBack: testCase.canGoBack,
                canGoForward: testCase.canGoForward,
                isSecure: testCase.expectedIsSecure,
                lastError: testCase.lastError
            )
            XCTAssertEqual(snapshot, expected, testCase.name)
        }
    }

    func testIsSecureRule() {
        let https = URL(string: "https://example.com/")
        let http = URL(string: "http://example.com/")

        XCTAssertTrue(WebPageSnapshot.isSecure(url: https, hasFailedServerTrustChallenge: false))
        XCTAssertFalse(WebPageSnapshot.isSecure(url: http, hasFailedServerTrustChallenge: false))
        XCTAssertFalse(WebPageSnapshot.isSecure(url: https, hasFailedServerTrustChallenge: true))
        XCTAssertFalse(WebPageSnapshot.isSecure(url: nil, hasFailedServerTrustChallenge: false))
    }
}
