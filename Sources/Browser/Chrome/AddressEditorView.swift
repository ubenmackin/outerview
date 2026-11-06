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

    var onSelectSuggestion: ((Suggestion) -> Void)?
    var onSelectFavorite: ((URL) -> Void)?
    var onSubmit: ((String) -> Void)?
    var onTextChanged: ((String) -> Void)?
    var onDone: (() -> Void)?

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

    private(set) var suggestions: [Suggestion] = []
    private(set) var suggestionSections: [SuggestionSection] = []
    private(set) var favorites: [Bookmark] = []
    private var activePageURL: URL?
    private(set) var searchEngine: SearchEngine = .google

    // MARK: - Compact Hierarchy

    private let contentAreaContainer = UIView()
    private let suggestionsTableView = UITableView(frame: .zero, style: .plain)
    private let bottomBarContainer = UIView()
    private let fieldRowStack = UIStackView()
    private let capsuleView = UIView()
    private let capsuleBackground = UIVisualEffectView(effect: GlassEffect.make())
    private let textField = UITextField()
    private let inlineDismissButton = UIButton(type: .system)
    private let inputErrorLabel = UILabel()

    // MARK: - Regular Floating Popover Hierarchy

    private let dismissBackdropControl = UIControl()
    private let regularCardShadowView = UIView()
    private let regularCardView = UIView()
    private let regularBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let regularHeaderRow = UIView()
    private let leadingIconBadge = UIView()
    private let leadingIconImageView = UIImageView()
    private let regularErrorLabel = UILabel()
    private let regularHeaderDivider = UIView()
    private let regularBodyContainer = UIView()
    private let regularFavoritesContainer = UIView()
    private let favoritesHeaderLabel = UILabel()
    private let favoritesCollectionView: UICollectionView
    private let favoritesFlowLayout = UICollectionViewFlowLayout()
    private let favoritesEmptyLabel = UILabel()

    private var compactConstraints: [NSLayoutConstraint] = []
    private var regularConstraints: [NSLayoutConstraint] = []
    private var compactTextFieldConstraints: [NSLayoutConstraint] = []
    private var regularTextFieldConstraints: [NSLayoutConstraint] = []
    private var compactTableConstraints: [NSLayoutConstraint] = []
    private var regularTableConstraints: [NSLayoutConstraint] = []
    private var suggestionsMaxHeightConstraint: NSLayoutConstraint!
    private var inputErrorTopConstraint: NSLayoutConstraint!
    private var inputErrorBottomConstraint: NSLayoutConstraint!
    private var inputErrorHeightConstraint: NSLayoutConstraint!
    private var fieldRowStackTopConstraint: NSLayoutConstraint!
    private var regularErrorHeightConstraint: NSLayoutConstraint!
    private var regularCardTopConstraint: NSLayoutConstraint?

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
        textField.resignFirstResponder()
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

    // MARK: - Private Setup

    private func setup() {
        backgroundColor = .clear
        setupCompactHierarchy()
        setupRegularHierarchy()
        setupSharedInputs()
        setupStaticConstraints()
        setupPlacementConstraints()
        applyPlacement()
    }

    private func setupCompactHierarchy() {
        contentAreaContainer.translatesAutoresizingMaskIntoConstraints = false
        contentAreaContainer.backgroundColor = .clear
        addSubview(contentAreaContainer)

        bottomBarContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomBarContainer.backgroundColor = .clear
        bottomBarContainer.layer.cornerRadius = 0
        addSubview(bottomBarContainer)

        fieldRowStack.axis = .horizontal
        fieldRowStack.alignment = .center
        fieldRowStack.spacing = 8
        fieldRowStack.translatesAutoresizingMaskIntoConstraints = false
        bottomBarContainer.addSubview(fieldRowStack)

        capsuleView.translatesAutoresizingMaskIntoConstraints = false
        capsuleView.backgroundColor = .clear
        capsuleView.clipsToBounds = true
        capsuleBackground.translatesAutoresizingMaskIntoConstraints = false
        capsuleBackground.clipsToBounds = true
        capsuleBackground.isUserInteractionEnabled = false
        capsuleView.addSubview(capsuleBackground)
        NSLayoutConstraint.activate([
            capsuleBackground.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor),
            capsuleBackground.trailingAnchor.constraint(equalTo: capsuleView.trailingAnchor),
            capsuleBackground.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            capsuleBackground.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor)
        ])

        let capsuleTap = UITapGestureRecognizer(target: self, action: #selector(handleCapsuleTap))
        capsuleView.addGestureRecognizer(capsuleTap)
        fieldRowStack.addArrangedSubview(capsuleView)

        inlineDismissButton.translatesAutoresizingMaskIntoConstraints = false
        var dismissConfig = UIButton.Configuration.glass()
        dismissConfig.title = ""
        dismissConfig.cornerStyle = .capsule
        let dismissSymbol = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        dismissConfig.image = UIImage(systemName: "xmark", withConfiguration: dismissSymbol)
        dismissConfig.baseForegroundColor = .label
        dismissConfig.baseBackgroundColor = .clear
        inlineDismissButton.configuration = dismissConfig
        inlineDismissButton.accessibilityLabel = "Dismiss"
        inlineDismissButton.isHidden = true
        inlineDismissButton.isUserInteractionEnabled = true
        if #available(iOS 26.0, *) {
            inlineDismissButton.cornerConfiguration = .capsule()
        }
        inlineDismissButton.addAction(UIAction { [weak self] _ in self?.handleDone() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            inlineDismissButton.widthAnchor.constraint(equalToConstant: Self.dismissDiameter),
            inlineDismissButton.heightAnchor.constraint(equalToConstant: Self.dismissDiameter)
        ])
        fieldRowStack.addArrangedSubview(inlineDismissButton)

        inputErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        inputErrorLabel.font = .preferredFont(forTextStyle: .footnote)
        inputErrorLabel.adjustsFontForContentSizeCategory = true
        inputErrorLabel.textColor = .systemRed
        inputErrorLabel.numberOfLines = 2
        inputErrorLabel.isHidden = true
        bottomBarContainer.addSubview(inputErrorLabel)

        // Keep the field row tappable above the keyboard.
        contentAreaContainer.isUserInteractionEnabled = true
        bottomBarContainer.isUserInteractionEnabled = true
        fieldRowStack.isUserInteractionEnabled = true
        capsuleView.isUserInteractionEnabled = true
        bottomBarContainer.bringSubviewToFront(fieldRowStack)
    }

    private func setupSharedInputs() {
        suggestionsTableView.translatesAutoresizingMaskIntoConstraints = false
        suggestionsTableView.backgroundColor = .systemBackground
        suggestionsTableView.keyboardDismissMode = .onDrag
        suggestionsTableView.rowHeight = UITableView.automaticDimension
        suggestionsTableView.estimatedRowHeight = 60
        suggestionsTableView.dataSource = self
        suggestionsTableView.delegate = self
        suggestionsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "SuggestionCell")
        contentAreaContainer.addSubview(suggestionsTableView)

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .go
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .webSearch
        textField.placeholder = AddressBarView.placeholder
        textField.accessibilityLabel = "Address or search query"
        textField.adjustsFontForContentSizeCategory = true
        textField.delegate = self
        textField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.clearInputError()
            let currentText = self.textField.text ?? ""
            self.isTypingMode = !currentText.isEmpty
            self.updateRegularLeadingIcon()
            self.updateVisibleContent()
            self.onTextChanged?(currentText)
        }, for: .editingChanged)
        capsuleView.addSubview(textField)
    }

    private func setupStaticConstraints() {
        inputErrorTopConstraint = inputErrorLabel.topAnchor.constraint(
            equalTo: bottomBarContainer.topAnchor
        )
        inputErrorBottomConstraint = inputErrorLabel.bottomAnchor.constraint(
            equalTo: fieldRowStack.topAnchor, constant: -4
        )
        fieldRowStackTopConstraint = fieldRowStack.topAnchor.constraint(
            equalTo: bottomBarContainer.topAnchor
        )
        inputErrorHeightConstraint = inputErrorLabel.heightAnchor.constraint(equalToConstant: 0)
        regularErrorHeightConstraint = regularErrorLabel.heightAnchor.constraint(equalToConstant: 0)

        let headerHeight = regularHeaderRow.heightAnchor.constraint(equalToConstant: Self.regularHeaderHeight)
        headerHeight.priority = UILayoutPriority(999)
        let badgeLeading = leadingIconBadge.leadingAnchor.constraint(equalTo: regularHeaderRow.leadingAnchor, constant: 18)
        badgeLeading.priority = UILayoutPriority(999)
        let favHeaderTop = favoritesHeaderLabel.topAnchor.constraint(equalTo: regularFavoritesContainer.topAnchor, constant: 10)
        favHeaderTop.priority = UILayoutPriority(999)
        let favHeaderLeading = favoritesHeaderLabel.leadingAnchor.constraint(equalTo: regularFavoritesContainer.leadingAnchor, constant: 24)
        favHeaderLeading.priority = UILayoutPriority(999)
        let favHeaderTrailing = favoritesHeaderLabel.trailingAnchor.constraint(lessThanOrEqualTo: regularFavoritesContainer.trailingAnchor, constant: -24)
        favHeaderTrailing.priority = UILayoutPriority(999)
        let favGridTop = favoritesCollectionView.topAnchor.constraint(equalTo: favoritesHeaderLabel.bottomAnchor, constant: 4)
        favGridTop.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            dismissBackdropControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            dismissBackdropControl.trailingAnchor.constraint(equalTo: trailingAnchor),
            dismissBackdropControl.topAnchor.constraint(equalTo: topAnchor),
            dismissBackdropControl.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentAreaContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            contentAreaContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),

            fieldRowStack.leadingAnchor.constraint(equalTo: bottomBarContainer.leadingAnchor),
            fieldRowStack.trailingAnchor.constraint(equalTo: bottomBarContainer.trailingAnchor),
            fieldRowStack.bottomAnchor.constraint(equalTo: bottomBarContainer.bottomAnchor),
            capsuleView.heightAnchor.constraint(equalToConstant: Self.fieldHeight),

            inputErrorLabel.leadingAnchor.constraint(equalTo: bottomBarContainer.leadingAnchor, constant: 8),
            inputErrorLabel.trailingAnchor.constraint(equalTo: bottomBarContainer.trailingAnchor, constant: -8),

            regularCardView.leadingAnchor.constraint(equalTo: regularCardShadowView.leadingAnchor),
            regularCardView.trailingAnchor.constraint(equalTo: regularCardShadowView.trailingAnchor),
            regularCardView.topAnchor.constraint(equalTo: regularCardShadowView.topAnchor),
            regularCardView.bottomAnchor.constraint(equalTo: regularCardShadowView.bottomAnchor),

            regularBlurView.leadingAnchor.constraint(equalTo: regularCardView.leadingAnchor),
            regularBlurView.trailingAnchor.constraint(equalTo: regularCardView.trailingAnchor),
            regularBlurView.topAnchor.constraint(equalTo: regularCardView.topAnchor),
            regularBlurView.bottomAnchor.constraint(equalTo: regularCardView.bottomAnchor),

            regularHeaderRow.topAnchor.constraint(equalTo: regularCardView.topAnchor),
            regularHeaderRow.leadingAnchor.constraint(equalTo: regularCardView.leadingAnchor),
            regularHeaderRow.trailingAnchor.constraint(equalTo: regularCardView.trailingAnchor),
            headerHeight,

            badgeLeading,
            leadingIconBadge.centerYAnchor.constraint(equalTo: regularHeaderRow.centerYAnchor),
            leadingIconBadge.widthAnchor.constraint(equalToConstant: 28),
            leadingIconBadge.heightAnchor.constraint(equalToConstant: 28),

            leadingIconImageView.centerXAnchor.constraint(equalTo: leadingIconBadge.centerXAnchor),
            leadingIconImageView.centerYAnchor.constraint(equalTo: leadingIconBadge.centerYAnchor),
            leadingIconImageView.widthAnchor.constraint(equalToConstant: 20),
            leadingIconImageView.heightAnchor.constraint(equalToConstant: 20),

            regularErrorLabel.topAnchor.constraint(equalTo: regularHeaderRow.bottomAnchor),
            regularErrorLabel.leadingAnchor.constraint(equalTo: regularCardView.leadingAnchor, constant: 24),
            regularErrorLabel.trailingAnchor.constraint(lessThanOrEqualTo: regularCardView.trailingAnchor, constant: -24),

            regularHeaderDivider.topAnchor.constraint(equalTo: regularErrorLabel.bottomAnchor),
            regularHeaderDivider.leadingAnchor.constraint(equalTo: regularCardView.leadingAnchor),
            regularHeaderDivider.trailingAnchor.constraint(equalTo: regularCardView.trailingAnchor),
            regularHeaderDivider.heightAnchor.constraint(equalToConstant: 0.5),

            regularBodyContainer.topAnchor.constraint(equalTo: regularHeaderDivider.bottomAnchor),
            regularBodyContainer.leadingAnchor.constraint(equalTo: regularCardView.leadingAnchor),
            regularBodyContainer.trailingAnchor.constraint(equalTo: regularCardView.trailingAnchor),
            regularBodyContainer.bottomAnchor.constraint(equalTo: regularCardView.bottomAnchor),

            regularFavoritesContainer.topAnchor.constraint(equalTo: regularBodyContainer.topAnchor),
            regularFavoritesContainer.leadingAnchor.constraint(equalTo: regularBodyContainer.leadingAnchor),
            regularFavoritesContainer.trailingAnchor.constraint(equalTo: regularBodyContainer.trailingAnchor),
            regularFavoritesContainer.bottomAnchor.constraint(equalTo: regularBodyContainer.bottomAnchor),

            favHeaderTop,
            favHeaderLeading,
            favHeaderTrailing,

            favGridTop,
            favoritesCollectionView.leadingAnchor.constraint(equalTo: regularFavoritesContainer.leadingAnchor),
            favoritesCollectionView.trailingAnchor.constraint(equalTo: regularFavoritesContainer.trailingAnchor),
            favoritesCollectionView.bottomAnchor.constraint(equalTo: regularFavoritesContainer.bottomAnchor),

            favoritesEmptyLabel.centerXAnchor.constraint(equalTo: regularFavoritesContainer.centerXAnchor),
            favoritesEmptyLabel.centerYAnchor.constraint(equalTo: regularFavoritesContainer.centerYAnchor),
            favoritesEmptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: regularFavoritesContainer.leadingAnchor, constant: 24),
            favoritesEmptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: regularFavoritesContainer.trailingAnchor, constant: -24)
        ])
        updateInputErrorConstraints()
    }

    private func updateInputErrorConstraints() {
        guard inputErrorTopConstraint != nil, fieldRowStackTopConstraint != nil else { return }
        let hasError = !inputErrorLabel.isHidden
        if hasError {
            fieldRowStackTopConstraint.isActive = false
            inputErrorHeightConstraint.isActive = false
            inputErrorBottomConstraint.constant = -4
            inputErrorTopConstraint.isActive = true
            inputErrorBottomConstraint.isActive = true
            regularErrorHeightConstraint.isActive = false
        } else {
            inputErrorTopConstraint.isActive = false
            inputErrorBottomConstraint.isActive = false
            fieldRowStackTopConstraint.isActive = true
            inputErrorHeightConstraint.isActive = true
            regularErrorHeightConstraint.isActive = true
        }
    }

    private func resolveToolbarView() -> UIView? {
        if let toolbarAnchorView {
            return toolbarAnchorView
        }
        guard let parent = superview else { return nil }
        for subview in parent.subviews where subview is TopBarView {
            return subview
        }
        return nil
    }

    /// Pins the floating regular card 18 pt below the toolbar's top edge so the
    /// 56 pt input row centers directly on the 46 pt address bar line.
    private func refreshRegularTopConstraint() {
        guard let current = regularCardTopConstraint, let toolbar = resolveToolbarView() else { return }
        if let second = current.secondItem as? UIView, second === toolbar {
            return
        }
        let wasActive = current.isActive
        current.isActive = false
        if let index = regularConstraints.firstIndex(where: { $0 === current }) {
            regularConstraints.remove(at: index)
        }
        let replacement = regularCardShadowView.topAnchor.constraint(
            equalTo: toolbar.topAnchor,
            constant: Self.panelTopOffset
        )
        regularCardTopConstraint = replacement
        regularConstraints.append(replacement)
        if wasActive, chromePlacement == .regular {
            replacement.isActive = true
        }
    }

    private func setupPlacementConstraints() {
        let compactFieldLead = textField.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor, constant: 16)
        compactFieldLead.priority = UILayoutPriority(999)
        let compactFieldTrail = textField.trailingAnchor.constraint(equalTo: capsuleView.trailingAnchor, constant: -12)
        compactFieldTrail.priority = UILayoutPriority(999)
        compactTextFieldConstraints = [
            compactFieldLead,
            compactFieldTrail,
            textField.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            textField.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor)
        ]

        let regularFieldLead = textField.leadingAnchor.constraint(equalTo: leadingIconBadge.trailingAnchor, constant: 12)
        regularFieldLead.priority = UILayoutPriority(999)
        let regularFieldTrail = textField.trailingAnchor.constraint(equalTo: regularHeaderRow.trailingAnchor, constant: -16)
        regularFieldTrail.priority = UILayoutPriority(999)
        regularTextFieldConstraints = [
            regularFieldLead,
            regularFieldTrail,
            textField.topAnchor.constraint(equalTo: regularHeaderRow.topAnchor),
            textField.bottomAnchor.constraint(equalTo: regularHeaderRow.bottomAnchor)
        ]

        compactTableConstraints = [
            suggestionsTableView.leadingAnchor.constraint(equalTo: contentAreaContainer.leadingAnchor),
            suggestionsTableView.trailingAnchor.constraint(equalTo: contentAreaContainer.trailingAnchor),
            suggestionsTableView.topAnchor.constraint(equalTo: contentAreaContainer.topAnchor),
            suggestionsTableView.bottomAnchor.constraint(equalTo: contentAreaContainer.bottomAnchor)
        ]

        suggestionsMaxHeightConstraint = suggestionsTableView.heightAnchor.constraint(
            lessThanOrEqualToConstant: Self.suggestionsMaxHeight
        )
        suggestionsMaxHeightConstraint.priority = .defaultHigh
        regularTableConstraints = [
            suggestionsTableView.leadingAnchor.constraint(equalTo: regularBodyContainer.leadingAnchor),
            suggestionsTableView.trailingAnchor.constraint(equalTo: regularBodyContainer.trailingAnchor),
            suggestionsTableView.topAnchor.constraint(equalTo: regularBodyContainer.topAnchor),
            suggestionsTableView.bottomAnchor.constraint(equalTo: regularBodyContainer.bottomAnchor),
            suggestionsMaxHeightConstraint
        ]

        let compactContentTop = contentAreaContainer.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8)
        let compactContentBottom = contentAreaContainer.bottomAnchor.constraint(equalTo: bottomBarContainer.topAnchor, constant: -8)
        let compactBarBottom = bottomBarContainer.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor, constant: -8)
        let compactBarLeading = bottomBarContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        let compactBarTrailing = bottomBarContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        compactConstraints = [
            compactContentTop, compactContentBottom, compactBarBottom,
            compactBarLeading, compactBarTrailing
        ]

        let regularTop = regularCardShadowView.topAnchor.constraint(
            equalTo: topAnchor,
            constant: Self.panelTopOffset
        )
        regularCardTopConstraint = regularTop
        let regularCenterX = regularCardShadowView.centerXAnchor.constraint(equalTo: centerXAnchor)
        let regularWidthCap = regularCardShadowView.widthAnchor.constraint(
            lessThanOrEqualToConstant: Self.panelMaxWidth
        )
        let regularWidthFill = regularCardShadowView.widthAnchor.constraint(
            equalTo: safeAreaLayoutGuide.widthAnchor,
            constant: -(Self.panelMargin * 2)
        )
        regularWidthFill.priority = .defaultHigh
        let regularMinLeading = regularCardShadowView.leadingAnchor.constraint(
            greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor,
            constant: Self.panelMargin
        )
        regularMinLeading.priority = UILayoutPriority(999)
        let regularMaxTrailing = regularCardShadowView.trailingAnchor.constraint(
            lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor,
            constant: -Self.panelMargin
        )
        regularMaxTrailing.priority = UILayoutPriority(999)
        let regularPreferredHeight = regularCardShadowView.heightAnchor.constraint(
            equalToConstant: Self.panelPreferredHeight
        )
        regularPreferredHeight.priority = .defaultHigh
        let regularMinHeight = regularCardShadowView.heightAnchor.constraint(
            greaterThanOrEqualToConstant: 180
        )
        regularMinHeight.priority = UILayoutPriority(900)
        let regularMaxBottomKeyboard = regularCardShadowView.bottomAnchor.constraint(
            lessThanOrEqualTo: keyboardLayoutGuide.topAnchor,
            constant: -12
        )
        regularMaxBottomKeyboard.priority = UILayoutPriority(999)
        let regularMaxBottomSafe = regularCardShadowView.bottomAnchor.constraint(
            lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor,
            constant: -12
        )
        regularMaxBottomSafe.priority = UILayoutPriority(999)

        regularConstraints = [
            regularTop,
            regularCenterX,
            regularWidthCap,
            regularWidthFill,
            regularMinLeading,
            regularMaxTrailing,
            regularPreferredHeight,
            regularMinHeight,
            regularMaxBottomKeyboard,
            regularMaxBottomSafe
        ]
    }

    func updateRegularLeadingIcon() {
        let trimmed = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !isTypingMode, !trimmed.isEmpty, let url = activePageURL {
            leadingIconImageView.image = FaviconService.shared.cachedFaviconOrMonogram(for: url, size: 20)
            leadingIconImageView.tintColor = nil
        } else {
            let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            leadingIconImageView.image = UIImage(systemName: "magnifyingglass", withConfiguration: config)
            leadingIconImageView.tintColor = .secondaryLabel
        }
    }

    private func updateFavoritesItemSize() {
        let availableWidth = regularCardView.bounds.width - 48
        guard availableWidth > 80 else { return }
        let columns = availableWidth >= 420 ? 4 : max(2, Int(availableWidth / 96))
        let spacing = CGFloat(max(columns - 1, 0)) * favoritesFlowLayout.minimumInteritemSpacing
        let itemWidth = max(FavoriteTileCell.tileLength, floor((availableWidth - spacing) / CGFloat(columns)))
        let size = CGSize(width: itemWidth, height: FavoriteTileCell.cellHeight)
        if favoritesFlowLayout.itemSize != size {
            favoritesFlowLayout.itemSize = size
            favoritesFlowLayout.invalidateLayout()
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

    @objc private func handleCapsuleTap() {
        textField.becomeFirstResponder()
    }

    @objc private func handleDone() {
        textField.resignFirstResponder()
        onDone?()
    }
}

// MARK: - Regular Hierarchy

extension AddressEditorView {
    private func setupRegularHierarchy() {
        dismissBackdropControl.translatesAutoresizingMaskIntoConstraints = false
        dismissBackdropControl.backgroundColor = .clear
        dismissBackdropControl.isAccessibilityElement = false
        dismissBackdropControl.isHidden = true
        dismissBackdropControl.addAction(UIAction { [weak self] _ in
            self?.handleDone()
        }, for: .touchUpInside)
        addSubview(dismissBackdropControl)

        regularCardShadowView.translatesAutoresizingMaskIntoConstraints = false
        regularCardShadowView.backgroundColor = .clear
        regularCardShadowView.layer.shadowColor = UIColor.black.cgColor
        regularCardShadowView.layer.shadowOpacity = 0.28
        regularCardShadowView.layer.shadowRadius = 28
        regularCardShadowView.layer.shadowOffset = CGSize(width: 0, height: 12)
        regularCardShadowView.isHidden = true
        addSubview(regularCardShadowView)

        regularCardView.translatesAutoresizingMaskIntoConstraints = false
        regularCardView.backgroundColor = .clear
        regularCardView.clipsToBounds = true
        regularCardView.layer.cornerRadius = Self.panelRadius
        regularCardView.layer.cornerCurve = .continuous
        regularCardView.layer.borderWidth = 0.5
        regularCardView.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        regularCardShadowView.addSubview(regularCardView)

        regularBlurView.translatesAutoresizingMaskIntoConstraints = false
        regularBlurView.isUserInteractionEnabled = false
        regularCardView.addSubview(regularBlurView)

        regularHeaderRow.translatesAutoresizingMaskIntoConstraints = false
        regularHeaderRow.backgroundColor = .clear
        let headerTap = UITapGestureRecognizer(target: self, action: #selector(handleCapsuleTap))
        regularHeaderRow.addGestureRecognizer(headerTap)
        regularCardView.addSubview(regularHeaderRow)

        leadingIconBadge.translatesAutoresizingMaskIntoConstraints = false
        // Plain icon host; system glass owns chrome visuals.
        leadingIconBadge.backgroundColor = .clear
        leadingIconBadge.layer.cornerRadius = 0
        leadingIconBadge.clipsToBounds = false
        leadingIconBadge.isUserInteractionEnabled = false
        regularHeaderRow.addSubview(leadingIconBadge)

        leadingIconImageView.translatesAutoresizingMaskIntoConstraints = false
        leadingIconImageView.contentMode = .scaleAspectFit
        leadingIconImageView.tintColor = .secondaryLabel
        leadingIconImageView.layer.cornerRadius = 10
        leadingIconImageView.clipsToBounds = true
        leadingIconBadge.addSubview(leadingIconImageView)

        regularErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        regularErrorLabel.font = .preferredFont(forTextStyle: .footnote)
        regularErrorLabel.adjustsFontForContentSizeCategory = true
        regularErrorLabel.textColor = .systemRed
        regularErrorLabel.numberOfLines = 2
        regularErrorLabel.isHidden = true
        regularCardView.addSubview(regularErrorLabel)

        regularHeaderDivider.translatesAutoresizingMaskIntoConstraints = false
        regularHeaderDivider.backgroundColor = UIColor.separator.withAlphaComponent(0.45)
        regularHeaderDivider.isHidden = true
        regularCardView.addSubview(regularHeaderDivider)

        regularBodyContainer.translatesAutoresizingMaskIntoConstraints = false
        regularBodyContainer.backgroundColor = .clear
        regularCardView.addSubview(regularBodyContainer)

        regularFavoritesContainer.translatesAutoresizingMaskIntoConstraints = false
        regularFavoritesContainer.backgroundColor = .clear
        regularBodyContainer.addSubview(regularFavoritesContainer)

        favoritesHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
        favoritesHeaderLabel.text = "Favorites"
        favoritesHeaderLabel.font = .preferredFont(forTextStyle: .headline)
        favoritesHeaderLabel.adjustsFontForContentSizeCategory = true
        favoritesHeaderLabel.textColor = .label
        regularFavoritesContainer.addSubview(favoritesHeaderLabel)

        favoritesCollectionView.translatesAutoresizingMaskIntoConstraints = false
        favoritesCollectionView.backgroundColor = .clear
        favoritesCollectionView.alwaysBounceVertical = true
        favoritesCollectionView.keyboardDismissMode = .onDrag
        favoritesCollectionView.dataSource = self
        favoritesCollectionView.delegate = self
        favoritesCollectionView.register(
            FavoriteTileCell.self,
            forCellWithReuseIdentifier: FavoriteTileCell.reuseIdentifier
        )
        regularFavoritesContainer.addSubview(favoritesCollectionView)

        favoritesEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        favoritesEmptyLabel.text = "Favorites you add appear here"
        favoritesEmptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        favoritesEmptyLabel.adjustsFontForContentSizeCategory = true
        favoritesEmptyLabel.textColor = .secondaryLabel
        favoritesEmptyLabel.textAlignment = .center
        favoritesEmptyLabel.isHidden = true
        regularFavoritesContainer.addSubview(favoritesEmptyLabel)
    }
}

// MARK: - SuggestionSection

struct SuggestionSection: Equatable, Sendable {
    let title: String
    let items: [Suggestion]
}
