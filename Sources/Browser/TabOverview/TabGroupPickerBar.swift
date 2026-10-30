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

/// Safari-exact bottom tab group segmented picker bar.
///
/// Features matching Safari.png:
/// - Continuous floating blurred capsule container at the bottom center.
/// - Segmented options: "Private" and "X Tabs" (plus any named tab groups) side-by-side.
/// - Active sliding pill: A prominent rounded pill sits behind the currently active segment.
/// - Tap active segment (the pill): Opens the Tab Groups management sheet with options.
/// - Tap inactive segment: Smoothly slides the pill over and switches mode/group.
/// - Drag / Pan: Smoothly slides the pill horizontally between segments with haptics, snapping on release.
@MainActor
final class TabGroupPickerBar: UIView, UIGestureRecognizerDelegate {
    var onTap: (() -> Void)?
    var onScrubSelect: ((PickerSelection) -> Void)?
    var onScrubEnd: ((PickerSelection) -> Void)?

    // MARK: - Pure Derivation Helpers

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

    // MARK: - Subviews

    private let backgroundView = UIVisualEffectView(effect: GlassEffect.make())
    let slidingPillView = UIView()
    let segmentStack = UIStackView()

    // MARK: - State

    private var currentState = TabGroupsSheetState(
        isPrivate: false,
        selectedGroupID: nil,
        standardCount: 0,
        privateCount: 0,
        groups: []
    )
    private(set) var segmentSelections: [PickerSelection] = []
    private(set) var segmentButtons: [UIButton] = []
    private(set) var activeIndex = 0
    private var isPanning = false
    private var panStartIndex = 0
    private var lastScrubNotified: PickerSelection?
    private let feedbackGenerator = UISelectionFeedbackGenerator()

    // MARK: - Gestures

    private let panGesture = UIPanGestureRecognizer()

    // MARK: - Lifecycle

    override var intrinsicContentSize: CGSize {
        let stackWidth = segmentStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        let minWidth: CGFloat = 160
        return CGSize(width: max(minWidth, stackWidth + 8), height: 44)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupHierarchy()
        setupGestures()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        segmentStack.layoutIfNeeded()
        let radius = bounds.height / 2
        backgroundView.layer.cornerRadius = radius
        backgroundView.clipsToBounds = true
        layer.cornerRadius = radius
        clipsToBounds = true

        if !isPanning, activeIndex < segmentButtons.count {
            positionPill(at: activeIndex, animated: false)
        }
    }

    // MARK: - Public Render

    func render(state: TabGroupsSheetState) {
        currentState = state
        rebuildSegments(for: state)
        accessibilityLabel = "Tab groups picker"
        accessibilityValue = Self.compactTitle(for: state)
        accessibilityHint = "Tap selected pill for options, tap another segment or drag to switch"
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    // MARK: - Setup

    private func setupHierarchy() {
        backgroundColor = .clear

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.isUserInteractionEnabled = false
        addSubview(backgroundView)

        // The sliding pill highlight behind the active segment (Safari.png style)
        slidingPillView.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.38, alpha: 0.65)
                : UIColor(white: 1.0, alpha: 0.85)
        }
        slidingPillView.isUserInteractionEnabled = false
        slidingPillView.clipsToBounds = true
        addSubview(slidingPillView)

        segmentStack.axis = .horizontal
        segmentStack.alignment = .fill
        segmentStack.distribution = .fillProportionally
        segmentStack.spacing = 2
        segmentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(segmentStack)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            heightAnchor.constraint(equalToConstant: 44),

            segmentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            segmentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            segmentStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            segmentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])

        isAccessibilityElement = false
        accessibilityIdentifier = "TabOverview.PickerBar"
        segmentStack.accessibilityIdentifier = "TabOverview.PickerBar"
    }

    private func setupGestures() {
        panGesture.delegate = self
        panGesture.addTarget(self, action: #selector(handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(panGesture)
    }

    // MARK: - Segments Construction

    private func rebuildSegments(for state: TabGroupsSheetState) {
        var newSelections: [PickerSelection] = []
        var newTitles: [String] = []

        // 1. Private Segment
        newSelections.append(.private)
        newTitles.append("Private")

        // 2. All Standard Tabs Segment (Count title e.g. "2 Tabs" or "1 Tab")
        let standardCountTitle = TabOverviewViewController.tabsCapsuleCountTitle(count: state.standardCount)
        newSelections.append(.allStandard)
        newTitles.append(standardCountTitle)

        // 3. Any Custom Tab Groups
        for group in state.groups {
            guard let id = group.id else { continue }
            newSelections.append(.group(id))
            newTitles.append(group.title)
        }

        let current = Self.selection(
            isPrivate: state.isPrivate,
            selectedGroupID: state.selectedGroupID,
            groups: state.groups
        )
        let newActiveIndex = newSelections.firstIndex(of: current) ?? 1

        if segmentSelections == newSelections, segmentButtons.count == newTitles.count {
            for (index, button) in segmentButtons.enumerated() {
                let title = newTitles[index]
                if button.configuration?.title != title {
                    var config = button.configuration ?? UIButton.Configuration.plain()
                    config.title = title
                    button.configuration = config
                }
            }
            activeIndex = newActiveIndex
            updateButtonColors()
            if !isPanning {
                segmentStack.layoutIfNeeded()
                positionPill(at: activeIndex, animated: false)
            }
            return
        }

        for button in segmentButtons {
            segmentStack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        segmentButtons.removeAll(keepingCapacity: true)
        segmentSelections.removeAll(keepingCapacity: true)

        for (selection, title) in zip(newSelections, newTitles) {
            appendSegment(title: title, selection: selection)
        }

        activeIndex = newActiveIndex
        updateButtonColors()
        segmentStack.layoutIfNeeded()
        if !isPanning {
            positionPill(at: activeIndex, animated: false)
        }
    }

    private func appendSegment(title: String, selection: PickerSelection) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }

        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self, let button, let index = self.segmentButtons.firstIndex(of: button) else { return }
            self.handleSegmentTap(at: index)
        }, for: .touchUpInside)

        segmentStack.addArrangedSubview(button)
        segmentButtons.append(button)
        segmentSelections.append(selection)
    }

    private func updateButtonColors() {
        let groupValue = Self.compactTitle(for: currentState)
        for (index, button) in segmentButtons.enumerated() {
            let isActive = index == activeIndex
            let color: UIColor = isActive ? .label : .secondaryLabel
            if var config = button.configuration {
                config.baseForegroundColor = color
                button.configuration = config
            }
            button.accessibilityLabel = button.configuration?.title
            if isActive {
                button.accessibilityTraits = [.button, .selected]
                button.accessibilityValue = groupValue
                button.accessibilityHint = "Double tap for tab group options"
            } else {
                button.accessibilityTraits = .button
                button.accessibilityValue = nil
                if let title = button.configuration?.title {
                    button.accessibilityHint = "Double tap to switch to \(title)"
                } else {
                    button.accessibilityHint = "Double tap to switch tabs"
                }
            }
        }
    }

    private func positionPill(at index: Int, animated: Bool) {
        guard index < segmentButtons.count else { return }
        segmentStack.layoutIfNeeded()
        let button = segmentButtons[index]
        button.layoutIfNeeded()
        let buttonFrame = button.convert(button.bounds, to: self)
        guard buttonFrame.width > 0 else { return }

        slidingPillView.layer.cornerRadius = buttonFrame.height / 2
        if animated {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState]
            ) {
                self.slidingPillView.frame = buttonFrame
            }
        } else {
            slidingPillView.frame = buttonFrame
        }
    }

    // MARK: - Interactions

    private func handleSegmentTap(at index: Int) {
        if index == activeIndex {
            // Tapping the active pill opens the Tab Groups management sheet immediately
            onTap?()
        } else {
            // Tapping an inactive segment slides the pill over and selects it
            selectSegment(at: index, animated: true, notify: true)
        }
    }

    private func selectSegment(at index: Int, animated: Bool, notify: Bool) {
        guard index < segmentSelections.count else { return }
        activeIndex = index
        updateButtonColors()
        positionPill(at: index, animated: animated)
        if notify {
            onScrubEnd?(segmentSelections[index])
        }
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            guard segmentSelections.count > 1 else { return }
            isPanning = true
            panStartIndex = activeIndex
            lastScrubNotified = nil
            feedbackGenerator.prepare()
            updatePillForPan(at: pan.location(in: segmentStack))

        case .changed:
            guard isPanning else { return }
            updatePillForPan(at: pan.location(in: segmentStack))

        case .ended:
            guard isPanning else { return }
            isPanning = false
            let finalIndex = nearestIndex(to: pan.location(in: segmentStack))
            // The final tick already applied this selection; commit visually without re-notifying.
            if finalIndex < segmentSelections.count,
               segmentSelections[finalIndex] == lastScrubNotified
            {
                selectSegment(at: finalIndex, animated: true, notify: false)
            } else {
                selectSegment(at: finalIndex, animated: true, notify: true)
            }
            lastScrubNotified = nil

        case .cancelled, .failed:
            guard isPanning else { return }
            isPanning = false
            lastScrubNotified = nil
            selectSegment(at: panStartIndex, animated: true, notify: true)

        default:
            break
        }
    }

    private func updatePillForPan(at point: CGPoint) {
        let nearest = nearestIndex(to: point)
        if nearest != activeIndex {
            activeIndex = nearest
            feedbackGenerator.selectionChanged()
            updateButtonColors()
            if nearest < segmentSelections.count {
                let selection = segmentSelections[nearest]
                lastScrubNotified = selection
                onScrubSelect?(selection)
            }
        }

        // Live spring track to the hovered segment
        guard nearest < segmentButtons.count else { return }
        let button = segmentButtons[nearest]
        let buttonFrame = button.convert(button.bounds, to: self)
        slidingPillView.layer.cornerRadius = buttonFrame.height / 2
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState]
        ) {
            self.slidingPillView.frame = buttonFrame
        }
    }

    private func nearestIndex(to point: CGPoint) -> Int {
        guard !segmentButtons.isEmpty else { return 0 }
        var best = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (index, button) in segmentButtons.enumerated() {
            let dist = abs(button.center.x - point.x)
            if dist < bestDist {
                bestDist = dist
                best = index
            }
        }
        return best
    }

    // MARK: - UIGestureRecognizerDelegate

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGesture {
            return segmentSelections.count > 1
        }
        return true
    }
}
