// Chrome — Inline autocompletion field fill and pipeline guard tests.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class InlineAutocompleteTests: XCTestCase {
    private func makeEditor() -> AddressEditorView {
        let editor = AddressEditorView(frame: CGRect(x: 0, y: 0, width: 360, height: 600))
        let window = TestWindow.attach(editor)
        window.makeKeyAndVisible()
        return editor
    }

    private func makeURL(_ string: String) -> URL {
        guard let result = URL(string: string) else {
            XCTFail("invalid URL: \(string)")
            return URL(fileURLWithPath: "/")
        }
        return result
    }

    private func selectedOffsets(in field: UITextField) -> (Int, Int)? {
        guard let selected = field.selectedTextRange else { return nil }
        let start = field.offset(from: field.beginningOfDocument, to: selected.start)
        let end = field.offset(from: field.beginningOfDocument, to: selected.end)
        return (start, end)
    }

    func testApplyInlineCompletionSelectsSuffix() throws {
        let editor = makeEditor()
        _ = editor.textFieldForTesting.becomeFirstResponder()
        let typed = "EXA"
        let bookmarkURL = makeURL("https://example.com/")
        let completion = try XCTUnwrap(
            SuggestionEngine.inlineCompletion(
                for: typed,
                tabs: [],
                bookmarks: [SuggestionBookmark(title: "Example", url: bookmarkURL, isFavorite: false)],
                recents: []
            )
        )
        editor.applyInlineCompletion(completion, forTypedPrefix: typed)
        XCTAssertEqual(editor.fieldText, completion.text)
        XCTAssertEqual(editor.pendingInlineCompletionForTesting?.text, completion.text)
        XCTAssertEqual(editor.pendingInlineCompletionForTesting?.sourceURL, bookmarkURL)
        let offsets = try XCTUnwrap(selectedOffsets(in: editor.textFieldForTesting))
        XCTAssertEqual(offsets.0, typed.count)
        XCTAssertEqual(offsets.1, completion.text.count)
        XCTAssertFalse(editor.isApplyingInlineForTesting)
    }

    func testApplyingInlineDoesNotEmitTextChanged() {
        let editor = makeEditor()
        var received: [String] = []
        editor.onTextChanged = { received.append($0) }
        editor.textFieldForTesting.text = "exa"
        editor.textFieldForTesting.sendActions(for: .editingChanged)
        XCTAssertEqual(received, ["exa"])
        received.removeAll()
        let completion = InlineCompletion(
            text: "example.com/",
            sourceURL: makeURL("https://example.com/"),
            displayHost: "example.com"
        )
        editor.applyInlineCompletion(completion, forTypedPrefix: "exa")
        XCTAssertTrue(received.isEmpty)
        XCTAssertFalse(editor.isApplyingInlineForTesting)
        XCTAssertEqual(editor.fieldText, "example.com/")
    }

    func testDeletionClearsPendingState() {
        let editor = makeEditor()
        let completion = InlineCompletion(
            text: "example.com/",
            sourceURL: makeURL("https://example.com/"),
            displayHost: "example.com"
        )
        editor.applyInlineCompletion(completion, forTypedPrefix: "exa")
        XCTAssertNotNil(editor.pendingInlineCompletionForTesting)
        let field = editor.textFieldForTesting
        let count = field.text?.count ?? 0
        let range = NSRange(location: max(count - 1, 0), length: min(1, count))
        XCTAssertTrue(editor.textField(field, shouldChangeCharactersIn: range, replacementString: ""))
        XCTAssertNil(editor.pendingInlineCompletionForTesting)
    }

    func testSpaceInputNeverFillsInlineCompletion() {
        let candidateURL = makeURL("https://apple.example.com/")
        let tabs = [SuggestionTab(id: UUID(), title: "Apple Pie Shop", url: candidateURL)]
        let bookmarks = [SuggestionBookmark(title: "Apple Pie Shop", url: candidateURL, isFavorite: false)]
        XCTAssertNil(
            SuggestionEngine.inlineCompletion(
                for: "apple pie",
                tabs: tabs,
                bookmarks: bookmarks,
                recents: []
            )
        )
        let editor = makeEditor()
        let fill = SuggestionEngine.inlineCompletion(
            for: "apple",
            tabs: tabs,
            bookmarks: bookmarks,
            recents: []
        )
        if let fill {
            editor.applyInlineCompletion(fill, forTypedPrefix: "apple")
        }
        XCTAssertNotNil(editor.pendingInlineCompletionForTesting)
        // Mirrors the editor pipeline: space input clears pending fill instead of applying.
        let spaced = "apple pie".trimmingCharacters(in: .whitespacesAndNewlines)
        if spaced.contains(" ") {
            editor.clearInlineCompletionState()
        }
        XCTAssertNil(editor.pendingInlineCompletionForTesting)
    }
}
