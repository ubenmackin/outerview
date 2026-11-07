// TabOverview — Regular-width live tab strip.

import UIKit

@MainActor
final class TabStripView: UIView {
    nonisolated static let stripHeight: CGFloat = 44
    nonisolated static let horizontalInset: CGFloat = 28
    nonisolated static let trackHeight: CGFloat = 32
    nonisolated static let cellHeight: CGFloat = 32
    nonisolated static let minCellWidth: CGFloat = 140
    nonisolated static let cellWidth: CGFloat = minCellWidth

    var onSelectTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    var onNewTab: (() -> Void)?
    var onReorderTabs: (([UUID]) -> Void)?

    private(set) var displayedTabs: [TabOverviewItem] = []
    private(set) var displayedSelectedID: UUID?

    let trackView = UIView()
    let collectionView: UICollectionView
    let newTabButton = UIButton(type: .system)
    private let flowLayout = UICollectionViewFlowLayout()
    private let blurView = UIVisualEffectView(effect: RegularHeaderBackground.makeBlurEffect())
    private var lastCollectionBoundsSize: CGSize = .zero

    var isBlurVisible: Bool {
        !blurView.isHidden
    }

    nonisolated static func tabWidth(at index: Int, count: Int, availableWidth: CGFloat) -> CGFloat {
        guard count > 0, availableWidth > 0 else { return minCellWidth }
        let totalWidth = floor(availableWidth)
        let rawEqual = totalWidth / CGFloat(count)
        guard rawEqual >= minCellWidth else {
            return minCellWidth
        }
        let clampedIndex = max(0, min(index, count - 1))
        let start = floor(CGFloat(clampedIndex) * totalWidth / CGFloat(count))
        let end = floor(CGFloat(clampedIndex + 1) * totalWidth / CGFloat(count))
        return max(1, end - start)
    }

    func applyHeaderBackground() {
        RegularHeaderBackground.apply(to: self, blurView: blurView)
    }

    override init(frame: CGRect) {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.stripHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTrackBorder()
        if collectionView.bounds.size != lastCollectionBoundsSize {
            lastCollectionBoundsSize = collectionView.bounds.size
            updateScrollBounce()
            flowLayout.invalidateLayout()
        }
    }

    func render(tabs: [TabOverviewItem], selectedID: UUID?) {
        displayedTabs = tabs
        displayedSelectedID = selectedID
        updateScrollBounce()
        collectionView.reloadData()
        flowLayout.invalidateLayout()
    }

    private func updateScrollBounce() {
        let contentMinimum = CGFloat(displayedTabs.count) * Self.minCellWidth
        collectionView.alwaysBounceHorizontal = collectionView.bounds.width > 0
            && contentMinimum > floor(collectionView.bounds.width)
    }

    private func updateTrackBorder() {
        let scale = max(1, traitCollection.displayScale)
        trackView.layer.borderWidth = 1.0 / scale
        trackView.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).resolvedColor(with: traitCollection).cgColor
    }

    private func setup() {
        RegularHeaderBackground.pinBlur(blurView, in: self)
        applyHeaderBackground()

        trackView.translatesAutoresizingMaskIntoConstraints = false
        trackView.backgroundColor = .tertiarySystemFill
        trackView.layer.cornerRadius = Self.trackHeight / 2
        trackView.layer.cornerCurve = .continuous
        trackView.clipsToBounds = true
        addSubview(trackView)
        updateTrackBorder()

        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.minimumLineSpacing = 0
        flowLayout.sectionInset = .zero
        flowLayout.estimatedItemSize = .zero
        flowLayout.itemSize = CGSize(width: Self.minCellWidth, height: Self.cellHeight)

        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(TabStripCell.self, forCellWithReuseIdentifier: TabStripCell.reuseIdentifier)
        trackView.addSubview(collectionView)
        setupReorderGesture()

        // Retained hidden for programmatic callers; TopBarView owns the visible `+` action on regular.
        newTabButton.setImage(UIImage(systemName: "plus"), for: .normal)
        newTabButton.tintColor = .label
        newTabButton.accessibilityLabel = "New Tab"
        newTabButton.isHidden = true
        newTabButton.addAction(UIAction { [weak self] _ in self?.onNewTab?() }, for: .touchUpInside)

        let trackLeading = trackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset)
        let trackTrailing = trackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset)
        trackTrailing.priority = UILayoutPriority(999)
        let trackHeight = trackView.heightAnchor.constraint(equalToConstant: Self.trackHeight)
        trackHeight.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            trackLeading,
            trackTrailing,
            trackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            trackHeight,
            collectionView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trackView.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: trackView.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: trackView.bottomAnchor)
        ])

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.updateTrackBorder()
        }
    }

    private func setupReorderGesture() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.25
        collectionView.addGestureRecognizer(longPress)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: collectionView)
        switch gesture.state {
        case .began:
            guard let indexPath = collectionView.indexPathForItem(at: point),
                  displayedTabs.count > 1,
                  collectionView.beginInteractiveMovementForItem(at: indexPath) else { return }
        case .changed:
            let clampedPoint = CGPoint(x: point.x, y: collectionView.bounds.midY)
            collectionView.updateInteractiveMovementTargetPosition(clampedPoint)
        case .ended:
            collectionView.endInteractiveMovement()
        case .cancelled, .failed:
            collectionView.cancelInteractiveMovement()
        default:
            break
        }
    }
}

extension TabStripView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        displayedTabs.count
    }

    func collectionView(_: UICollectionView, canMoveItemAt _: IndexPath) -> Bool {
        displayedTabs.count > 1
    }

    func collectionView(
        _: UICollectionView,
        moveItemAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard sourceIndexPath.item < displayedTabs.count,
              destinationIndexPath.item < displayedTabs.count,
              sourceIndexPath.item != destinationIndexPath.item else { return }
        let moved = displayedTabs.remove(at: sourceIndexPath.item)
        displayedTabs.insert(moved, at: destinationIndexPath.item)
        onReorderTabs?(displayedTabs.map(\.id))
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout _: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = Self.tabWidth(
            at: indexPath.item,
            count: displayedTabs.count,
            availableWidth: collectionView.bounds.width
        )
        let resolvedHeight = collectionView.bounds.height > 0
            ? min(Self.cellHeight, collectionView.bounds.height)
            : Self.cellHeight
        return CGSize(width: width, height: max(1, resolvedHeight))
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: TabStripCell.reuseIdentifier,
            for: indexPath
        ) as? TabStripCell
        else {
            return UICollectionViewCell()
        }
        let item = displayedTabs[indexPath.item]
        cell.configure(with: item, isSelected: item.id == displayedSelectedID)
        cell.onClose = { [weak self] in
            self?.onCloseTab?(item.id)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard indexPath.item < displayedTabs.count else { return }
        onSelectTab?(displayedTabs[indexPath.item].id)
    }
}

/// Equal-width Safari capsule tab cell with centered `[favicon + title]` and a leading
/// `xmark.circle.fill` close button on the active tab.
@MainActor
final class TabStripCell: UICollectionViewCell {
    static let reuseIdentifier = "TabStripCell"
    nonisolated static let activeLeadingClearance: CGFloat = 34
    nonisolated static let inactiveHorizontalPadding: CGFloat = 14

    var onClose: (() -> Void)?

    private let closeButton = AccessibleButton(type: .system)
    private let titleGroupStack = UIStackView()
    private let faviconView = UIImageView()
    private let titleLabel = UILabel()
    private var titleGroupMinLeadingConstraint: NSLayoutConstraint!
    private var currentID: UUID?
    private var isTabSelected = false
    private var faviconTask: Task<Void, Never>?

    var isCloseButtonVisible: Bool {
        !closeButton.isHidden
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        faviconTask?.cancel()
        faviconTask = nil
        onClose = nil
        currentID = nil
        isTabSelected = false
        faviconView.image = nil
        titleLabel.text = nil
        closeButton.isHidden = true
    }

    func configure(with item: TabOverviewItem, isSelected: Bool) {
        faviconTask?.cancel()
        faviconTask = nil
        currentID = item.id
        isTabSelected = isSelected

        if let url = item.url {
            titleLabel.text = HostFormatter.displayTitle(url: url, title: item.title)
            faviconTask = FaviconService.shared.bind(
                url: url,
                into: faviconView,
                identity: item.id,
                currentIdentity: { [weak self] in self?.currentID },
                size: 16,
                isPrivate: item.isPrivate
            )
        } else {
            titleLabel.text = "New Tab"
            let globeConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            faviconView.image = UIImage(systemName: "globe", withConfiguration: globeConfig)
        }

        let baseFont = UIFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium)
        titleLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: baseFont)
        titleLabel.textColor = isSelected ? .label : UIColor.label.withAlphaComponent(0.85)

        closeButton.isHidden = !isSelected
        titleGroupMinLeadingConstraint.constant = isSelected
            ? Self.activeLeadingClearance
            : Self.inactiveHorizontalPadding

        applySelectionAppearance()

        isAccessibilityElement = true
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        accessibilityLabel = titleLabel.text
    }

    private func applySelectionAppearance() {
        if isTabSelected {
            contentView.backgroundColor = .secondarySystemFill
            let scale = max(1, traitCollection.displayScale)
            contentView.layer.borderWidth = 1.0 / scale
            contentView.layer.borderColor = UIColor.separator
                .withAlphaComponent(0.55)
                .resolvedColor(with: traitCollection)
                .cgColor
        } else {
            contentView.backgroundColor = .clear
            contentView.layer.borderWidth = 0
            contentView.layer.borderColor = nil
        }
    }

    private func setup() {
        contentView.layer.cornerRadius = TabStripView.trackHeight / 2
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        closeButton.setImage(
            UIImage(
                systemName: "xmark.circle.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            ),
            for: .normal
        )
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = "Close Tab"
        closeButton.isHidden = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        contentView.addSubview(closeButton)

        faviconView.contentMode = .scaleAspectFit
        faviconView.tintColor = .secondaryLabel
        faviconView.layer.cornerRadius = 4
        faviconView.clipsToBounds = true
        faviconView.translatesAutoresizingMaskIntoConstraints = false
        faviconView.setContentHuggingPriority(.required, for: .horizontal)
        faviconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        titleGroupStack.axis = .horizontal
        titleGroupStack.alignment = .center
        titleGroupStack.spacing = 6
        titleGroupStack.translatesAutoresizingMaskIntoConstraints = false
        titleGroupStack.addArrangedSubview(faviconView)
        titleGroupStack.addArrangedSubview(titleLabel)
        contentView.addSubview(titleGroupStack)

        let closeLeading = closeButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5)
        closeLeading.priority = UILayoutPriority(999)
        let centerGroup = titleGroupStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
        centerGroup.priority = .defaultHigh
        titleGroupMinLeadingConstraint = titleGroupStack.leadingAnchor.constraint(
            greaterThanOrEqualTo: contentView.leadingAnchor,
            constant: Self.inactiveHorizontalPadding
        )
        titleGroupMinLeadingConstraint.priority = UILayoutPriority(999)
        let maxTrailing = titleGroupStack.trailingAnchor.constraint(
            lessThanOrEqualTo: contentView.trailingAnchor,
            constant: -Self.inactiveHorizontalPadding
        )
        maxTrailing.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            closeLeading,
            closeButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
            faviconView.widthAnchor.constraint(equalToConstant: 16),
            faviconView.heightAnchor.constraint(equalToConstant: 16),
            centerGroup,
            titleGroupMinLeadingConstraint,
            maxTrailing,
            titleGroupStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.applySelectionAppearance()
        }
    }
}
