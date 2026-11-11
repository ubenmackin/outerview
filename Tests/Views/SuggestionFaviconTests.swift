// Chrome — Suggestion favicon sizing, symbol rows, and reuse tests.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class SuggestionFaviconTests: XCTestCase {
    private func makeURL(_ string: String) -> URL {
        guard let result = URL(string: string) else {
            XCTFail("invalid URL: \(string)")
            return URL(fileURLWithPath: "/")
        }
        return result
    }

    private func makeCell() -> SuggestionCell {
        SuggestionCell(style: .default, reuseIdentifier: SuggestionCell.reuseIdentifier)
    }

    func testSiteRowShowsSizedPlaceholder() throws {
        let cell = makeCell()
        let siteURL = makeURL("https://inline-autocomplete-placeholder-test.invalid/")
        let site = Suggestion(kind: .site(title: "Example", url: siteURL, isFavorite: false))
        cell.configure(for: site, engine: .google, isPrivate: false)
        let image = try XCTUnwrap(cell.faviconImageForTesting)
        XCTAssertEqual(image.size.width, SuggestionCell.faviconLength)
        XCTAssertEqual(image.size.height, SuggestionCell.faviconLength)
        // Full-color monograms ignore tint, which inherits from the hierarchy.
        XCTAssertNotEqual(cell.faviconTintForTesting, .secondaryLabel)
        XCTAssertEqual(cell.boundURLForTesting, siteURL)
        XCTAssertTrue(cell.hasFaviconTaskForTesting)
        cell.prepareForReuse()
    }

    func testSearchRowUsesSymbolWithoutFaviconTask() throws {
        let cell = makeCell()
        let search = Suggestion(kind: .search(query: "hello"))
        cell.configure(for: search, engine: .google, isPrivate: false)
        XCTAssertFalse(cell.hasFaviconTaskForTesting)
        XCTAssertNil(cell.boundURLForTesting)
        let image = try XCTUnwrap(cell.faviconImageForTesting)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertEqual(cell.faviconTintForTesting, .secondaryLabel)
        cell.prepareForReuse()
    }

    func testPrepareForReuseCancelsPendingTask() {
        let cell = makeCell()
        let siteURL = makeURL("https://reuse-cancellation-test.invalid/")
        let site = Suggestion(kind: .site(title: "Example", url: siteURL, isFavorite: false))
        cell.configure(for: site, engine: .google, isPrivate: false)
        XCTAssertTrue(cell.hasFaviconTaskForTesting)
        XCTAssertNotNil(cell.boundURLForTesting)
        cell.prepareForReuse()
        XCTAssertFalse(cell.hasFaviconTaskForTesting)
        XCTAssertNil(cell.boundURLForTesting)
        XCTAssertNil(cell.faviconImageForTesting)
        XCTAssertNil(cell.lastConfiguredIsPrivateForTesting)
    }

    func testPrivateFlagRoutesIntoCachedFaviconPath() throws {
        let siteURL = makeURL("https://private-routing-test.invalid/")
        let site = Suggestion(kind: .site(title: "Private Page", url: siteURL, isFavorite: false))
        let expectedPrivate = FaviconService.shared.cachedFaviconOrMonogram(
            for: siteURL,
            size: SuggestionCell.faviconLength,
            isPrivate: true
        )
        let expectedStandard = FaviconService.shared.cachedFaviconOrMonogram(
            for: siteURL,
            size: SuggestionCell.faviconLength,
            isPrivate: false
        )
        let privateCell = makeCell()
        privateCell.configure(for: site, engine: .google, isPrivate: true)
        XCTAssertEqual(privateCell.lastConfiguredIsPrivateForTesting, true)
        let privateImage = try XCTUnwrap(privateCell.faviconImageForTesting)
        XCTAssertEqual(privateImage.size, expectedPrivate.size)
        privateCell.prepareForReuse()
        let standardCell = makeCell()
        standardCell.configure(for: site, engine: .google, isPrivate: false)
        XCTAssertEqual(standardCell.lastConfiguredIsPrivateForTesting, false)
        let standardImage = try XCTUnwrap(standardCell.faviconImageForTesting)
        XCTAssertEqual(standardImage.size, expectedStandard.size)
        standardCell.prepareForReuse()
    }
}
