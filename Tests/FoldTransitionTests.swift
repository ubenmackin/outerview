//
//  FoldTransitionTests.swift
//  OuterViewTests
//

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class FoldTransitionTests: XCTestCase {
    private func makeRootWithParent(
        tabCount: Int = 2
    ) throws -> (parent: UIViewController, root: BrowserRootViewController) {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        let parent = UIViewController()
        TestWindow.attach(parent)
        parent.addChild(root)
        parent.view.addSubview(root.view)
        root.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            root.view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            root.view.topAnchor.constraint(equalTo: parent.view.topAnchor),
            root.view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor)
        ])
        root.didMove(toParent: parent)
        parent.view.layoutIfNeeded()
        var tabs: [TabRecord] = []
        for _ in 0 ..< tabCount {
            tabs.append(TabRecord(isPrivate: false))
            try root.tabPool.create(XCTUnwrap(tabs.last))
        }
        root.tabs = tabs
        root.selectedTabID = tabs.first?.id
        if let selected = root.selectedTabID {
            root.displaySelectedTabForTest(id: selected)
        }
        return (parent, root)
    }

    func testPlacementRecomputeOnTraitChange() throws {
        XCTAssertEqual(BrowserRootViewController.placement(for: .compact), .compact)
        XCTAssertEqual(BrowserRootViewController.placement(for: .regular), .regular)
        XCTAssertEqual(BrowserRootViewController.placement(for: .unspecified), .compact)
        let fixture = try makeRootWithParent(tabCount: 2)
        let root = fixture.root
        root.traitOverrides.horizontalSizeClass = .compact
        root.view.layoutIfNeeded()
        XCTAssertEqual(root.chromePlacement, .compact)
        root.traitOverrides.horizontalSizeClass = .regular
        root.view.layoutIfNeeded()
        XCTAssertEqual(root.chromePlacement, .regular)
        root.traitOverrides.horizontalSizeClass = .compact
        root.view.layoutIfNeeded()
        root.applyStructuralLayout()
        XCTAssertEqual(root.chromePlacement, .compact)
        XCTAssertTrue(root.topBarView.isHidden)
        XCTAssertFalse(root.railView.isHidden)
    }

    func testOrderedViewUpdates() throws {
        let fixture = try makeRootWithParent(tabCount: 2)
        let root = fixture.root
        root.traitOverrides.horizontalSizeClass = .regular
        root.view.layoutIfNeeded()
        root.applyStructuralLayout()
        XCTAssertEqual(root.chromePlacement, .regular)
        XCTAssertTrue(root.pillView.superview === root.topBarView.pillSlotView)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertEqual(root.editorView.chromePlacement, .regular)
        XCTAssertTrue(root.railView.isHidden)
        XCTAssertEqual(root.libraryOverlay.chromePlacement, .regular)
        XCTAssertEqual(root.settingsOverlay.chromePlacement, .regular)
        XCTAssertEqual(root.downloadsOverlay.chromePlacement, .regular)
        XCTAssertEqual(root.bookmarksLibraryView.chromePlacement, .regular)
        XCTAssertEqual(root.tabStripView.displayedTabs.count, 2)
        XCTAssertEqual(root.tabStripView.displayedSelectedID, root.selectedTabID)
        root.traitOverrides.horizontalSizeClass = .compact
        root.view.layoutIfNeeded()
        root.applyStructuralLayout()
        XCTAssertEqual(root.chromePlacement, .compact)
        XCTAssertTrue(root.pillView.superview === root.view)
        XCTAssertTrue(root.topBarView.isHidden)
        XCTAssertTrue(root.tabStripView.isHidden)
        XCTAssertEqual(root.editorView.chromePlacement, .compact)
        XCTAssertFalse(root.railView.isHidden)
        XCTAssertEqual(root.libraryOverlay.chromePlacement, .compact)
        XCTAssertEqual(root.tabStripView.displayedTabs.count, 2)
        let pillParents = Set([root.pillView.superview].compactMap(\.self))
        XCTAssertEqual(pillParents.count, 1)
    }

    func testSelectionPlusTextPreservation() throws {
        let fixture = try makeRootWithParent(tabCount: 3)
        let root = fixture.root
        let ids = root.tabs.map(\.id)
        let selected = ids[1]
        root.selectedTabID = selected
        root.displaySelectedTabForTest(id: selected)
        root.editorView.configure(text: "example.com/search", suggestions: [], engine: .google)
        let beforePage = root.peekActivePage()
        XCTAssertNotNil(beforePage)
        let beforeWebView = beforePage?.webView
        root.traitOverrides.horizontalSizeClass = .regular
        root.view.layoutIfNeeded()
        root.applyStructuralLayout()
        XCTAssertEqual(root.tabs.map(\.id), ids)
        XCTAssertEqual(root.selectedTabID, selected)
        XCTAssertEqual(root.editorView.fieldText, "example.com/search")
        XCTAssertTrue(root.peekActivePage() === beforePage)
        XCTAssertTrue(root.peekActivePage()?.webView === beforeWebView)
        root.traitOverrides.horizontalSizeClass = .compact
        root.view.layoutIfNeeded()
        root.applyStructuralLayout()
        XCTAssertEqual(root.tabs.map(\.id), ids)
        XCTAssertEqual(root.selectedTabID, selected)
        XCTAssertEqual(root.editorView.fieldText, "example.com/search")
        XCTAssertTrue(root.peekActivePage() === beforePage)
    }

    func testLandscapeCompactRetention() throws {
        XCTAssertEqual(BrowserRootViewController.placement(for: .compact), .compact)
        let landscape = UITraitCollection(mutations: { traits in
            traits.horizontalSizeClass = .compact
            traits.verticalSizeClass = .compact
        })
        XCTAssertEqual(landscape.horizontalSizeClass, .compact)
        let fixture = try makeRootWithParent(tabCount: 2)
        let root = fixture.root
        root.traitOverrides.horizontalSizeClass = .compact
        root.traitOverrides.verticalSizeClass = .compact
        root.view.layoutIfNeeded()
        XCTAssertEqual(root.chromePlacement, .compact)
        root.applyStructuralLayout()
        XCTAssertEqual(root.chromePlacement, .compact)
        XCTAssertTrue(root.pillView.superview === root.view)
        XCTAssertTrue(root.topBarView.isHidden)
        XCTAssertTrue(root.tabStripView.isHidden)
        XCTAssertFalse(root.railView.isHidden)
        XCTAssertEqual(root.editorView.chromePlacement, .compact)
        root.applyStructuralLayout()
        XCTAssertTrue(root.pillView.superview === root.view)
        XCTAssertTrue(root.topBarView.isHidden)
    }
}

extension BrowserRootViewController {
    func displaySelectedTabForTest(id: UUID) {
        selectedTabID = id
        displaySelectedTab()
    }
}
