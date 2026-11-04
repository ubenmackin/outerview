// RootView — Interface-mode resolution plus status-bar scope.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class InterfaceModeTests: XCTestCase {
    func testInterfaceModeResolution() {
        // Mode 2: regular horizontal size class -> duoInnerOrPad (iPad / Duo inner / Pro Max landscape)
        let modeRegular = BrowserRootViewController.interfaceMode(
            horizontalSizeClass: .regular,
            safeAreaInsets: .zero,
            bounds: CGRect(x: 0, y: 0, width: 951, height: 669),
            deviceName: "iPhone Duo"
        )
        XCTAssertEqual(modeRegular, .duoInnerOrPad)

        // Mode 2: iPhone 17 Pro Max in landscape has regular size class
        let modeProMaxLandscape = BrowserRootViewController.interfaceMode(
            horizontalSizeClass: .regular,
            safeAreaInsets: UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 0),
            bounds: CGRect(x: 0, y: 0, width: 932, height: 430),
            deviceName: "iPhone 17 Pro Max"
        )
        XCTAssertEqual(modeProMaxLandscape, .duoInnerOrPad)

        // Mode 1: iPhone Duo outer display (bounds 466x678, compact)
        let modeDuoOuterBounds = BrowserRootViewController.interfaceMode(
            horizontalSizeClass: .compact,
            safeAreaInsets: .zero,
            bounds: CGRect(x: 0, y: 0, width: 466, height: 678),
            deviceName: "iPhone 17 Pro"
        )
        XCTAssertEqual(modeDuoOuterBounds, .duoOuter)

        // Mode 1: iPhone Duo outer display with safe area right >= 44
        let modeDuoOuterSafeArea = BrowserRootViewController.interfaceMode(
            horizontalSizeClass: .compact,
            safeAreaInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
            bounds: CGRect(x: 0, y: 0, width: 466, height: 678),
            deviceName: "Any Device"
        )
        XCTAssertEqual(modeDuoOuterSafeArea, .duoOuter)

        // Mode 1: Simulator device name containing "Duo"
        let modeDuoDeviceName = BrowserRootViewController.interfaceMode(
            horizontalSizeClass: .compact,
            safeAreaInsets: .zero,
            bounds: CGRect(x: 0, y: 0, width: 402, height: 874),
            deviceName: "iPhone Duo - Outer Display"
        )
        XCTAssertEqual(modeDuoDeviceName, .duoOuter)

        // Mode 3: iPhone 17 Pro in portrait (compact, bounds 402x874, safeAreaRight 0, name without Duo)
        let modeIPhone17Pro = BrowserRootViewController.interfaceMode(
            horizontalSizeClass: .compact,
            safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
            bounds: CGRect(x: 0, y: 0, width: 402, height: 874),
            deviceName: "iPhone 17 Pro"
        )
        XCTAssertEqual(modeIPhone17Pro, .nonDuoPhone)

        // Mode 3: iPhone 17 Pro Max in portrait (compact)
        let modeIPhone17ProMaxPortrait = BrowserRootViewController.interfaceMode(
            horizontalSizeClass: .compact,
            safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
            bounds: CGRect(x: 0, y: 0, width: 430, height: 932),
            deviceName: "iPhone 17 Pro Max"
        )
        XCTAssertEqual(modeIPhone17ProMaxPortrait, .nonDuoPhone)
    }

    func testStatusBarHidingScope() {
        let minifiedState = ChromeState(rail: .hidden, pill: .minified)
        let expandedState = ChromeState(rail: .visible, pill: .expanded)
        let editingState = ChromeState(rail: .visible, pill: .editing)

        // Mode 1: statusBarHidden is true when address bar is collapsed/minified
        XCTAssertTrue(BrowserRootViewController.shouldHideStatusBar(
            for: .duoOuter,
            state: minifiedState,
            isOverviewVisible: false,
            isSheetOverlayVisible: false
        ))
        XCTAssertFalse(BrowserRootViewController.shouldHideStatusBar(
            for: .duoOuter,
            state: expandedState,
            isOverviewVisible: false,
            isSheetOverlayVisible: false
        ))
        XCTAssertFalse(BrowserRootViewController.shouldHideStatusBar(
            for: .duoOuter,
            state: editingState,
            isOverviewVisible: false,
            isSheetOverlayVisible: false
        ))

        // Mode 2: statusBarHidden is true when address bar is collapsed/minified
        XCTAssertTrue(BrowserRootViewController.shouldHideStatusBar(
            for: .duoInnerOrPad,
            state: minifiedState,
            isOverviewVisible: false,
            isSheetOverlayVisible: false
        ))
        XCTAssertFalse(BrowserRootViewController.shouldHideStatusBar(
            for: .duoInnerOrPad,
            state: expandedState,
            isOverviewVisible: false,
            isSheetOverlayVisible: false
        ))

        // Mode 3: statusBarHidden is false (standard iPhone Safari status bar remains visible)
        XCTAssertFalse(BrowserRootViewController.shouldHideStatusBar(
            for: .nonDuoPhone,
            state: minifiedState,
            isOverviewVisible: false,
            isSheetOverlayVisible: false
        ))
        XCTAssertFalse(BrowserRootViewController.shouldHideStatusBar(
            for: .nonDuoPhone,
            state: expandedState,
            isOverviewVisible: false,
            isSheetOverlayVisible: false
        ))
    }

    func testNonDuoPhoneChromeLayout() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        // Frame of an iPhone 17 Pro (402x874)
        let phoneFrame = CGRect(x: 0, y: 0, width: 402, height: 874)
        TestWindow.attach(root, frame: phoneFrame)
        root.view.frame = phoneFrame

        // Verify resolution on non-Duo phone bounds
        XCTAssertEqual(
            BrowserRootViewController.interfaceMode(
                horizontalSizeClass: .compact,
                safeAreaInsets: .zero,
                bounds: phoneFrame,
                deviceName: "iPhone 17 Pro"
            ),
            .nonDuoPhone
        )

        // Apply placement for non-Duo phone
        root.topBarView.isNonDuoPhone = true
        root.applyChromePlacement(for: .compact)

        // Mode 3 contract:
        // 1. Bottom address pill is attached to root.view (not topBarView)
        XCTAssertTrue(root.pillView.superview === root.view)
        // 2. Side rail is hidden
        XCTAssertTrue(root.railView.isHidden)
        // 3. TopBarView is hidden on the main browser screen
        XCTAssertTrue(root.topBarView.isHidden)
        // 4. Tab strip is hidden (no tab strip on phone portrait)
        XCTAssertTrue(root.tabStripView.isHidden)

        // Verify bottom stacks contain the action buttons
        root.updateRailItems()
        let leadingLabels = root.bottomLeadingStack.arrangedSubviews.compactMap(\.accessibilityLabel)
        let trailingLabels = root.bottomTrailingStack.arrangedSubviews.compactMap(\.accessibilityLabel)
        XCTAssertEqual(leadingLabels, ["Back"])
        XCTAssertEqual(trailingLabels, ["Bookmarks", "Tabs"])

        // Verify Back and Tabs buttons have long-press menus configured (showsMenuAsPrimaryAction = false)
        guard let backButton = root.bottomLeadingStack.arrangedSubviews.first as? UIButton,
              let tabsButton = root.bottomTrailingStack.arrangedSubviews.last as? UIButton
        else {
            XCTFail("Expected UIButton in bottom stacks")
            return
        }
        XCTAssertNotNil(backButton.menu)
        XCTAssertFalse(backButton.showsMenuAsPrimaryAction)
        XCTAssertNotNil(tabsButton.menu)
        XCTAssertFalse(tabsButton.showsMenuAsPrimaryAction)
    }

    func testStartPageDoneButtonInMode3() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        let phoneFrame = CGRect(x: 0, y: 0, width: 402, height: 874)
        TestWindow.attach(root, frame: phoneFrame)
        root.traitOverrides.horizontalSizeClass = .compact
        root.view.layoutIfNeeded()

        root.applyChromePlacement(for: .compact)
        root.setChromeItems(
            prefix: [],
            suffix: [.done {}]
        )

        XCTAssertTrue(root.bottomLeadingStack.arrangedSubviews.isEmpty)
        let trailingLabels = root.bottomTrailingStack.arrangedSubviews.compactMap(\.accessibilityLabel)
        XCTAssertEqual(trailingLabels, ["Done"])
    }

    func testTabGroupMenuStructure() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        let menu = root.makeTabGroupMenu()

        // Verify menu elements exist
        XCTAssertFalse(menu.children.isEmpty)
        // Check inline menus exist for Private/Tabs count and tab operations
        let inlineMenus = menu.children.compactMap { $0 as? UIMenu }
        XCTAssertGreaterThanOrEqual(inlineMenus.count, 2)

        // Verify Private and count options
        let modesMenu = inlineMenus.first(where: { candidateMenu in
            candidateMenu.children.contains { ($0 as? UIAction)?.title == "Private" }
        })
        XCTAssertNotNil(modesMenu)

        // Verify Close this tab, New Private Tab, New Tab options
        let opsMenu = inlineMenus.first(where: { candidateMenu in
            candidateMenu.children.contains { ($0 as? UIAction)?.title == "Close This Tab" }
        })
        XCTAssertNotNil(opsMenu)
        let closeAction = opsMenu?.children.compactMap { $0 as? UIAction }.first(where: { $0.title == "Close This Tab" })
        XCTAssertEqual(closeAction?.attributes, .destructive)

        let hasNewPrivateTab = opsMenu?.children.contains { ($0 as? UIAction)?.title == "New Private Tab" } ?? false
        let hasNewTab = opsMenu?.children.contains { ($0 as? UIAction)?.title == "New Tab" } ?? false
        XCTAssertTrue(hasNewPrivateTab)
        XCTAssertTrue(hasNewTab)
    }

    func testTabStripSynchronizedWithPillSizeOnRegular() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        let regularFrame = CGRect(x: 0, y: 0, width: 951, height: 669)
        TestWindow.attach(root, frame: regularFrame)
        root.traitOverrides.horizontalSizeClass = .regular
        root.view.layoutIfNeeded()

        var tabs: [TabRecord] = []
        for _ in 0 ..< 2 {
            tabs.append(TabRecord(isPrivate: false))
        }
        root.tabs = tabs
        root.selectedTabID = tabs.first?.id
        root.applyChromePlacement(for: .regular)
        root.applyChromeViews(animated: false)

        // Full large address bar showing -> tab bar shows and toolbar is expanded
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertFalse(root.topBarView.isCollapsed)
        XCTAssertEqual(root.topBarView.currentHeightConstant, TopBarView.barHeight)

        // Scroll 8 pt (rail threshold) -> pill is still expanded, so tab bar still shows!
        _ = root.chromeController.handle(.scroll(offsetDelta: 8))
        XCTAssertEqual(root.chromeController.state.pill, .expanded)
        root.applyCommands(ChromeCommands(rail: .hidden), animated: false)
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertFalse(root.topBarView.isCollapsed)

        // Scroll to 24 pt (pill minify threshold) -> pill minifies, tab bar shrinks away, toolbar collapses
        _ = root.chromeController.handle(.scroll(offsetDelta: 16))
        XCTAssertEqual(root.chromeController.state.pill, .minified)
        root.applyCommands(ChromeCommands(pill: .minified), animated: false)
        XCTAssertTrue(root.tabStripView.isHidden)
        XCTAssertTrue(root.topBarView.isCollapsed)
        XCTAssertEqual(root.topBarView.currentHeightConstant, TopBarView.remnantHeight)
    }

    func testNonDuoPhoneTopInsetMatchesContentReservation() {
        let expanded = ChromeState(rail: .visible, pill: .expanded)
        let collapsed = ChromeState(rail: .hidden, pill: .minified)
        // In Mode 3, there is no top toolbar on the main screen, so topContentInset is 0.
        XCTAssertEqual(
            BrowserRootViewController.topContentInset(
                for: .compact,
                state: expanded,
                stripVisible: false,
                interfaceMode: .nonDuoPhone
            ),
            0
        )
        XCTAssertEqual(
            BrowserRootViewController.topContentInset(
                for: .compact,
                state: collapsed,
                stripVisible: false,
                interfaceMode: .nonDuoPhone
            ),
            0
        )
    }
}
