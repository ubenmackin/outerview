//
//  SmokeTests.swift
//  OuterView
//

@testable import OuterView
import XCTest

final class SmokeTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }

    @MainActor
    func testOpenExternalURL() throws {
        let root = BrowserRootViewController()
        TestWindow.attach(root)
        let url = try XCTUnwrap(URL(string: "outerview://open?url=https://apple.com"))
        root.openExternalURL(url)
        XCTAssertNotNil(root.activePage())
    }
}
