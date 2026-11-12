// Tests — Page-menu tap single-path wiring.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class PageMenuTapTests: XCTestCase {
    private func pageMenuButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityLabel == "Page menu" {
            return button
        }
        for subview in view.subviews {
            if let found = pageMenuButton(in: subview) {
                return found
            }
        }
        return nil
    }

    func testArmedProviderSuppressesForwarder() throws {
        let pill = AddressBarView(frame: .zero)
        var fireCount = 0
        pill.onPageMenu = { fireCount += 1 }
        pill.pageMenuProvider = { UIMenu(children: [UIAction(title: "Copy") { _ in }]) }
        let button = try XCTUnwrap(pageMenuButton(in: pill))
        XCTAssertNotNil(button.menu)
        XCTAssertTrue(button.showsMenuAsPrimaryAction)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fireCount, 0)
    }

    func testUnarmedProviderForwardsTap() throws {
        let pill = AddressBarView(frame: .zero)
        var fireCount = 0
        pill.onPageMenu = { fireCount += 1 }
        pill.pageMenuProvider = nil
        let button = try XCTUnwrap(pageMenuButton(in: pill))
        XCTAssertNil(button.menu)
        XCTAssertFalse(button.showsMenuAsPrimaryAction)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fireCount, 1)
    }

    func testProviderChurnReinstallsSingleForwarder() throws {
        let pill = AddressBarView(frame: .zero)
        var fireCount = 0
        pill.onPageMenu = { fireCount += 1 }
        pill.pageMenuProvider = nil
        var button = try XCTUnwrap(pageMenuButton(in: pill))
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fireCount, 1)
        pill.pageMenuProvider = { UIMenu(children: []) }
        button = try XCTUnwrap(pageMenuButton(in: pill))
        XCTAssertNotNil(button.menu)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fireCount, 1)
        pill.pageMenuProvider = nil
        button = try XCTUnwrap(pageMenuButton(in: pill))
        XCTAssertNil(button.menu)
        XCTAssertFalse(button.showsMenuAsPrimaryAction)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fireCount, 2)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fireCount, 3)
    }

    func testRearmingKeepsForwarderSuppressed() throws {
        let pill = AddressBarView(frame: .zero)
        var fireCount = 0
        pill.onPageMenu = { fireCount += 1 }
        pill.pageMenuProvider = { UIMenu(children: []) }
        pill.pageMenuProvider = { UIMenu(children: [UIAction(title: "Share") { _ in }]) }
        let button = try XCTUnwrap(pageMenuButton(in: pill))
        XCTAssertNotNil(button.menu)
        XCTAssertTrue(button.showsMenuAsPrimaryAction)
        button.sendActions(for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fireCount, 0)
    }
}
