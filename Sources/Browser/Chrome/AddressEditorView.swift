// Chrome — Address editing surface with compact inline dismiss and regular popover.
import os
import UIKit

/// Editing surface docked above the keyboard on compact
/// and floating as a blurred popover on regular.
/// Mode 3 shows one inline dismiss trailing the capsule.
@MainActor
final class AddressEditorView: UIView, ChromePlacementDriven {
    nonisolated static let fieldHeight: CGFloat = 44
    nonisolated static let regularHeaderHeight: CGFloat = 56
    nonisolated static let suggestionsMaxHeight: CGFloat = 420
    nonisolated static let panelMaxWidth: CGFloat = 600
    nonisolated static let panelPreferredHeight: CGFloat = 520
    nonisolated static let panelMargin: CGFloat = 24
    nonisolated static let panelTopOffset: CGFloat = 18
    nonisolated static let panelRadius: CGFloat = 28
    nonisolated static var dimAlpha: CGFloat {
        SheetDim.alpha
    }

    nonisolated static let dismissDiameter: CGFloat = 44

    var chromePlacement: ChromePlacement = .compact {
        didSet {
            if oldValue != chromePlacement {
                applyPlacement()
            }
        }
    }

    var onSelectSuggestion: (@MainActor (Suggestion) -> Void)?
    var onSelectFavorite: (@MainActor (URL) -> Void)?
    var onSubmit: (@MainActor (String) -> Void)?
    var onTextChanged: (@MainActor (String) -> Void)?
    var onDone: (@MainActor () -> Void)?

    var isNonDuoPhone: Bool = false {
        didSet {
            if oldValue != isNonDuoPhone {
                updateVisibleContent()
            }
        }
    }

    var isEditing: Bool = false {
        didSet {
            if oldValue != isEditing {
                updateVisibleContent()
            }
        }
    }

    var isPrivateMode: Bool = false

    private(set) var suggestions: [Suggestion] = []
    private(set) var suggestionSections: [SuggestionSection] = []
    private(set) var favorites: [Bookmark] = []
    private var activePageURL: URL?
    private(set) var searchEngine: SearchEngine = .google

    // MARK: - Compact Hierarchy

    let contentAreaContainer = UIView()
    let suggestionsTableView = UITableView(frame: .zero, style: .plain)
    let bottomBarContainer = UIView()
    let fieldRowStack = UIStackView()
    let capsuleView = UIView()
    let capsuleBackground = UIVisualEffectView(effect: GlassEffect.make())
    let textField = UITextField()
    let inlineDismissButton = UIButton(type: .system)
    let inputErrorLabel = UILabel()

    // MARK: - Regular Floating Popover Hierarchy

    let dismissBackdropControl = UIControl()
    let regularCardShadowView = UIView()
    let regularCardView = UIView()
    let regularBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    let regularHeaderRow = UIView()
    let leadingIconBadge = UIView()
    let leadingIconImageView = UIImageView()
    let regularErrorLabel = UILabel()
    let regularHeaderDivider = UIView()
    let regularBodyContainer = UIView()
    let regularFavoritesContainer = UIView()
    let favoritesHeaderLabel = UILabel()
    let favoritesCollectionView: UICollectionView
    let favoritesFlowLayout = UICollectionViewFlowLayout()
    let favoritesEmptyLabel = UILabel()

    var compactConstraints: [NSLayoutConstraint] = []
    var regularConstraints: [NSLayoutConstraint] = []
    var compactTextFieldConstraints: [NSLayoutConstraint] = []
    var regularTextFieldConstraints: [NSLayoutConstraint] = []
    var compactTableConstraints: [NSLayoutConstraint] = []
    var regularTableConstraints: [NSLayoutConstraint] = []
    var suggestionsMaxHeightConstraint: NSLayoutConstraint?
    var inputErrorTopConstraint: NSLayoutConstraint?
    var inputErrorBottomConstraint: NSLayoutConstraint?
    var inputErrorHeightConstraint: NSLayoutConstraint?
    var fieldRowStackTopConstraint: NSLayoutConstraint?
    var regularErrorHeightConstraint: NSLayoutConstraint?
    var regularCardTopConstraint: NSLayoutConstraint?

    /// Injected toolbar reference so the regular popover aligns directly with the
    /// toolbar's top edge when mounted in the browser hierarchy.
    weak var toolbarAnchorView: UIView? {
        didSet {
            if oldValue !== toolbarAnchorView {
                refreshRegularTopConstraint()
            }
        }
    }

    private var initialLoadedText: String = ""
    var isTypingMode: Bool = false
    private var pendingInlineCompletion: InlineCompletion?
    private var isApplyingInline: Bool = false

    override init(frame: CGRect) {
        favoritesFlowLayout.scrollDirection = .vertical
        favoritesFlowLayout.minimumInteritemSpacing = 16
        favoritesFlowLayout.minimumLineSpacing = 16
        favoritesFlowLayout.sectionInset = UIEdgeInsets(top: 12, left: 24, bottom: 20, right: 24)
        favoritesFlowLayout.itemSize = CGSize(width: FavoriteTileCell.tileLength, height: FavoriteTileCell.cellHeight)
        favoritesCollectionView = UICollectionView(frame: .zero, collectionViewLayout: favoritesFlowLayout)
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        favoritesFlowLayout.scrollDirection = .vertical
        favoritesFlowLayout.minimumInteritemSpacing = 16
        favoritesFlowLayout.minimumLineSpacing = 16
        favoritesFlowLayout.sectionInset = UIEdgeInsets(top: 12, left: 24, bottom: 20, right: 24)
        favoritesFlowLayout.itemSize = CGSize(width: FavoriteTileCell.tileLength, height: FavoriteTileCell.cellHeight)
        favoritesCollectionView = UICollectionView(frame: .zero, collectionViewLayout: favoritesFlowLayout)
        super.init(coder: coder)
        setup()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                input: UIKeyCommand.inputEscape,
                modifierFlags: [],
                action: #selector(handleDone)
            )
        ]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        capsuleView.layer.cornerRadius = capsuleView.bounds.height / 2
        capsuleBackground.layer.cornerRadius = capsuleBackground.bounds.height / 2
        if #available(iOS 26.0, *) {
            capsuleBackground.cornerConfiguration = .capsule()
        }
        if chromePlacement == .regular {
            regularCardShadowView.layer.shadowPath = UIBezierPath(
                roundedRect: regularCardShadowView.bounds,
                cornerRadius: Self.panelRadius
            ).cgPath
            updateFavoritesItemSize()
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        refreshRegularTopConstraint()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha >= 0.01, isEditing else { return nil }

        // Prioritize dismiss so taps never fall through to rows behind.
        if chromePlacement == .compact, !inlineDismissButton.isHidden {
            let buttonFrame = inlineDismissButton.convert(inlineDismissButton.bounds, to: self)
            if buttonFrame.contains(point) {
                return inlineDismissButton
            }
        }
        if chromePlacement == .compact, capsuleView.superview != nil {
            let capsuleFrame = capsuleView.convert(capsuleView.bounds, to: self)
            if capsuleFrame.contains(point) {
                let localPoint = convert(point, to: capsuleView)
                if let hit = capsuleView.hitTest(localPoint, with: event) {
                    return hit
                }
                return textField.isUserInteractionEnabled ? textField : capsuleView
            }
        }
        let hit = super.hitTest(point, with: event)
        if chromePlacement == .compact, hit === contentAreaContainer || hit === self, suggestionsTableView.isHidden {
            return nil
        }
        return hit
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let didBecome = textField.becomeFirstResponder()
        if didBecome {
            textField.selectAll(nil)
        }
        return didBecome
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        clearInlineCompletionState()
        return textField.resignFirstResponder()
    }

    func reloadContent() {
        favoritesCollectionView.reloadData()
        updateRegularLeadingIcon()
        updateVisibleContent()
    }

    func configure(
        text: String?,
        suggestions: [Suggestion],
        engine: SearchEngine,
        activeURL: URL? = nil,
        favorites: [Bookmark] = []
    ) {
        searchEngine = engine
        activePageURL = activeURL
        self.favorites = favorites
        initialLoadedText = text ?? ""
        textField.text = text
        isTypingMode = false
        clearInlineCompletionState()
        clearInputError()
        favoritesCollectionView.reloadData()
        updateRegularLeadingIcon()
        setSuggestions(suggestions)
        updateVisibleContent()
    }

    func setFavorites(_ favorites: [Bookmark]) {
        self.favorites = favorites
        favoritesCollectionView.reloadData()
        updateVisibleContent()
    }

    func setSuggestions(_ suggestions: [Suggestion]) {
        self.suggestions = suggestions
        buildSuggestionSections()
        suggestionsTableView.reloadData()
        updateVisibleContent()
    }

    private func buildSuggestionSections() {
        var sections: [SuggestionSection] = []
        let searchItems = suggestions.filter(\.isSearchSuggestion)
        if !searchItems.isEmpty {
            sections.append(SuggestionSection(
                title: "\(searchEngine.displayName) Suggestions",
                items: searchItems
            ))
        }
        let localItems = suggestions.filter { !$0.isSearchSuggestion }
        if !localItems.isEmpty {
            sections.append(SuggestionSection(
                title: "Bookmarks, History, and Tabs",
                items: localItems
            ))
        }
        suggestionSections = sections
    }

    func showInputError(_ message: String) {
        inputErrorLabel.text = message
        inputErrorLabel.isHidden = false
        regularErrorLabel.text = message
        regularErrorLabel.isHidden = false
        updateInputErrorConstraints()
        updateVisibleContent()
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    func clearInputError() {
        inputErrorLabel.text = nil
        inputErrorLabel.isHidden = true
        regularErrorLabel.text = nil
        regularErrorLabel.isHidden = true
        updateInputErrorConstraints()
        updateVisibleContent()
    }

    func applyInlineCompletion(_ completion: InlineCompletion, forTypedPrefix typed: String) {
        isApplyingInline = true
        defer { isApplyingInline = false }
        textField.text = completion.text
        // UITextInput offsets are UTF-16; Character counts split emoji surrogates.
        let prefixLength = min((typed as NSString).length, (completion.text as NSString).length)
        if let start = textField.position(from: textField.beginningOfDocument, offset: prefixLength),
           let selection = textField.textRange(from: start, to: textField.endOfDocument)
        {
            textField.selectedTextRange = selection
        }
        pendingInlineCompletion = completion
        leadingIconImageView.image = FaviconService.shared.cachedFaviconOrMonogram(
            for: completion.sourceURL,
            size: 20,
            isPrivate: isPrivateMode
        )
        leadingIconImageView.tintColor = nil
    }

    func clearInlineCompletionState() {
        pendingInlineCompletion = nil
        updateRegularLeadingIcon()
    }

    func didChangeFieldSelection() {
        if isApplyingInline {
            return
        }
        guard let pending = pendingInlineCompletion else {
            return
        }
        // Keep the programmatic suffix selection; caret moves collapse or leave the end.
        guard let current = textField.text, current == pending.text,
              let selected = textField.selectedTextRange,
              textField.offset(from: selected.start, to: selected.end) > 0,
              textField.offset(from: selected.end, to: textField.endOfDocument) == 0
        else {
            clearInlineCompletionState()
            return
        }
    }

    var fieldText: String {
        textField.text ?? ""
    }

    /// Neither placement dims or blurs the background behind the editor:
    /// compact reveals the Start Page, regular keeps the live page crisp.
    var isDimVisible: Bool {
        false
    }

    var areSuggestionsVisible: Bool {
        !suggestionsTableView.isHidden
    }

    var areFavoritesVisible: Bool {
        chromePlacement == .regular && !regularCardShadowView.isHidden && !regularFavoritesContainer.isHidden
    }

    var isOutsideDismissEnabled: Bool {
        chromePlacement == .regular && !dismissBackdropControl.isHidden && dismissBackdropControl.isUserInteractionEnabled
    }

    var isCompactLayoutActive: Bool {
        compactConstraints.allSatisfy(\.isActive) && !regularConstraints.contains(where: \.isActive)
    }

    var isRegularLayoutActive: Bool {
        regularConstraints.allSatisfy(\.isActive) && !compactConstraints.contains(where: \.isActive)
    }

    var isSuggestionsHeightCapped: Bool {
        suggestionsMaxHeightConstraint?.isActive ?? false
    }

    var suggestionsMaxHeight: CGFloat {
        suggestionsMaxHeightConstraint?.constant ?? Self.suggestionsMaxHeight
    }

    /// Compact nonDuoPhone editing shows one inline dismiss
    /// trailing the capsule; all other states hide it.
    var isDismissVisible: Bool {
        !inlineDismissButton.isHidden
    }

    func performDone() {
        handleDone()
    }

    func performOutsideTap() {
        dismissBackdropControl.sendActions(for: .touchUpInside)
    }

    var isClearWhileEditing: Bool {
        textField.clearButtonMode == .whileEditing
    }

    var textFieldForTesting: UITextField {
        textField
    }

    var isTypingModeForTesting: Bool {
        isTypingMode
    }

    var pendingInlineCompletionForTesting: InlineCompletion? {
        pendingInlineCompletion
    }

    var isApplyingInlineForTesting: Bool {
        isApplyingInline
    }

    var panelFrame: CGRect {
        chromePlacement == .regular ? regularCardShadowView.frame : bottomBarContainer.frame
    }

    var panelCornerRadius: CGFloat {
        chromePlacement == .regular ? regularCardView.layer.cornerRadius : bottomBarContainer.layer.cornerRadius
    }

    func applyPlacement() {
        refreshRegularTopConstraint()
        let isRegular = chromePlacement == .regular

        NSLayoutConstraint.deactivate(compactConstraints)
        NSLayoutConstraint.deactivate(regularConstraints)
        NSLayoutConstraint.deactivate(compactTextFieldConstraints)
        NSLayoutConstraint.deactivate(regularTextFieldConstraints)
        NSLayoutConstraint.deactivate(compactTableConstraints)
        NSLayoutConstraint.deactivate(regularTableConstraints)

        let targetFieldParent: UIView = isRegular ? regularHeaderRow : capsuleView
        if textField.superview !== targetFieldParent {
            textField.removeFromSuperview()
            targetFieldParent.addSubview(textField)
        }

        let targetTableParent: UIView = isRegular ? regularBodyContainer : contentAreaContainer
        if suggestionsTableView.superview !== targetTableParent {
            suggestionsTableView.removeFromSuperview()
            targetTableParent.addSubview(suggestionsTableView)
        }

        contentAreaContainer.isHidden = isRegular
        bottomBarContainer.isHidden = isRegular
        dismissBackdropControl.isHidden = !isRegular
        regularCardShadowView.isHidden = !isRegular

        suggestionsTableView.backgroundColor = isRegular ? .clear : .systemBackground

        NSLayoutConstraint.activate(isRegular ? regularConstraints : compactConstraints)
        NSLayoutConstraint.activate(isRegular ? regularTextFieldConstraints : compactTextFieldConstraints)
        NSLayoutConstraint.activate(isRegular ? regularTableConstraints : compactTableConstraints)

        updateRegularLeadingIcon()
        updateVisibleContent()
    }

    func handleTextFieldEditingChanged() {
        if isApplyingInline {
            return
        }
        clearInputError()
        let currentText = textField.text ?? ""
        if currentText.isEmpty {
            clearInlineCompletionState()
        }
        isTypingMode = !currentText.isEmpty
        updateRegularLeadingIcon()
        updateVisibleContent()
        onTextChanged?(currentText)
    }

    func updateRegularLeadingIcon() {
        if let completion = pendingInlineCompletion {
            leadingIconImageView.image = FaviconService.shared.cachedFaviconOrMonogram(
                for: completion.sourceURL,
                size: 20,
                isPrivate: isPrivateMode
            )
            leadingIconImageView.tintColor = nil
            return
        }
        let trimmed = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !isTypingMode, !trimmed.isEmpty, let url = activePageURL {
            leadingIconImageView.image = FaviconService.shared.cachedFaviconOrMonogram(
                for: url,
                size: 20,
                isPrivate: isPrivateMode
            )
            leadingIconImageView.tintColor = nil
        } else {
            let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            leadingIconImageView.image = UIImage(systemName: "magnifyingglass", withConfiguration: config)
            leadingIconImageView.tintColor = .secondaryLabel
        }
    }

    func updateVisibleContent() {
        let shouldShowInlineDismiss = chromePlacement == .compact && isEditing
        inlineDismissButton.isHidden = !shouldShowInlineDismiss

        // Keep stale taps off rows behind the dismiss control.
        if chromePlacement == .compact {
            bottomBarContainer.bringSubviewToFront(fieldRowStack)
        }

        let currentText = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasText = !currentText.isEmpty
        let shouldShowSuggestions: Bool = if isNonDuoPhone, chromePlacement == .compact {
            hasText && !suggestions.isEmpty
        } else {
            (isTypingMode && hasText) || (!hasText && !suggestions.isEmpty)
        }

        if chromePlacement == .regular {
            suggestionsTableView.isHidden = !shouldShowSuggestions
            regularFavoritesContainer.isHidden = shouldShowSuggestions
            favoritesCollectionView.isHidden = favorites.isEmpty
            favoritesEmptyLabel.isHidden = !favorites.isEmpty
            regularHeaderDivider.isHidden = !(shouldShowSuggestions || !regularErrorLabel.isHidden)
            contentAreaContainer.backgroundColor = .clear
            backgroundColor = .clear
            return
        }

        if shouldShowSuggestions {
            suggestionsTableView.isHidden = false
            contentAreaContainer.backgroundColor = .systemBackground
            backgroundColor = .systemBackground
        } else {
            suggestionsTableView.isHidden = true
            contentAreaContainer.backgroundColor = .clear
            backgroundColor = .clear
        }
    }

    @objc func handleCapsuleTap() {
        textField.becomeFirstResponder()
    }

    @objc func handleDone() {
        clearInlineCompletionState()
        textField.resignFirstResponder()
        onDone?()
    }
}

// MARK: - SuggestionSection

struct SuggestionSection: Equatable, Sendable {
    let title: String
    let items: [Suggestion]
}
