//
//  TabGroupPickerBar.swift
//  OuterView
//

import UIKit

/// Live scrub selection. Derived purely from privacy + group filter.
enum PickerSelection: Equatable, Sendable {
    case allStandard
    case `private`
    case group(UUID)
}

/// Single bottom pill owning tap, long-press, and scrub-to-select. Rests as
/// one compact pill; a horizontal drag past threshold crossfades to the item
/// strip, tracks the nearest pill, and collapses on release.
@MainActor
final class TabGroupPickerBar: UIView {
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    var onScrubSelect: ((PickerSelection) -> Void)?
    var onScrubEnd: ((PickerSelection) -> Void)?

    nonisolated static let scrubThreshold: CGFloat = 10

    private let backgroundView = UIVisualEffectView(effect: GlassEffect.make())
    private let compactLabel = UILabel()
    private let stripScroll = UIScrollView()
    private let stripStack = UIStackView()
    private let indicatorView = UIView()

    private var currentState = TabGroupsSheetState(
        isPrivate: false,
        selectedGroupID: nil,
        standardCount: 0,
        privateCount: 0,
        groups: []
    )
    private var itemSelections: [PickerSelection] = []
    private var itemButtons: [UIButton] = []
    private var activeIndex: Int?
    private var isScrubbing = false
    private var scrubCurrentIndex: Int?

    private let tapRecognizer = UITapGestureRecognizer()
    private let longPressRecognizer = UILongPressGestureRecognizer()
    private let scrubPan = UIPanGestureRecognizer()

    /// Pure derivation: private wins, then a known group id, else All.
    nonisolated static func selection(
        isPrivate: Bool,
        selectedGroupID: UUID?,
        groups: [GroupCapsuleItem]
    ) -> PickerSelection {
        if isPrivate {
            return .private
        }
        if let selectedGroupID, groups.contains(where: { $0.id == selectedGroupID }) {
            return .group(selectedGroupID)
        }
        return .allStandard
    }

    /// Compact rest title, composed from the shared segments builder so the
    /// pill text can never drift from the sheet counts.
    nonisolated static func compactSegments(for state: TabGroupsSheetState) -> (modeTitle: String, countTitle: String) {
        let mode: TabOverviewMode = state.isPrivate ? .privateMode : .standard
        let count = state.isPrivate ? state.privateCount : state.standardCount
        return (
            TabOverviewViewController.otherModeTitle(for: mode),
            TabOverviewViewController.tabsCapsuleCountTitle(count: count)
        )
    }

    nonisolated static func compactTitle(for state: TabGroupsSheetState) -> String {
        let segments = compactSegments(for: state)
        return "\(segments.modeTitle) · \(segments.countTitle)"
    }

    nonisolated static func compactAttributedTitle(for state: TabGroupsSheetState) -> NSAttributedString {
        let segments = compactSegments(for: state)
        let font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        let secondary: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel
        ]
        let attributed = NSMutableAttributedString(string: segments.modeTitle, attributes: secondary)
        attributed.append(NSAttributedString(string: " · ", attributes: secondary))
        attributed.append(NSAttributedString(
            string: segments.countTitle,
            attributes: [.font: font, .foregroundColor: UIColor.label]
        ))
        return attributed
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.layer.cornerRadius = bounds.height / 2
        backgroundView.clipsToBounds = true
        layer.cornerRadius = bounds.height / 2
        clipsToBounds = true
        guard let index = activeIndex, index < itemButtons.count else { return }
        let button = itemButtons[index]
        let target = button.convert(button.bounds, to: stripScroll)
        guard target.width > 0, indicatorView.frame != target else { return }
        indicatorView.frame = target
        indicatorView.layer.cornerRadius = target.height / 2
    }

    func render(state: TabGroupsSheetState) {
        currentState = state
        let attributed = Self.compactAttributedTitle(for: state)
        compactLabel.attributedText = attributed
        accessibilityValue = Self.compactTitle(for: state)
        rebuildStrip(for: state)
    }

    // MARK: - Private

    private func setup() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.isUserInteractionEnabled = false
        addSubview(backgroundView)

        compactLabel.textAlignment = .center
        compactLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        compactLabel.adjustsFontForContentSizeCategory = true
        compactLabel.isUserInteractionEnabled = false
        compactLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(compactLabel)

        stripScroll.showsHorizontalScrollIndicator = false
        stripScroll.isScrollEnabled = false
        stripScroll.isUserInteractionEnabled = false
        stripScroll.alpha = 0
        stripScroll.isHidden = true
        stripScroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stripScroll)

        stripStack.axis = .horizontal
        stripStack.spacing = 8
        stripStack.alignment = .center
        stripStack.isUserInteractionEnabled = false
        stripStack.translatesAutoresizingMaskIntoConstraints = false
        stripScroll.addSubview(stripStack)

        indicatorView.backgroundColor = .secondarySystemFill
        indicatorView.isUserInteractionEnabled = false
        indicatorView.isHidden = true
        stripScroll.addSubview(indicatorView)
        stripScroll.sendSubviewToBack(indicatorView)

        isAccessibilityElement = true
        accessibilityIdentifier = "TabOverview.PickerBar"
        accessibilityLabel = "Select tab group"
        accessibilityTraits = .button

        tapRecognizer.addTarget(self, action: #selector(handleTap(_:)))
        tapRecognizer.require(toFail: longPressRecognizer)
        addGestureRecognizer(tapRecognizer)

        longPressRecognizer.minimumPressDuration = 0.5
        longPressRecognizer.allowableMovement = 10
        longPressRecognizer.addTarget(self, action: #selector(handleLongPress(_:)))
        addGestureRecognizer(longPressRecognizer)

        scrubPan.addTarget(self, action: #selector(handlePan(_:)))
        scrubPan.maximumNumberOfTouches = 1
        addGestureRecognizer(scrubPan)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            compactLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            compactLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            compactLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            compactLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            compactLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),
            compactLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),

            stripScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stripScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stripScroll.centerYAnchor.constraint(equalTo: centerYAnchor),
            stripScroll.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 6),
            stripScroll.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
            stripScroll.heightAnchor.constraint(equalToConstant: 32),

            stripStack.leadingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.leadingAnchor),
            stripStack.trailingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.trailingAnchor),
            stripStack.topAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.topAnchor),
            stripStack.bottomAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.bottomAnchor),
            stripStack.heightAnchor.constraint(equalTo: stripScroll.frameLayoutGuide.heightAnchor),

            heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func rebuildStrip(for state: TabGroupsSheetState) {
        for button in itemButtons {
            stripStack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        itemButtons.removeAll(keepingCapacity: true)
        itemSelections.removeAll(keepingCapacity: true)

        let allTitle = "All · \(TabOverviewViewController.tabsCapsuleCountTitle(count: state.standardCount))"
        appendStripItem(title: allTitle, selection: .allStandard)
        let privateTitle = "Private · \(TabOverviewViewController.tabsCapsuleCountTitle(count: state.privateCount))"
        appendStripItem(title: privateTitle, selection: .private)
        for item in state.groups {
            guard let id = item.id else { continue }
            appendStripItem(title: item.title, selection: .group(id))
        }

        let current = Self.selection(
            isPrivate: state.isPrivate,
            selectedGroupID: state.selectedGroupID,
            groups: state.groups
        )
        activeIndex = itemSelections.firstIndex(of: current) ?? 0
        if scrubCurrentIndex == nil || !isScrubbing {
            updateActiveAppearance()
            setNeedsLayout()
            layoutIfNeeded()
            moveIndicator(animated: false)
            if isScrubbing {
                scrollActiveIntoView(animated: false)
            }
        } else {
            updateActiveAppearance()
            setNeedsLayout()
        }
    }

    private func appendStripItem(title: String, selection: PickerSelection) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = .secondaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 14, weight: .semibold)
            return outgoing
        }
        let button = UIButton(configuration: configuration)
        button.isUserInteractionEnabled = false
        stripStack.addArrangedSubview(button)
        itemButtons.append(button)
        itemSelections.append(selection)
    }

    private func updateActiveAppearance() {
        for (index, button) in itemButtons.enumerated() {
            let color: UIColor = index == activeIndex ? .label : .secondaryLabel
            if var configuration = button.configuration {
                configuration.baseForegroundColor = color
                button.configuration = configuration
            } else {
                button.tintColor = color
            }
        }
    }

    private func moveIndicator(animated: Bool) {
        guard let index = activeIndex, index < itemButtons.count else {
            indicatorView.isHidden = true
            return
        }
        indicatorView.isHidden = false
        let button = itemButtons[index]
        let target = button.convert(button.bounds, to: stripScroll)
        guard target.width > 0 else { return }
        indicatorView.layer.cornerRadius = target.height / 2
        if animated {
            UIView.animate(withDuration: 0.2) {
                self.indicatorView.frame = target
            }
        } else {
            indicatorView.frame = target
        }
    }

    private func scrollActiveIntoView(animated: Bool) {
        guard let index = activeIndex, index < itemButtons.count else { return }
        let button = itemButtons[index]
        let rect = button.convert(button.bounds, to: stripScroll)
        stripScroll.scrollRectToVisible(rect.insetBy(dx: -20, dy: 0), animated: animated)
    }

    private func setExpanded(_ expanded: Bool, animated: Bool = true) {
        // Both sides stay visible through the crossfade; the faded-out
        // side hides only in finish so collapse no longer animates a hidden view.
        compactLabel.isHidden = false
        stripScroll.isHidden = false
        let changes = {
            self.compactLabel.alpha = expanded ? 0 : 1
            self.stripScroll.alpha = expanded ? 1 : 0
        }
        let finish = {
            self.compactLabel.isHidden = expanded
            self.stripScroll.isHidden = !expanded
            if expanded {
                self.scrollActiveIntoView(animated: true)
            }
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: changes) { _ in finish() }
        } else {
            changes()
            finish()
        }
    }

    private func nearestIndex(to point: CGPoint) -> Int? {
        guard !itemButtons.isEmpty else { return nil }
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, button) in itemButtons.enumerated() {
            let distance = abs(button.center.x - point.x)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private func updateScrubSelection(with pan: UIPanGestureRecognizer) {
        layoutIfNeeded()
        let point = pan.location(in: stripStack)
        guard let nearest = nearestIndex(to: point), nearest != scrubCurrentIndex else { return }
        scrubCurrentIndex = nearest
        activeIndex = nearest
        updateActiveAppearance()
        moveIndicator(animated: true)
        scrollActiveIntoView(animated: true)
        onScrubSelect?(itemSelections[nearest])
    }

    private func finishScrub() {
        isScrubbing = false
        let final: PickerSelection = if let index = scrubCurrentIndex, index < itemSelections.count {
            itemSelections[index]
        } else if let index = activeIndex, index < itemSelections.count {
            itemSelections[index]
        } else {
            Self.selection(
                isPrivate: currentState.isPrivate,
                selectedGroupID: currentState.selectedGroupID,
                groups: currentState.groups
            )
        }
        scrubCurrentIndex = nil
        setExpanded(false)
        onScrubEnd?(final)
    }

    @objc private func handleTap(_ tap: UITapGestureRecognizer) {
        guard tap.state == .ended, !isScrubbing else { return }
        onTap?()
    }

    @objc private func handleLongPress(_ press: UILongPressGestureRecognizer) {
        switch press.state {
        case .began:
            scrubPan.isEnabled = false
            onLongPress?()
        case .ended, .cancelled, .failed:
            scrubPan.isEnabled = true
        default:
            break
        }
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            scrubCurrentIndex = nil
        case .changed:
            let translation = pan.translation(in: self)
            let distance = hypot(translation.x, translation.y)
            if !isScrubbing {
                guard distance > Self.scrubThreshold else { return }
                isScrubbing = true
                scrubCurrentIndex = activeIndex
                setExpanded(true)
                updateScrubSelection(with: pan)
            } else {
                updateScrubSelection(with: pan)
            }
        case .ended:
            // A pan that never passed threshold ends here without scrubbing
            // so the tap recognizer still proceeds.
            guard isScrubbing else { return }
            finishScrub()
        case .cancelled, .failed:
            guard isScrubbing else { return }
            // Cancel reverts the live-filtered grid to the committed
            // selection instead of stranding it at the last scrub tick.
            let reverted = Self.selection(
                isPrivate: currentState.isPrivate,
                selectedGroupID: currentState.selectedGroupID,
                groups: currentState.groups
            )
            isScrubbing = false
            scrubCurrentIndex = nil
            activeIndex = itemSelections.firstIndex(of: reverted) ?? activeIndex
            updateActiveAppearance()
            moveIndicator(animated: true)
            setExpanded(false)
            onScrubEnd?(reverted)
        default:
            break
        }
    }
}
