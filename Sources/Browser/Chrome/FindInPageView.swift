//
//  FindInPageView.swift
//  OuterView
//

import UIKit

/// Glass find capsule shown in place of the address pill while find is active.
/// The owner docks this bar above the keyboard via `keyboardLayoutGuide`,
/// matching the address editor's docking behavior.
@MainActor
final class FindInPageView: UIView {
    nonisolated static let barHeight: CGFloat = 44

    /// Expanded-pill-equivalent frame for a stubbed bounds. The owner pins
    /// this view with the same leading, trailing, height, and bottom
    /// constants so the bar occupies the pill's exact frame.
    nonisolated static func barFrame(
        for bounds: CGRect,
        safeAreaRight: CGFloat = 0,
        systemBottomInset: CGFloat
    ) -> CGRect {
        let column = safeAreaRight > 0 ? safeAreaRight : SideRailView.safeColumnWidth
        let width = max(0, bounds.width - column - 32)
        let bottomOffset = systemBottomInset + 4
        return CGRect(
            x: 16,
            y: bounds.height - bottomOffset - barHeight,
            width: width,
            height: barHeight
        )
    }

    /// Pure counter text shared with tests.
    nonisolated static func counterText(total: Int, index: Int) -> String {
        if total <= 0 {
            return "No Results"
        }
        if total == 1 {
            return "1 match"
        }
        return "\(max(1, index))/\(total)"
    }

    var onTextChanged: (@MainActor (String) -> Void)?
    var onPrevious: (@MainActor () -> Void)?
    var onNext: (@MainActor () -> Void)?
    var onDone: (@MainActor () -> Void)?

    private(set) var currentTotal: Int = 0
    private(set) var currentIndex: Int = 0

    private let backgroundEffectView = UIVisualEffectView(effect: GlassEffect.make())
    private let contentStack = UIStackView()
    private let searchField = UITextField()
    private let countLabel = UILabel()
    private let previousButton = AccessibleButton(type: .system)
    private let nextButton = AccessibleButton(type: .system)
    private let doneButton = AccessibleButton(type: .system)

    var fieldText: String {
        searchField.text ?? ""
    }

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
        let radius = bounds.height / 2
        layer.cornerRadius = radius
        backgroundEffectView.layer.cornerRadius = radius
        backgroundEffectView.clipsToBounds = true
        if #available(iOS 26.0, *) {
            backgroundEffectView.cornerConfiguration = .capsule()
        }
    }

    @discardableResult
    func focusSearch() -> Bool {
        searchField.becomeFirstResponder()
    }

    @discardableResult
    func resignSearch() -> Bool {
        searchField.resignFirstResponder()
    }

    func setQuery(_ query: String) {
        searchField.text = query
    }

    func setMatchCount(total: Int, index: Int) {
        currentTotal = max(0, total)
        currentIndex = max(0, index)
        updateCounter()
    }

    func setMatchIndex(_ index: Int) {
        currentIndex = max(0, index)
        updateCounter()
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .clear
        clipsToBounds = true

        backgroundEffectView.translatesAutoresizingMaskIntoConstraints = false
        backgroundEffectView.isUserInteractionEnabled = false
        addSubview(backgroundEffectView)
        NSLayoutConstraint.activate([
            backgroundEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundEffectView.topAnchor.constraint(equalTo: topAnchor),
            backgroundEffectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = "Find in Page"
        searchField.accessibilityLabel = "Find in Page"
        searchField.returnKeyType = .next
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.clearButtonMode = .whileEditing
        searchField.adjustsFontForContentSizeCategory = true
        searchField.delegate = self
        searchField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onTextChanged?(self.searchField.text ?? "")
        }, for: .editingChanged)

        countLabel.font = .preferredFont(forTextStyle: .footnote)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .center
        countLabel.isAccessibilityElement = true
        countLabel.accessibilityLabel = "Match count"
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        previousButton.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        previousButton.tintColor = .label
        previousButton.accessibilityLabel = "Previous match"
        previousButton.addAction(UIAction { [weak self] _ in self?.onPrevious?() }, for: .touchUpInside)

        nextButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        nextButton.tintColor = .label
        nextButton.accessibilityLabel = "Next match"
        nextButton.addAction(UIAction { [weak self] _ in self?.onNext?() }, for: .touchUpInside)

        doneButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        doneButton.tintColor = .label
        doneButton.accessibilityLabel = "Done"
        doneButton.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(searchField)
        contentStack.addArrangedSubview(countLabel)
        contentStack.addArrangedSubview(previousButton)
        contentStack.addArrangedSubview(nextButton)
        contentStack.addArrangedSubview(doneButton)
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 36),
            previousButton.heightAnchor.constraint(equalToConstant: 36),
            nextButton.widthAnchor.constraint(equalToConstant: 36),
            nextButton.heightAnchor.constraint(equalToConstant: 36),
            doneButton.widthAnchor.constraint(equalToConstant: 36),
            doneButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        updateCounter()
    }

    private func updateCounter() {
        let text = Self.counterText(total: currentTotal, index: currentIndex)
        countLabel.text = text
        countLabel.accessibilityValue = text
    }
}

extension FindInPageView: UITextFieldDelegate {
    func textFieldShouldReturn(_: UITextField) -> Bool {
        onNext?()
        return false
    }
}
