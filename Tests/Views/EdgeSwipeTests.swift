// RootView — Edge-close recognizer installation view test.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class EdgeSwipeTests: XCTestCase {
    private func makeRoot() throws -> BrowserRootViewController {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        TestWindow.attach(root)
        root.view.layoutIfNeeded()
        return root
    }

    func testEdgeCloseRecognizerInstalledOnContentContainer() throws {
        let root = try makeRoot()
        let recognizers = root.contentContainer.gestureRecognizers ?? []
        let edgePans = recognizers.compactMap { $0 as? UIScreenEdgePanGestureRecognizer }
        // Installation is owned solely by viewDidLoad; removing the call
        // empties this list and fails the count.
        XCTAssertEqual(edgePans.count, 1)
        let edge = try XCTUnwrap(edgePans.first)
        XCTAssertEqual(edge.edges, .left)
        XCTAssertIdentical(edge.delegate, root)
        XCTAssertTrue(edge.isEnabled)
    }
}
