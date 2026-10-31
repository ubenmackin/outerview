//
//  EditorPlacementTests.swift
//  OuterViewTests
//

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class EditorPlacementTests: XCTestCase {
    private func makeEditor(placement: ChromePlacement = .compact) -> AddressEditorView {
        let editor = AddressEditorView()
        TestWindow.attach(editor)
        editor.applyPlacement(for: placement)
        return editor
    }

    func testCompactKeepsBottomDockAboveKeyboard() {
        let editor = makeEditor(placement: .compact)
        XCTAssertEqual(editor.chromePlacement, .compact)
        XCTAssertFalse(editor.isDimVisible)
        XCTAssertTrue(editor.isCompactLayoutActive)
        XCTAssertFalse(editor.isRegularLayoutActive)
        XCTAssertFalse(editor.isSuggestionsHeightCapped)
    }

    func testRegularShowsTopAnchoredFieldWithDim() {
        let editor = makeEditor(placement: .regular)
        XCTAssertEqual(editor.chromePlacement, .regular)
        XCTAssertTrue(editor.isRegularLayoutActive)
        XCTAssertFalse(editor.isCompactLayoutActive)
        XCTAssertTrue(editor.isDimVisible)
    }

    func testDimPresentOnlyOnRegular() {
        let editor = makeEditor(placement: .compact)
        XCTAssertFalse(editor.isDimVisible)
        editor.applyPlacement(for: .regular)
        XCTAssertTrue(editor.isDimVisible)
        editor.applyPlacement(for: .compact)
        XCTAssertFalse(editor.isDimVisible)
    }

    func testSuggestionsTableCappedAt420() {
        XCTAssertEqual(AddressEditorView.suggestionsMaxHeight, 420)
        let editor = makeEditor(placement: .compact)
        XCTAssertFalse(editor.isSuggestionsHeightCapped)
        editor.applyPlacement(for: .regular)
        XCTAssertTrue(editor.isSuggestionsHeightCapped)
        XCTAssertEqual(editor.suggestionsMaxHeight, 420)
    }

    func testFieldTextPreservedAcrossPlacementSwaps() {
        let editor = makeEditor(placement: .compact)
        let suggestion = Suggestion(kind: .search(query: "apple"))
        editor.configure(text: "example.com", suggestions: [suggestion], engine: .google)
        let before = editor.fieldText
        XCTAssertEqual(before, "example.com")
        editor.applyPlacement(for: .regular)
        XCTAssertEqual(editor.fieldText, before)
        XCTAssertEqual(editor.suggestions.count, 1)
        editor.applyPlacement(for: .compact)
        XCTAssertEqual(editor.fieldText, before)
        XCTAssertEqual(editor.suggestions.count, 1)
    }

    func testRootStructuralLayoutPropagatesPlacement() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        TestWindow.attach(root)
        root.editorView.configure(text: "example.com", suggestions: [], engine: .google)
        root.editorView.applyPlacement(for: .regular)
        XCTAssertEqual(root.editorView.chromePlacement, .regular)
        root.applyStructuralLayout()
        XCTAssertEqual(root.editorView.chromePlacement, root.chromePlacement)
        XCTAssertEqual(root.editorView.fieldText, "example.com")
    }

    func testStaticsMatchRegularHeaderContract() {
        XCTAssertEqual(TopBarView.barHeight, 56)
        XCTAssertEqual(TabStripView.stripHeight, 44)
        XCTAssertEqual(AddressEditorView.panelMargin, 24)
        XCTAssertEqual(AddressEditorView.panelRadius, 16)
        XCTAssertEqual(AddressEditorView.dimAlpha, 0.2, accuracy: 0.001)
        XCTAssertEqual(AddressEditorView.suggestionsMaxHeight, 420)
    }

    func testRegularPanelFrameMarginsAndRadius() {
        let editor = AddressEditorView()
        editor.frame = TestWindow.defaultFrame
        TestWindow.attach(editor, frame: TestWindow.defaultFrame)
        editor.frame = TestWindow.defaultFrame
        editor.applyPlacement(for: .regular)
        editor.layoutIfNeeded()
        XCTAssertTrue(editor.isRegularLayoutActive)
        XCTAssertTrue(editor.isDimVisible)
        XCTAssertEqual(editor.panelCornerRadius, AddressEditorView.panelRadius)
        XCTAssertEqual(editor.panelFrame.minX, editor.safeAreaInsets.left + AddressEditorView.panelMargin, accuracy: 1.0)
        let expectedMaxX = editor.bounds.width - editor.safeAreaInsets.right - AddressEditorView.panelMargin
        XCTAssertEqual(editor.panelFrame.maxX, expectedMaxX, accuracy: 1.0)
        let expectedMinY = editor.safeAreaInsets.top + TopBarView.barHeight + 8
        XCTAssertEqual(editor.panelFrame.minY, expectedMinY, accuracy: 1.0)
        XCTAssertLessThan(editor.panelFrame.width, editor.bounds.width)
    }

    func testCompactPanelHasNoRadiusAndNoDone() {
        let editor = makeEditor(placement: .compact)
        editor.layoutIfNeeded()
        XCTAssertFalse(editor.isDimVisible)
        XCTAssertFalse(editor.isDoneVisible)
        XCTAssertEqual(editor.panelCornerRadius, 0)
        XCTAssertTrue(editor.isClearWhileEditing)
    }

    func testDoneVisibilityPerPlacement() {
        let editor = makeEditor(placement: .compact)
        XCTAssertFalse(editor.isDoneVisible)
        editor.applyPlacement(for: .regular)
        XCTAssertTrue(editor.isDoneVisible)
        editor.applyPlacement(for: .compact)
        XCTAssertFalse(editor.isDoneVisible)
    }

    func testDoneCallsOnDone() {
        let editor = makeEditor(placement: .regular)
        XCTAssertTrue(editor.isDoneVisible)
        var didCall = false
        editor.onDone = { didCall = true }
        editor.performDone()
        XCTAssertTrue(didCall)
    }

    func testClearWhileEditingBothPlacements() {
        let editor = makeEditor(placement: .compact)
        XCTAssertTrue(editor.isClearWhileEditing)
        editor.applyPlacement(for: .regular)
        XCTAssertTrue(editor.isClearWhileEditing)
        editor.applyPlacement(for: .compact)
        XCTAssertTrue(editor.isClearWhileEditing)
    }

    func testNoMicAffordanceEitherPlacement() {
        for placement: ChromePlacement in [.compact, .regular] {
            let editor = makeEditor(placement: placement)
            XCTAssertFalse(hasMicAffordance(in: editor))
        }
    }

    func testDimNeverDismissesAndPassesThrough() {
        let editor = makeEditor(placement: .regular)
        XCTAssertTrue(editor.isDimVisible)
        XCTAssertTrue(editor.isDimInteractionDisabled)
        editor.applyPlacement(for: .compact)
        XCTAssertFalse(editor.isDimVisible)
        XCTAssertTrue(editor.isDimInteractionDisabled)
    }

    func testStartPageVisibleAroundPanelWhenIdle() {
        let editor = makeEditor(placement: .regular)
        editor.configure(text: "", suggestions: [], engine: .google)
        XCTAssertFalse(editor.areSuggestionsVisible)
        XCTAssertTrue(editor.isDimVisible)
        XCTAssertTrue(editor.isDoneVisible)
    }

    private func hasMicAffordance(in view: UIView) -> Bool {
        if let button = view as? UIButton, let label = button.accessibilityLabel?.lowercased(),
           label.contains("mic") || label.contains("dictation") || label.contains("microphone")
        {
            return true
        }
        for subview in view.subviews where hasMicAffordance(in: subview) {
            return true
        }
        return false
    }
}
