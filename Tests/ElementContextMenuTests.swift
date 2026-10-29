//
//  ElementContextMenuTests.swift
//  OuterView
//

@testable import OuterView
import WebKit
import XCTest

@MainActor
final class ElementContextMenuTests: XCTestCase {
    private enum Fixture {
        static let linkURL = URL(string: "https://example.com/news")!
        static let imageURL = URL(string: "https://cdn.example.com/photo.png")!
        static let pageURL = URL(string: "https://example.com/blog/post")!
    }

    /// UIAction handlers are not invocable through public API, so dispatch is
    /// exercised by the app flow; menu tests inspect menu shape only.
    private static let stubActions = ElementContextActions(
        openInNewTab: { _ in },
        addToReadingList: { _ in },
        copyLink: { _ in },
        share: { _ in },
        saveToPhotos: { _ in },
        copyImage: { _ in }
    )

    func testLinkMenuItemsCountOrderIconsAndImageOnlyExclusion() {
        let menu = ElementContextMenu.menu(for: .link(url: Fixture.linkURL), actions: Self.stubActions)

        XCTAssertEqual(menu.children.count, 4)
        XCTAssertEqual(
            menu.children.compactMap { $0 as? UIAction }.map(\.title),
            ["Open in New Tab", "Add to Reading List", "Copy Link", "Share"]
        )
        XCTAssertEqual(
            menu.children.compactMap { $0 as? UIAction }.map(\.image),
            [
                UIImage(systemName: "plus.square.on.square"),
                UIImage(systemName: "eyeglasses"),
                UIImage(systemName: "doc.on.doc"),
                UIImage(systemName: "square.and.arrow.up")
            ]
        )
        let titles = Set(menu.children.compactMap { $0 as? UIAction }.map(\.title))
        // Reading list is link-only; Photos actions are image-only.
        XCTAssertFalse(titles.contains("Save to Photos"))
        XCTAssertFalse(titles.contains("Copy Image"))
    }

    func testImageMenuItemsCountOrderIconsAndLinkOnlyExclusion() {
        let menu = ElementContextMenu.menu(for: .image(url: Fixture.imageURL), actions: Self.stubActions)

        XCTAssertEqual(menu.children.count, 4)
        XCTAssertEqual(
            menu.children.compactMap { $0 as? UIAction }.map(\.title),
            ["Open in New Tab", "Save to Photos", "Copy Image", "Share"]
        )
        XCTAssertEqual(
            menu.children.compactMap { $0 as? UIAction }.map(\.image),
            [
                UIImage(systemName: "plus.square.on.square"),
                UIImage(systemName: "square.and.arrow.down"),
                UIImage(systemName: "photo.on.rectangle.angled"),
                UIImage(systemName: "square.and.arrow.up")
            ]
        )
        let titles = Set(menu.children.compactMap { $0 as? UIAction }.map(\.title))
        XCTAssertFalse(titles.contains("Add to Reading List"))
        XCTAssertFalse(titles.contains("Copy Link"))
    }

    func testLinkURLMapsToLinkKind() {
        XCTAssertEqual(
            ElementContextMenu.kind(linkURL: Fixture.linkURL, imageURLString: nil, baseURL: nil),
            .link(url: Fixture.linkURL)
        )
        // A link beats a co-located image so link-wrapped images stay links.
        XCTAssertEqual(
            ElementContextMenu.kind(linkURL: Fixture.linkURL, imageURLString: Fixture.imageURL.absoluteString, baseURL: nil),
            .link(url: Fixture.linkURL)
        )
    }

    func testImageSourceMapsToImageKind() {
        XCTAssertEqual(
            ElementContextMenu.kind(linkURL: nil, imageURLString: Fixture.imageURL.absoluteString, baseURL: nil),
            .image(url: Fixture.imageURL)
        )
    }

    func testRelativeImageSourceResolvesAgainstPageURL() throws {
        let expectedCover = try XCTUnwrap(URL(string: "https://example.com/assets/cover.jpg"))
        XCTAssertEqual(
            ElementContextMenu.kind(linkURL: nil, imageURLString: "/assets/cover.jpg", baseURL: Fixture.pageURL),
            .image(url: expectedCover)
        )
        let expectedBlog = try XCTUnwrap(URL(string: "https://example.com/blog/cover.jpg"))
        XCTAssertEqual(
            ElementContextMenu.absoluteURL(for: "cover.jpg", baseURL: Fixture.pageURL),
            expectedBlog
        )
    }

    func testMissingImageSourcesProduceNoKind() {
        XCTAssertNil(ElementContextMenu.kind(linkURL: nil, imageURLString: nil, baseURL: Fixture.pageURL))
        XCTAssertNil(ElementContextMenu.kind(linkURL: nil, imageURLString: "", baseURL: Fixture.pageURL))
        // Relative sources without a page URL base cannot resolve.
        XCTAssertNil(ElementContextMenu.kind(linkURL: nil, imageURLString: "cover.jpg", baseURL: nil))
    }

    func testWebPageControllerDefaultsToNilActionsAndOwnsUIDelegate() {
        let controller = WebPageController(configuration: WKWebViewConfiguration())

        XCTAssertNil(controller.contextActions)
        XCTAssertIdentical(controller.webView.uiDelegate, controller)
    }
}
