//
//  WebPageControllerTests.swift
//  OuterView
//

@testable import OuterView
import WebKit
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
                lastError: testCase.lastError,
                lastErrorCode: nil,
                hasFailedServerTrustChallenge: testCase.hasFailedServerTrustChallenge
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

    func testWebPageErrorKindMapping() {
        let offline = WebPageError.make(
            code: NSURLErrorNotConnectedToInternet,
            hasFailedServerTrustChallenge: false,
            detail: "offline"
        )
        XCTAssertEqual(offline.kind, .offline)
        let offlineLiteral = WebPageError.make(code: -1009, hasFailedServerTrustChallenge: false, detail: "offline")
        XCTAssertEqual(offlineLiteral.kind, .offline)
        let offlinePrecedence = WebPageError.make(
            code: NSURLErrorNotConnectedToInternet,
            hasFailedServerTrustChallenge: true,
            detail: "offline"
        )
        XCTAssertEqual(offlinePrecedence.kind, .offline)
        let trustNilCode = WebPageError.make(code: nil, hasFailedServerTrustChallenge: true, detail: "trust")
        XCTAssertEqual(trustNilCode.kind, .serverTrust)
        let trustCertCode = WebPageError.make(
            code: NSURLErrorServerCertificateUntrusted,
            hasFailedServerTrustChallenge: true,
            detail: "trust"
        )
        XCTAssertEqual(trustCertCode.kind, .serverTrust)
        let trustOtherCode = WebPageError.make(
            code: NSURLErrorTimedOut,
            hasFailedServerTrustChallenge: true,
            detail: "trust"
        )
        XCTAssertEqual(trustOtherCode.kind, .serverTrust)
        let otherNil = WebPageError.make(code: nil, hasFailedServerTrustChallenge: false, detail: "other")
        XCTAssertEqual(otherNil.kind, .other)
        let otherTimeout = WebPageError.make(
            code: NSURLErrorTimedOut,
            hasFailedServerTrustChallenge: false,
            detail: "other"
        )
        XCTAssertEqual(otherTimeout.kind, .other)
        let certCodeWithoutFlag = WebPageError.make(
            code: NSURLErrorServerCertificateUntrusted,
            hasFailedServerTrustChallenge: false,
            detail: "other"
        )
        XCTAssertEqual(certCodeWithoutFlag.kind, .other)
    }

    func testWebPageErrorTitleAndDetail() {
        let offline = WebPageError.make(
            code: NSURLErrorNotConnectedToInternet,
            hasFailedServerTrustChallenge: false,
            detail: "The Internet connection appears to be offline.",
            url: URL(string: "https://example.com/page")
        )
        XCTAssertEqual(offline.title, "Can't Connect to example.com")
        XCTAssertEqual(offline.detail, "The Internet connection appears to be offline.")
        XCTAssertEqual(offline.code, NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(offline.hint, "Check your connection and try again.")
        XCTAssertEqual(offline.kind.systemImageName, "wifi.exclamationmark")
        let offlineNoHost = WebPageError.make(
            code: NSURLErrorNotConnectedToInternet,
            hasFailedServerTrustChallenge: false,
            detail: "offline",
            url: nil
        )
        XCTAssertEqual(offlineNoHost.title, "Can't Connect")
        let trust = WebPageError.make(
            code: NSURLErrorServerCertificateUntrusted,
            hasFailedServerTrustChallenge: true,
            detail: "The certificate is not trusted.",
            url: URL(string: "https://example.com")
        )
        XCTAssertEqual(trust.title, "Can't Verify Server")
        XCTAssertEqual(trust.detail, "The certificate is not trusted.")
        XCTAssertEqual(trust.kind.systemImageName, "exclamationmark.shield")
        XCTAssertNil(trust.hint)
        let other = WebPageError.make(
            code: nil,
            hasFailedServerTrustChallenge: false,
            detail: "boom",
            url: URL(string: "https://example.com")
        )
        XCTAssertEqual(other.title, "Something Went Wrong")
        XCTAssertEqual(other.code, 0)
        XCTAssertEqual(other.kind.systemImageName, "xmark")
        XCTAssertNil(other.hint)
        let trimmed = WebPageError.make(
            code: nil,
            hasFailedServerTrustChallenge: false,
            detail: "  hello  ",
            url: nil
        )
        XCTAssertEqual(trimmed.detail, "hello")
        let fallback = WebPageError.make(code: nil, hasFailedServerTrustChallenge: false, detail: nil, url: nil)
        XCTAssertFalse(fallback.detail.isEmpty)
        let offlineFallback = WebPageError.make(
            code: NSURLErrorNotConnectedToInternet,
            hasFailedServerTrustChallenge: false,
            detail: "   ",
            url: nil
        )
        XCTAssertFalse(offlineFallback.detail.isEmpty)
        let trustFallback = WebPageError.make(
            code: nil,
            hasFailedServerTrustChallenge: true,
            detail: nil,
            url: nil
        )
        XCTAssertFalse(trustFallback.detail.isEmpty)
        XCTAssertTrue(other.copySummary.contains(other.detail))
        XCTAssertTrue(other.copySummary.contains("\(other.code)"))
        XCTAssertTrue(offline.copySummary.contains(offline.title))
    }

    func testSnapshotCarriesErrorCodeAndTrustFlag() {
        let snapshot = WebPageSnapshot.make(
            url: URL(string: "https://example.com/"),
            title: nil,
            progress: 0,
            canGoBack: false,
            canGoForward: false,
            lastError: "failure",
            hasFailedServerTrustChallenge: true,
            lastErrorCode: NSURLErrorNotConnectedToInternet
        )
        XCTAssertEqual(snapshot.lastErrorCode, NSURLErrorNotConnectedToInternet)
        XCTAssertTrue(snapshot.hasFailedServerTrustChallenge)
        XCTAssertFalse(snapshot.isSecure)
        let clean = WebPageSnapshot.make(
            url: URL(string: "https://example.com/"),
            title: nil,
            progress: 1,
            canGoBack: false,
            canGoForward: false,
            lastError: nil,
            hasFailedServerTrustChallenge: false
        )
        XCTAssertNil(clean.lastErrorCode)
        XCTAssertFalse(clean.hasFailedServerTrustChallenge)
    }

    func testFindCountsParsingFromJSContract() {
        let counts = WebPageController.parsedFindCounts(from: "{\"total\":5,\"index\":2}")
        XCTAssertEqual(counts.total, 5)
        XCTAssertEqual(counts.index, 2)

        XCTAssertEqual(WebPageController.parsedFindTotal(from: "{\"total\":3,\"index\":1}"), 3)
        XCTAssertEqual(WebPageController.parsedFindIndex(from: "{\"total\":3,\"index\":1}"), 1)

        let empty = WebPageController.parsedFindCounts(from: "{\"total\":0,\"index\":0}")
        XCTAssertEqual(empty.total, 0)
        XCTAssertEqual(empty.index, 0)

        XCTAssertEqual(WebPageController.parsedFindCounts(from: nil).total, 0)
        XCTAssertEqual(WebPageController.parsedFindCounts(from: "not-json").total, 0)
        XCTAssertEqual(WebPageController.parsedFindCounts(from: "").index, 0)
    }

    @MainActor
    func testFindEmptyQueryReturnsZeroAndClearIsNoop() async {
        let controller = WebPageController(configuration: WKWebViewConfiguration())
        let emptyTotal = await controller.findText("")
        XCTAssertEqual(emptyTotal, 0)
        let blankTotal = await controller.findText("   ")
        XCTAssertEqual(blankTotal, 0)
        await controller.clearFind()
    }

    @MainActor
    func testBackForwardNavigationGesturesEnabledOnInit() {
        let controller = WebPageController(configuration: WKWebViewConfiguration())
        XCTAssertTrue(controller.webView.allowsBackForwardNavigationGestures)
        #if DEBUG
            XCTAssertTrue(controller.webView.isInspectable)
        #endif
    }
}
