//
//  VerticalBarTests.swift
//  OuterViewTests
//

@testable import OuterView
import SwiftUI
import UIKit
import XCTest

@MainActor
final class VerticalBarTests: XCTestCase {
    private func makeHost() throws -> (host: BrowserChromeHostViewController, root: BrowserRootViewController) {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        let host = BrowserChromeHostViewController(browserRoot: root)
        return (host, root)
    }

    func testHostExposesBrowserRootForForwarding() throws {
        let fixture = try makeHost()
        XCTAssertTrue(fixture.host.browserRoot === fixture.root)
        XCTAssertTrue(fixture.host.childForPreferredVerticalBarBehavior === fixture.root)
    }

    func testHostEmbedsBrowserRootEdgeToEdge() throws {
        let fixture = try makeHost()
        TestWindow.attach(fixture.host)
        XCTAssertTrue(fixture.root.parent === fixture.host)
        XCTAssertTrue(fixture.root.view.superview === fixture.host.view)
        let edges = fixture.host.view.constraints.filter {
            ($0.firstItem as? UIView) === fixture.root.view
                && ($0.secondItem as? UIView) === fixture.host.view
        }
        XCTAssertEqual(edges.count, 4)
        for edge in edges {
            XCTAssertEqual(edge.constant, 0, accuracy: 0.001)
        }
    }

    func testPlacementMapping() {
        XCTAssertEqual(BrowserRootViewController.placement(for: .compact), .compact)
        XCTAssertEqual(BrowserRootViewController.placement(for: .regular), .regular)
        XCTAssertEqual(BrowserRootViewController.placement(for: .unspecified), .compact)
        XCTAssertEqual(BrowserRootViewController.verticalBarBehavior(for: .compact), .automatic)
        XCTAssertEqual(BrowserRootViewController.verticalBarBehavior(for: .regular), .disabled)
    }

    func testPreferredBehaviorFollowsPlacement() throws {
        let fixture = try makeHost()
        TestWindow.attach(fixture.host)
        fixture.root.traitOverrides.horizontalSizeClass = .compact
        fixture.host.view.layoutIfNeeded()
        XCTAssertEqual(fixture.root.preferredVerticalBarBehavior, .automatic)
        fixture.root.traitOverrides.horizontalSizeClass = .regular
        fixture.host.view.layoutIfNeeded()
        XCTAssertEqual(fixture.root.preferredVerticalBarBehavior, .disabled)
    }

    func testCoordinatorDrivesThroughHostBrowserRoot() throws {
        let fixture = try makeHost()
        TestWindow.attach(fixture.host)
        let container = BrowserContainerView(scenePhase: .active, pendingURL: .constant(nil))
        let coordinator = container.makeCoordinator()
        coordinator.controller = fixture.host.browserRoot
        XCTAssertTrue(coordinator.controller === fixture.root)
        XCTAssertTrue(coordinator.controller === fixture.host.browserRoot)
        coordinator.controller?.handleScenePhase(.active)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        coordinator.controller?.openExternalURL(url)
        XCTAssertNotNil(fixture.root.activePage())
    }
}
