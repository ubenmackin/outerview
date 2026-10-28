//
//  AccessibilityTests.swift
//  OuterViewTests
//

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class AccessibilityTests: XCTestCase {
    func testLibraryTabBarAccessibility() {
        let tabBar = LibraryTabBar()
        TestWindow.attach(tabBar)

        XCTAssertEqual(tabBar.segmentAccessibilityLabel(at: 0), "Favorites")
        XCTAssertEqual(tabBar.segmentAccessibilityLabel(at: 1), "Bookmarks")
        XCTAssertEqual(tabBar.segmentAccessibilityLabel(at: 2), "History")
        XCTAssertNil(tabBar.segmentAccessibilityLabel(at: 99))
    }

    func testFavoriteTileCellAccessibility() throws {
        let cell = FavoriteTileCell(frame: CGRect(x: 0, y: 0, width: 76, height: 112))
        let bookmark = try Bookmark(
            id: UUID(),
            title: "Apple Developer",
            url: XCTUnwrap(URL(string: "https://developer.apple.com")),
            addedAt: Date(),
            isFavorite: true,
            folderId: nil
        )

        var didCopy = false
        var didDelete = false
        cell.onCopyURL = { didCopy = true }
        cell.onDelete = { didDelete = true }
        cell.configure(with: bookmark)

        XCTAssertTrue(cell.isAccessibilityElement)
        XCTAssertTrue(cell.accessibilityTraits.contains(.button))
        XCTAssertNotNil(cell.accessibilityLabel)
        XCTAssertTrue(cell.accessibilityLabel?.contains("Apple Developer") ?? false)
        XCTAssertTrue(cell.accessibilityLabel?.contains("developer.apple.com") ?? false)
        XCTAssertEqual(cell.accessibilityHint, "Double tap to open favorite")

        let customActions = cell.accessibilityCustomActions ?? []
        XCTAssertEqual(customActions.count, 2)
        XCTAssertEqual(customActions[0].name, "Copy URL")
        XCTAssertEqual(customActions[1].name, "Remove from Favorites")

        // Trigger actions
        _ = customActions[0].actionHandler?(customActions[0])
        XCTAssertTrue(didCopy)
        _ = customActions[1].actionHandler?(customActions[1])
        XCTAssertTrue(didDelete)
    }

    func testAddressBarViewAccessibility() throws {
        let pill = AddressBarView(frame: CGRect(x: 0, y: 0, width: 360, height: 44))
        XCTAssertTrue(pill.isDomainAccessibilityElement)

        // Empty URL shows placeholder
        pill.configure(url: nil, isSecure: false, isLoading: false)
        XCTAssertEqual(pill.domainAccessibilityLabel, AddressBarView.placeholder)
        XCTAssertEqual(pill.actionAccessibilityLabel, "Reload page")

        // Loading state
        let secureURL = try XCTUnwrap(URL(string: "https://wikipedia.org"))
        pill.configure(url: secureURL, isSecure: true, isLoading: true)
        XCTAssertTrue(pill.domainAccessibilityLabel?.contains("wikipedia.org") ?? false)
        XCTAssertTrue(pill.domainAccessibilityLabel?.contains("secure") ?? false)
        XCTAssertEqual(pill.actionAccessibilityLabel, "Stop loading")

        // Non-secure URL
        let insecureURL = try XCTUnwrap(URL(string: "http://example.com"))
        pill.configure(url: insecureURL, isSecure: false, isLoading: false)
        XCTAssertTrue(pill.domainAccessibilityLabel?.contains("example.com") ?? false)
        XCTAssertTrue(pill.domainAccessibilityLabel?.contains("not secure") ?? false)
        XCTAssertEqual(pill.actionAccessibilityLabel, "Reload page")
    }

    func testTabCardCellAccessibility() throws {
        let cell = TabCardCell(frame: CGRect(x: 0, y: 0, width: 160, height: 240))
        let item = try TabOverviewItem(
            id: UUID(),
            title: "Swift Documentation",
            host: "swift.org",
            url: XCTUnwrap(URL(string: "https://swift.org")),
            isPrivate: false
        )

        // Unselected card
        cell.configure(with: item, preview: nil, isSelected: false)
        XCTAssertTrue(cell.isAccessibilityElement)
        XCTAssertTrue(cell.accessibilityTraits.contains(.button))
        XCTAssertFalse(cell.accessibilityTraits.contains(.selected))
        XCTAssertTrue(cell.accessibilityLabel?.contains("Swift Documentation") ?? false)
        XCTAssertTrue(cell.accessibilityLabel?.contains("swift.org") ?? false)
        XCTAssertEqual(cell.accessibilityHint, "Double tap to switch to tab")

        // Selected card
        cell.configure(with: item, preview: nil, isSelected: true)
        XCTAssertTrue(cell.accessibilityTraits.contains(.selected))

        // Custom action for closing tab
        var didClose = false
        cell.onClose = { didClose = true }
        let customActions = cell.accessibilityCustomActions ?? []
        XCTAssertEqual(customActions.count, 1)
        XCTAssertEqual(customActions.first?.name, "Close Tab")
        _ = try customActions.first?.actionHandler?(XCTUnwrap(customActions.first))
        XCTAssertTrue(didClose)
    }

    func testAccessibleButtonTouchTarget() {
        let button = AccessibleButton(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        // Center point is inside
        XCTAssertTrue(button.point(inside: CGPoint(x: 18, y: 18), with: nil))

        // (-2, 18) is outside the 36x36 bounds (0..36), but inside the 44x44 minimum hit area (-4..40)
        XCTAssertTrue(button.point(inside: CGPoint(x: -2, y: 18), with: nil))
        XCTAssertTrue(button.point(inside: CGPoint(x: 38, y: 18), with: nil))

        // (-10, 18) is completely outside the 44x44 hit area
        XCTAssertFalse(button.point(inside: CGPoint(x: -10, y: 18), with: nil))
    }

    func testAddressEditorViewAccessibility() {
        let editor = AddressEditorView(frame: CGRect(x: 0, y: 0, width: 360, height: 600))
        TestWindow.attach(editor)
        XCTAssertEqual(editor.fieldText, "")
        editor.configure(text: "apple.com", suggestions: [], engine: .google)
        XCTAssertEqual(editor.fieldText, "apple.com")
    }
}
