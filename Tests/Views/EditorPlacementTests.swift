// Editor — Placement, floating regular popover card, Favorites/Suggestions switching, and outside-tap tests.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class EditorPlacementTests: XCTestCase {
    private func makeEditor(
        placement: ChromePlacement = .compact,
        frame: CGRect = TestWindow.defaultFrame
    ) -> AddressEditorView {
        let editor = AddressEditorView()
        editor.frame = CGRect(origin: .zero, size: frame.size)
        TestWindow.attach(editor, frame: frame)
        editor.frame = CGRect(origin: .zero, size: frame.size)
        editor.applyPlacement(for: placement)
        editor.layoutIfNeeded()
        return editor
    }

    private struct RegularRootFixture {
        let parent: UIViewController
        let root: BrowserRootViewController
        let tabID: UUID
    }

    private func makeRegularRootWithLoadedTab() throws -> RegularRootFixture {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        let parent = UIViewController()
        let innerFrame = CGRect(x: 0, y: 0, width: 951, height: 669)
        TestWindow.attach(parent, frame: innerFrame)
        parent.addChild(root)
        root.traitOverrides.horizontalSizeClass = .regular
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

        let url = try XCTUnwrap(URL(string: "https://www.apple.com"))
        let record = TabRecord(url: url, title: "Apple", isPrivate: false)
        root.tabs = [record]
        root.tabPool.create(record)
        root.selectedTabID = record.id
        root.displaySelectedTabForTest(id: record.id)
        root.applyStructuralLayout()
        root.view.layoutIfNeeded()
        return RegularRootFixture(parent: parent, root: root, tabID: record.id)
    }

    func testCompactKeepsBottomDockAboveKeyboard() {
        let editor = makeEditor(placement: .compact)
        XCTAssertEqual(editor.chromePlacement, .compact)
        XCTAssertFalse(editor.isDimVisible)
        XCTAssertFalse(editor.isDoneVisible)
        XCTAssertFalse(editor.isOutsideDismissEnabled)
        XCTAssertFalse(editor.areFavoritesVisible)
        XCTAssertTrue(editor.isCompactLayoutActive)
        XCTAssertFalse(editor.isRegularLayoutActive)
        XCTAssertFalse(editor.isSuggestionsHeightCapped)
    }

    func testRegularShowsFloatingBlurredPopoverWithoutDimOrBlueCheck() {
        let innerFrame = CGRect(x: 0, y: 0, width: 951, height: 669)
        let editor = makeEditor(placement: .regular, frame: innerFrame)
        XCTAssertEqual(editor.chromePlacement, .regular)
        XCTAssertTrue(editor.isRegularLayoutActive)
        XCTAssertFalse(editor.isCompactLayoutActive)
        XCTAssertFalse(editor.isDimVisible)
        XCTAssertFalse(editor.isDoneVisible)
        XCTAssertTrue(editor.isOutsideDismissEnabled)
    }

    func testSuggestionsTableCappedAt420OnRegular() {
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

    func testStaticsMatchSafariRegularPopoverContract() {
        XCTAssertEqual(TopBarView.barHeight, 84)
        XCTAssertEqual(TabStripView.stripHeight, 44)
        XCTAssertEqual(AddressEditorView.panelMaxWidth, 600)
        XCTAssertEqual(AddressEditorView.panelPreferredHeight, 520)
        XCTAssertEqual(AddressEditorView.panelMargin, 24)
        XCTAssertEqual(AddressEditorView.panelRadius, 28)
        XCTAssertEqual(AddressEditorView.panelTopOffset, 18)
        XCTAssertEqual(AddressEditorView.regularHeaderHeight, 56)
        XCTAssertEqual(AddressEditorView.suggestionsMaxHeight, 420)
    }

    func testRegularPopoverGeometryCentersAt600MaxWidthAlignedWithTopBar() {
        let innerFrame = CGRect(x: 0, y: 0, width: 951, height: 669)
        let editor = makeEditor(placement: .regular, frame: innerFrame)
        XCTAssertTrue(editor.isRegularLayoutActive)
        XCTAssertEqual(editor.panelCornerRadius, AddressEditorView.panelRadius)
        XCTAssertEqual(editor.panelFrame.width, AddressEditorView.panelMaxWidth, accuracy: 1.0)
        XCTAssertEqual(editor.panelFrame.midX, innerFrame.midX, accuracy: 1.0)
        XCTAssertEqual(editor.panelFrame.minY, AddressEditorView.panelTopOffset, accuracy: 1.0)
        // 18 pt top + 28 pt half-header = 46 pt vertical center, matching TopBarView's pill center.
        let headerMidY = editor.panelFrame.minY + AddressEditorView.regularHeaderHeight / 2
        XCTAssertEqual(headerMidY, 46, accuracy: 1.0)
    }

    func testOutsideTapDismissesOnRegularOnly() {
        let innerFrame = CGRect(x: 0, y: 0, width: 951, height: 669)
        let editor = makeEditor(placement: .regular, frame: innerFrame)
        var didDismiss = false
        editor.onDone = { didDismiss = true }
        XCTAssertTrue(editor.isOutsideDismissEnabled)
        editor.performOutsideTap()
        XCTAssertTrue(didDismiss)

        editor.applyPlacement(for: .compact)
        XCTAssertFalse(editor.isOutsideDismissEnabled)
    }

    func testRegularShowsFavoritesWhenIdleAndSwitchesToSuggestionsOnTyping() throws {
        let innerFrame = CGRect(x: 0, y: 0, width: 951, height: 669)
        let editor = makeEditor(placement: .regular, frame: innerFrame)
        let appleURL = try XCTUnwrap(URL(string: "https://www.apple.com"))
        let favorite = Bookmark(title: "Apple", url: appleURL, addedAt: Date(), isFavorite: true)

        editor.configure(
            text: appleURL.absoluteString,
            suggestions: [],
            engine: .google,
            activeURL: appleURL,
            favorites: [favorite]
        )
        XCTAssertTrue(editor.areFavoritesVisible)
        XCTAssertFalse(editor.areSuggestionsVisible)

        let searchSuggestion = Suggestion(kind: .search(query: "macbook"))
        editor.setSuggestions([searchSuggestion])
        // Still idle (isTypingMode == false) with pre-filled URL: Favorites remain shown.
        XCTAssertTrue(editor.areFavoritesVisible)
        XCTAssertFalse(editor.areSuggestionsVisible)

        // Clearing text with non-empty recent-search suggestions surfaces suggestions.
        editor.configure(text: "", suggestions: [searchSuggestion], engine: .google, favorites: [favorite])
        XCTAssertFalse(editor.areFavoritesVisible)
        XCTAssertTrue(editor.areSuggestionsVisible)
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

    func testRegularBeginEditingKeepsWebPageAndTopBarButtonsAsIs() throws {
        let fixture = try makeRegularRootWithLoadedTab()
        let root = fixture.root
        let tabID = fixture.tabID

        root.beginEditing()
        root.view.layoutIfNeeded()

        XCTAssertTrue(root.isEditingAddress)
        // Regular address editing never swaps the live webpage out for StartPageView.
        XCTAssertFalse(root.forcedStartPageTabs.contains(tabID))
        XCTAssertFalse(root.editorView.isHidden)
        XCTAssertTrue(root.pillView.isHidden)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertFalse(root.topBarView.leadingStack.isHidden)
        XCTAssertFalse(root.topBarView.trailingStack.isHidden)
        XCTAssertEqual(root.topBarView.leadingStack.arrangedSubviews.count, 2)
        XCTAssertEqual(root.topBarView.trailingStack.arrangedSubviews.count, 2)
        let trailingLabels = root.topBarView.trailingStack.arrangedSubviews.compactMap(\.accessibilityLabel)
        XCTAssertFalse(trailingLabels.contains("Done"))

        // Floating editor popover sits above TopBarView in z-order.
        let topBarIndex = try XCTUnwrap(root.view.subviews.firstIndex(of: root.topBarView))
        let editorIndex = try XCTUnwrap(root.view.subviews.firstIndex(of: root.editorView))
        XCTAssertGreaterThan(editorIndex, topBarIndex)

        // Tapping outside the popover closes editing and restores the address pill.
        root.editorView.performOutsideTap()
        root.view.layoutIfNeeded()
        XCTAssertFalse(root.isEditingAddress)
        XCTAssertTrue(root.editorView.isHidden)
        XCTAssertFalse(root.pillView.isHidden)
    }

    func testSelectingFavoriteInRegularPopoverLoadsPageAndEndsEditing() throws {
        let fixture = try makeRegularRootWithLoadedTab()
        let root = fixture.root
        let targetURL = try XCTUnwrap(URL(string: "https://example.org"))

        root.beginEditing()
        XCTAssertTrue(root.isEditingAddress)

        root.editorView.onSelectFavorite?(targetURL)
        XCTAssertFalse(root.isEditingAddress)
        XCTAssertTrue(root.editorView.isHidden)
    }

    func testCompactNonDuoEditingShowsInlineDoneAboveKeyboard() {
        let editor = makeEditor(placement: .compact)
        editor.isNonDuoPhone = true
        editor.isEditing = true
        editor.layoutIfNeeded()

        XCTAssertTrue(editor.isDoneVisible)
        XCTAssertEqual(AddressEditorView.fieldHeight, 44)
        XCTAssertEqual(AddressEditorView.doneDiameter, 44)
        guard let done = findDoneButton(in: editor) else {
            XCTFail("Expected inline Done button")
            return
        }
        XCTAssertEqual(done.accessibilityLabel, "Done")
        XCTAssertEqual(done.backgroundColor, .systemBlue)
        XCTAssertEqual(done.tintColor, .white)
        XCTAssertEqual(done.bounds.width, AddressEditorView.doneDiameter, accuracy: 0.5)
        XCTAssertEqual(done.bounds.height, AddressEditorView.doneDiameter, accuracy: 0.5)
        let frameInEditor = done.convert(done.bounds, to: editor)
        let keyboardTop = editor.keyboardLayoutGuide.layoutFrame.minY
        XCTAssertLessThanOrEqual(frameInEditor.maxY, keyboardTop)
    }

    func testCompactInlineDoneHiddenOutsideMode3Editing() {
        let idle = makeEditor(placement: .compact)
        idle.isNonDuoPhone = true
        idle.isEditing = false
        idle.layoutIfNeeded()
        XCTAssertFalse(idle.isDoneVisible)

        let duoEditing = makeEditor(placement: .compact)
        duoEditing.isNonDuoPhone = false
        duoEditing.isEditing = true
        duoEditing.layoutIfNeeded()
        XCTAssertFalse(duoEditing.isDoneVisible)

        let regularEditing = makeEditor(placement: .regular)
        regularEditing.isNonDuoPhone = true
        regularEditing.isEditing = true
        regularEditing.layoutIfNeeded()
        XCTAssertFalse(regularEditing.isDoneVisible)
        XCTAssertTrue(regularEditing.isOutsideDismissEnabled)
    }

    func testMode3EditingHidesBottomStacksAndDismissRestoresBrowsing() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        let phoneFrame = CGRect(x: 0, y: 0, width: 402, height: 874)
        TestWindow.attach(root, frame: phoneFrame)
        root.traitOverrides.horizontalSizeClass = .compact
        root.view.layoutIfNeeded()
        root.applyChromePlacement(for: .compact)
        root.updateRailItems()
        root.view.layoutIfNeeded()

        XCTAssertEqual(root.interfaceMode, .nonDuoPhone)
        XCTAssertFalse(root.bottomLeadingStack.isHidden)
        XCTAssertFalse(root.bottomTrailingStack.isHidden)

        root.beginEditing()
        root.view.layoutIfNeeded()

        XCTAssertTrue(root.isEditingAddress)
        XCTAssertTrue(root.editorView.isDoneVisible)
        XCTAssertTrue(root.bottomLeadingStack.isHidden)
        XCTAssertTrue(root.bottomTrailingStack.isHidden)
        XCTAssertTrue(root.bottomLeadingStack.arrangedSubviews.isEmpty)
        XCTAssertTrue(root.bottomTrailingStack.arrangedSubviews.isEmpty)

        root.editorView.performDone()
        root.view.layoutIfNeeded()

        XCTAssertFalse(root.isEditingAddress)
        XCTAssertFalse(root.editorView.isDoneVisible)
        XCTAssertFalse(root.bottomLeadingStack.isHidden)
        XCTAssertFalse(root.bottomTrailingStack.isHidden)
        let leading = root.bottomLeadingStack.arrangedSubviews.compactMap(\.accessibilityLabel)
        let trailing = root.bottomTrailingStack.arrangedSubviews.compactMap(\.accessibilityLabel)
        XCTAssertEqual(leading, ["Back"])
        XCTAssertEqual(trailing, ["Bookmarks", "Tabs"])
    }

    private func findDoneButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityLabel == "Done" {
            return button
        }
        for subview in view.subviews {
            if let found = findDoneButton(in: subview) {
                return found
            }
        }
        return nil
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
