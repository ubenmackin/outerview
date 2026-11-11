// RootView — EdgeClosePolicy gate matrix for the left-edge child-tab close.

@testable import OuterView
import XCTest

final class EdgeClosePolicyTests: XCTestCase {
    /// All-clear baseline: every gate starts in its passing state.
    private func canBegin(
        canGoBack: Bool = false,
        parentResolved: Bool = true,
        isEditingAddress: Bool = false,
        isFindActive: Bool = false,
        isOverviewVisible: Bool = false,
        isStartPageShown: Bool = false,
        isErrorVisible: Bool = false,
        pillSessionActive: Bool = false
    ) -> Bool {
        EdgeClosePolicy.canBegin(
            canGoBack: canGoBack,
            parentResolved: parentResolved,
            isEditingAddress: isEditingAddress,
            isFindActive: isFindActive,
            isOverviewVisible: isOverviewVisible,
            isStartPageShown: isStartPageShown,
            isErrorVisible: isErrorVisible,
            pillSessionActive: pillSessionActive
        )
    }

    func testAllClearPasses() {
        XCTAssertTrue(canBegin())
    }

    func testBackHistoryRejects() {
        XCTAssertFalse(canBegin(canGoBack: true))
    }

    func testUnresolvedParentRejects() {
        XCTAssertFalse(canBegin(parentResolved: false))
    }

    func testEditingAddressAloneRejects() {
        XCTAssertFalse(canBegin(isEditingAddress: true))
    }

    func testFindActiveAloneRejects() {
        XCTAssertFalse(canBegin(isFindActive: true))
    }

    func testOverviewVisibleAloneRejects() {
        XCTAssertFalse(canBegin(isOverviewVisible: true))
    }

    func testStartPageShownAloneRejects() {
        XCTAssertFalse(canBegin(isStartPageShown: true))
    }

    func testErrorVisibleAloneRejects() {
        XCTAssertFalse(canBegin(isErrorVisible: true))
    }

    func testPillSessionActiveAloneRejects() {
        XCTAssertFalse(canBegin(pillSessionActive: true))
    }

    func testCombinedGatesReject() {
        XCTAssertFalse(canBegin(canGoBack: true, parentResolved: false, isStartPageShown: true))
        XCTAssertFalse(canBegin(isOverviewVisible: true, isErrorVisible: true, pillSessionActive: true))
    }
}
