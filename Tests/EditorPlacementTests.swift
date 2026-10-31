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
}
