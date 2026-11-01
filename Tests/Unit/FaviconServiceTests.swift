//
//  FaviconServiceTests.swift
//  OuterView
//

@testable import OuterView
import XCTest

@MainActor
final class FaviconServiceTests: XCTestCase {
    func testMonogramGeneration() {
        let service = FaviconService.shared
        let image = service.generateMonogram(for: "apple.com", size: 88)
        XCTAssertEqual(image.size.width, 88)
        XCTAssertEqual(image.size.height, 88)
    }

    func testCachedFaviconOrMonogramReturnsImmediately() throws {
        let service = FaviconService.shared
        let url = try XCTUnwrap(URL(string: "https://apple.com"))
        let image = service.cachedFaviconOrMonogram(for: url, size: 76)
        XCTAssertEqual(image.size.width, 76)
        XCTAssertEqual(image.size.height, 76)
    }

    func testCachedFaviconOrMonogramWithHostlessURLReturnsMonogram() throws {
        let service = FaviconService.shared
        let url = try XCTUnwrap(URL(string: "about:blank"))
        let image = service.cachedFaviconOrMonogram(for: url, size: 44)
        XCTAssertEqual(image.size.width, 44)
        XCTAssertEqual(image.size.height, 44)
    }
}
