//
//  AddressEditorView.swift
//  OuterView
//

import os
import UIKit

/// Testable row content for one `Suggestion`, independent of table cells.
struct SuggestionRowViewModel: Hashable, Sendable {
    let systemImageName: String
    let primary: String
    let secondary: String

    static func make(for suggestion: Suggestion, engine: SearchEngine) -> SuggestionRowViewModel {
        switch suggestion.kind {
        case let .site(title, url, isFavorite):
            let (primary, host) = displayHostAndTitle(title: title, url: url)
            return SuggestionRowViewModel(
                systemImageName: isFavorite ? "star.fill" : "globe",
                primary: primary,
                secondary: host
            )
        case let .openTab(title, url, _):
            let (primary, host) = displayHostAndTitle(title: title, url: url)
            return SuggestionRowViewModel(
                systemImageName: "square.on.square",
                primary: primary,
                secondary: "Switch to Tab • \(host)"
            )
        case let .googleSuggest(query):
            return SuggestionRowViewModel(
                systemImageName: "magnifyingglass",
                primary: query,
                secondary: "\(engine.displayName) Suggestions"
            )
        case let .search(query):
            return SuggestionRowViewModel(
                systemImageName: "magnifyingglass",
                primary: query,
                secondary: "Search \(engine.displayName)"
            )
        case let .onPageFind(term):
            return SuggestionRowViewModel(
                systemImageName: "text.magnifyingglass",
                primary: "Find \"\(term)\"",
                secondary: "On This Page"
            )
        }
    }

    private static func displayHostAndTitle(title: String, url: URL) -> (primary: String, host: String) {
        let rawHost = HostFormatter.host(of: url)
        let host = rawHost.isEmpty ? url.absoluteString : rawHost
        let primary = HostFormatter.displayTitle(url: url, title: title)
        return (primary, host)
    }
}

/// Address editor surface:
/// - Initial tap: text field focuses over the underlying unified Start Page.
/// - Typing text: reveals live suggestions in `suggestionsTableView`.
/// - Bottom bar: Full-width capsule field docked above the keyboard. Exit/close is handled by the side rail Done button.
@MainActor
final class AddressEditorView: UIView, ChromePlacementDriven {
    static let fieldHeight: CGFloat = 44
    nonisolated static let suggestionsMaxHeight: CGFloat = 420

    var chromePlacement: ChromePlacement = .compact {
        didSet {
            if oldValue != chromePlacement {
                applyPlacement()
            }
        }
    }

    var onSelectSuggestion: ((Suggestion) -> Void)?
    var onSubmit: ((String) -> Void)?
    var onTextChanged: ((String) -> Void)?

    private(set) var suggestions: [Suggestion] = []
    private var searchEngine: SearchEngine = .google

    // MARK: - Content Area

    private let contentAreaContainer = UIView()
    private let suggestionsTableView = UITableView(frame: .zero, style: .plain)

    // MARK: - Bottom Bar (docked above keyboard)

    private let bottomBarContainer = UIView()
    private let dimView = UIView()
    private let fieldRowStack = UIStackView()
    private let capsuleView = UIView()
    private let capsuleBackground = UIVisualEffectView(effect: GlassEffect.make())
    private let textField = UITextField()
    private let inputErrorLabel = UILabel()

    private var compactConstraints: [NSLayoutConstraint] = []
    private var regularConstraints: [NSLayoutConstraint] = []
    private var suggestionsMaxHeightConstraint: NSLayoutConstraint!

    private var initialLoadedText: String = ""
    private var isTypingMode: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        capsuleView.layer.cornerRadius = capsuleView.bounds.height / 2
        capsuleBackground.layer.cornerRadius = capsuleBackground.bounds.height / 2
        if #available(iOS 26.0, *) {
            capsuleBackground.cornerConfiguration = .capsule()
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // When suggestions are hidden, allow taps in the empty content area
        // to pass through to the underlying Start Page so tiles remain interactive.
        if hit === contentAreaContainer, suggestionsTableView.isHidden {
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
        updateVisibleContent()
    }

    func configure(text: String?, suggestions: [Suggestion], engine: SearchEngine) {
        searchEngine = engine
        initialLoadedText = text ?? ""
        textField.text = text
        isTypingMode = false
        clearInputError()
        setSuggestions(suggestions)
        updateVisibleContent()
    }

    func setSuggestions(_ suggestions: [Suggestion]) {
        self.suggestions = suggestions
        suggestionsTableView.reloadData()
        updateVisibleContent()
    }

    func showInputError(_ message: String) {
        inputErrorLabel.text = message
        inputErrorLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    func clearInputError() {
        inputErrorLabel.text = nil
        inputErrorLabel.isHidden = true
    }

    var fieldText: String {
        textField.text ?? ""
    }

    /// Behavioural placement state for tests: dim visibility, suggestion
    /// visibility, and which layout set is active. Read-only so tests verify
    /// behaviour without mutating layout internals.
    var isDimVisible: Bool {
        !dimView.isHidden
    }

    var areSuggestionsVisible: Bool {
        !suggestionsTableView.isHidden
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

    func applyPlacement() {
        let isRegular = chromePlacement == .regular
        NSLayoutConstraint.deactivate(isRegular ? compactConstraints : regularConstraints)
        NSLayoutConstraint.activate(isRegular ? regularConstraints : compactConstraints)
        dimView.isHidden = !isRegular
        if isRegular {
            sendSubviewToBack(dimView)
        }
        updateVisibleContent()
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .clear

        dimView.translatesAutoresizingMaskIntoConstraints = false
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimView.isHidden = true
        dimView.isUserInteractionEnabled = false
        addSubview(dimView)

        contentAreaContainer.translatesAutoresizingMaskIntoConstraints = false
        contentAreaContainer.backgroundColor = .clear
        addSubview(contentAreaContainer)

        suggestionsTableView.translatesAutoresizingMaskIntoConstraints = false
        suggestionsTableView.backgroundColor = .systemBackground
        suggestionsTableView.keyboardDismissMode = .onDrag
        suggestionsTableView.rowHeight = UITableView.automaticDimension
        suggestionsTableView.estimatedRowHeight = 60
        suggestionsTableView.dataSource = self
        suggestionsTableView.delegate = self
        suggestionsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "SuggestionCell")
        contentAreaContainer.addSubview(suggestionsTableView)

        bottomBarContainer.translatesAutoresizingMaskIntoConstraints = false
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
            self.updateVisibleContent()
            self.onTextChanged?(currentText)
        }, for: .editingChanged)
        capsuleView.addSubview(textField)

        let capsuleTap = UITapGestureRecognizer(target: self, action: #selector(handleCapsuleTap))
        capsuleView.addGestureRecognizer(capsuleTap)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: capsuleView.trailingAnchor, constant: -12),
            textField.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            textField.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor)
        ])

        fieldRowStack.addArrangedSubview(capsuleView)

        inputErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        inputErrorLabel.font = .preferredFont(forTextStyle: .footnote)
        inputErrorLabel.adjustsFontForContentSizeCategory = true
        inputErrorLabel.textColor = .systemRed
        inputErrorLabel.numberOfLines = 2
        inputErrorLabel.isHidden = true
        bottomBarContainer.addSubview(inputErrorLabel)

        NSLayoutConstraint.activate([
            dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimView.topAnchor.constraint(equalTo: topAnchor),
            dimView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentAreaContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            contentAreaContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),

            bottomBarContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            bottomBarContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),

            suggestionsTableView.leadingAnchor.constraint(equalTo: contentAreaContainer.leadingAnchor),
            suggestionsTableView.trailingAnchor.constraint(equalTo: contentAreaContainer.trailingAnchor),
            suggestionsTableView.topAnchor.constraint(equalTo: contentAreaContainer.topAnchor),

            fieldRowStack.leadingAnchor.constraint(equalTo: bottomBarContainer.leadingAnchor),
            fieldRowStack.trailingAnchor.constraint(equalTo: bottomBarContainer.trailingAnchor),
            fieldRowStack.bottomAnchor.constraint(equalTo: bottomBarContainer.bottomAnchor),
            capsuleView.heightAnchor.constraint(equalToConstant: Self.fieldHeight),

            inputErrorLabel.leadingAnchor.constraint(equalTo: bottomBarContainer.leadingAnchor, constant: 8),
            inputErrorLabel.trailingAnchor.constraint(equalTo: bottomBarContainer.trailingAnchor, constant: -8),
            inputErrorLabel.bottomAnchor.constraint(equalTo: fieldRowStack.topAnchor, constant: -4),
            inputErrorLabel.topAnchor.constraint(equalTo: bottomBarContainer.topAnchor)
        ])

        setupPlacementConstraints()
    }

    private func setupPlacementConstraints() {
        let compactContentTop = contentAreaContainer.topAnchor.constraint(
            equalTo: safeAreaLayoutGuide.topAnchor, constant: 8
        )
        let compactContentBottom = contentAreaContainer.bottomAnchor.constraint(
            equalTo: bottomBarContainer.topAnchor, constant: -8
        )
        let compactBarBottom = bottomBarContainer.bottomAnchor.constraint(
            equalTo: keyboardLayoutGuide.topAnchor, constant: -8
        )
        let compactTableBottom = suggestionsTableView.bottomAnchor.constraint(
            equalTo: contentAreaContainer.bottomAnchor
        )
        compactConstraints = [
            compactContentTop, compactContentBottom, compactBarBottom, compactTableBottom
        ]

        let regularBarTop = bottomBarContainer.topAnchor.constraint(
            equalTo: safeAreaLayoutGuide.topAnchor,
            constant: TopBarView.barHeight + 8
        )
        let regularContentTop = contentAreaContainer.topAnchor.constraint(
            equalTo: bottomBarContainer.bottomAnchor, constant: 8
        )
        let regularContentBottom = contentAreaContainer.bottomAnchor.constraint(
            equalTo: keyboardLayoutGuide.topAnchor, constant: -8
        )
        let regularTableBottom = suggestionsTableView.bottomAnchor.constraint(
            equalTo: contentAreaContainer.bottomAnchor
        )
        regularTableBottom.priority = .defaultHigh
        suggestionsMaxHeightConstraint = suggestionsTableView.heightAnchor.constraint(
            lessThanOrEqualToConstant: Self.suggestionsMaxHeight
        )
        regularConstraints = [
            regularBarTop, regularContentTop, regularContentBottom,
            regularTableBottom, suggestionsMaxHeightConstraint
        ]

        NSLayoutConstraint.activate(compactConstraints)
    }

    private func updateVisibleContent() {
        let currentText = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasText = !currentText.isEmpty
        let shouldShowSuggestions = (isTypingMode && hasText) || (!hasText && !suggestions.isEmpty)

        if chromePlacement == .regular {
            suggestionsTableView.isHidden = !shouldShowSuggestions
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
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension AddressEditorView: UITableViewDataSource, UITableViewDelegate {
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        suggestions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SuggestionCell", for: indexPath)
        let suggestion = suggestions[indexPath.row]
        let viewModel = SuggestionRowViewModel.make(for: suggestion, engine: searchEngine)
        var content = UIListContentConfiguration.subtitleCell()
        content.image = UIImage(systemName: viewModel.systemImageName)
        content.imageProperties.tintColor = .secondaryLabel
        content.text = viewModel.primary
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.textProperties.color = .label
        content.secondaryText = viewModel.secondary
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        content.secondaryTextProperties.color = .secondaryLabel
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        content.textToSecondaryTextVerticalPadding = 2
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        cell.accessibilityTraits = .button
        cell.accessibilityHint = "Double tap to select suggestion"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelectSuggestion?(suggestions[indexPath.row])
    }
}

// MARK: - UITextFieldDelegate

extension AddressEditorView: UITextFieldDelegate {
    func textFieldDidBeginEditing(_: UITextField) {
        updateVisibleContent()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onSubmit?(textField.text ?? "")
        return true
    }
}
