// TabOverview — Single tab card plus swipe-dismiss gesture.

import UIKit

/// Pan gesture recognizer that differentiates immediate horizontal swipe-to-dismiss
/// from a stationary hold intended for long-press menus or drag-reordering.
@MainActor
final class CardSwipePanGestureRecognizer: UIPanGestureRecognizer {
    private var touchStartTime: TimeInterval = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        touchStartTime = CACurrentMediaTime()
        super.touchesBegan(touches, with: event)
    }

    override func reset() {
        super.reset()
        touchStartTime = 0
    }

    var isImmediateSwipe: Bool {
        guard touchStartTime > 0 else { return true }
        return (CACurrentMediaTime() - touchStartTime) < 0.30
    }
}

/// Single tab card: portrait-ratio preview above a favicon + title + host
/// strip. Previews arrive asynchronously from the owner's snapshot provider;
/// until then a host-tinted placeholder keeps the grid stable. Closing is a
/// visible 28 pt xmark or a horizontal swipe to remove (slow drag past threshold
/// or fast flick towards edge).
@MainActor
final class TabCardCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    static let reuseIdentifier = "TabCardCell"
    static let cornerRadius: CGFloat = 16
    static let previewAspectHeightOverWidth: CGFloat = 4.0 / 3.0
    static let landscapeAspectHeightOverWidth: CGFloat = 3.0 / 4.0

    nonisolated static let swipeDismissDistance: CGFloat = 120
    nonisolated static let swipeDismissVelocity: CGFloat = 800

    /// Determines if a horizontal swipe should dismiss the card.
    /// Requires far drag (>= 120 pt or 60% of card width) or fast flick with at least 50 pt travel.
    nonisolated static func shouldDismissSwipe(
        translationX: CGFloat,
        velocityX: CGFloat,
        cardWidth: CGFloat
    ) -> Bool {
        let distanceThreshold = max(swipeDismissDistance, cardWidth * 0.60)
        if abs(translationX) >= distanceThreshold {
            return true
        }
        if abs(velocityX) >= swipeDismissVelocity, abs(translationX) >= 50 {
            return (translationX > 0 && velocityX > 0) || (translationX < 0 && velocityX < 0)
        }
        return false
    }

    /// Pure helper to check if a gesture qualifies as an immediate horizontal swipe.
    /// Stationary holds (isImmediate == false) and vertical dominant gestures are rejected,
    /// guaranteeing long-press reorder and vertical scrolling never conflict.
    nonisolated static func shouldBeginSwipe(isImmediate: Bool, velocity: CGPoint) -> Bool {
        isImmediate && abs(velocity.x) > abs(velocity.y) * 1.2
    }

    /// Deterministic tint for the snapshot placeholder so the same host
    /// always renders the same muted hue.
    nonisolated static func placeholderColor(forHost host: String?) -> UIColor {
        guard let host, !host.isEmpty else { return .secondarySystemFill }
        let hue = CGFloat(HostFormatter.stableHue(forHost: host))
        return UIColor(hue: hue, saturation: 0.25, brightness: 0.92, alpha: 1.0)
    }

    var onClose: (() -> Void)?

    /// Internal container holding all card content. Transforming this view ensures
    /// UICollectionViewCell layout passes do not reset or conflict with swipe animations.
    private let cardContainer = UIView()
    private let previewContainer = UIView()
    private let previewImageView = UIImageView()
    private let placeholderLabel = UILabel()
    private let stripStack = UIStackView()
    private let faviconView = UIImageView()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let swipePanRecognizer = CardSwipePanGestureRecognizer()
    private var faviconTask: Task<Void, Never>?
    private var currentID: UUID?

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
        onClose = nil
        faviconTask?.cancel()
        faviconTask = nil
        currentID = nil
        faviconView.image = UIImage(systemName: "globe")
        previewImageView.image = nil
        previewImageView.isHidden = true
        titleLabel.text = nil
        hostLabel.text = nil
        cardContainer.layer.removeAllAnimations()
        cardContainer.transform = .identity
        cardContainer.alpha = 1
        contentView.layer.borderWidth = 0
        contentView.layer.borderColor = nil
        closeButton.transform = .identity
        closeButton.alpha = 1
    }

    func configure(with item: TabOverviewItem, preview: UIImage?, isSelected: Bool) {
        faviconTask?.cancel()
        faviconTask = nil
        currentID = item.id

        if let url = item.url {
            faviconTask = FaviconService.shared.bind(
                url: url,
                into: faviconView,
                identity: item.id,
                currentIdentity: { [weak self] in self?.currentID },
                size: 16,
                isPrivate: item.isPrivate
            )
        } else {
            faviconView.image = UIImage(systemName: "globe")
        }

        let host = item.host
        if let url = item.url {
            let display = HostFormatter.displayTitle(url: url, title: item.title)
            titleLabel.text = display.isEmpty ? "New Tab" : display
        } else if let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty
        {
            // URL-less tabs surface their title so seeded fixtures stay visible.
            titleLabel.text = title
        } else {
            titleLabel.text = "New Tab"
        }
        hostLabel.text = host ?? ""
        hostLabel.isHidden = host?.isEmpty ?? true

        if let preview {
            previewImageView.image = preview
            previewImageView.isHidden = false
            placeholderLabel.isHidden = true
            previewContainer.backgroundColor = .secondarySystemBackground
        } else {
            previewImageView.image = nil
            previewImageView.isHidden = true
            placeholderLabel.isHidden = false
            previewContainer.backgroundColor = Self.placeholderColor(forHost: host)
            let initial = (host ?? titleLabel.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(1)
                .uppercased()
            placeholderLabel.text = initial.isEmpty ? "◌" : String(initial)
        }

        // No blue outline on selection
        contentView.layer.borderWidth = 0
        contentView.layer.borderColor = nil

        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        let displayTitle = titleLabel.text ?? "New Tab"
        if let host, !host.isEmpty, !displayTitle.contains(host) {
            accessibilityLabel = "\(displayTitle), \(host)"
        } else {
            accessibilityLabel = displayTitle
        }
        accessibilityHint = "Double tap to switch to tab"
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        clipsToBounds = false
        contentView.clipsToBounds = false

        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.clipsToBounds = false
        contentView.addSubview(cardContainer)

        previewContainer.layer.cornerRadius = Self.cornerRadius
        previewContainer.clipsToBounds = true
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(previewContainer)

        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        previewImageView.isHidden = true
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(previewImageView)

        placeholderLabel.font = .preferredFont(forTextStyle: .largeTitle)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .secondaryLabel
        placeholderLabel.textAlignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(placeholderLabel)

        // Sits above the preview so it stays tappable over any snapshot.
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(
            UIImage(
                systemName: "xmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            ),
            for: .normal
        )
        closeButton.tintColor = .white
        closeButton.layer.backgroundColor = UIColor(white: 0.5, alpha: 0.9).cgColor
        closeButton.layer.cornerRadius = 14
        closeButton.clipsToBounds = true
        closeButton.isAccessibilityElement = true
        closeButton.accessibilityLabel = "Close Tab"
        closeButton.addAction(
            UIAction { [weak self] _ in self?.handleCloseTap() },
            for: .touchUpInside
        )
        previewContainer.addSubview(closeButton)

        faviconView.image = UIImage(systemName: "globe")
        faviconView.contentMode = .scaleAspectFit
        faviconView.tintColor = .secondaryLabel
        faviconView.translatesAutoresizingMaskIntoConstraints = false
        faviconView.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            faviconView.widthAnchor.constraint(equalToConstant: 16),
            faviconView.heightAnchor.constraint(equalToConstant: 16)
        ])

        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        hostLabel.font = .preferredFont(forTextStyle: .caption2)
        hostLabel.adjustsFontForContentSizeCategory = true
        hostLabel.textColor = .secondaryLabel
        hostLabel.numberOfLines = 1
        hostLabel.lineBreakMode = .byTruncatingMiddle

        let textStack = UIStackView(arrangedSubviews: [titleLabel, hostLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        stripStack.axis = .horizontal
        stripStack.alignment = .center
        stripStack.spacing = 6
        stripStack.translatesAutoresizingMaskIntoConstraints = false
        stripStack.addArrangedSubview(faviconView)
        stripStack.addArrangedSubview(textStack)
        cardContainer.addSubview(stripStack)

        NSLayoutConstraint.activate([
            cardContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            previewContainer.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
            previewContainer.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            placeholderLabel.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            closeButton.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 6),
            closeButton.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 6),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),
            stripStack.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 4),
            stripStack.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -4),
            stripStack.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 6),
            stripStack.bottomAnchor.constraint(lessThanOrEqualTo: cardContainer.bottomAnchor)
        ])

        swipePanRecognizer.delegate = self
        swipePanRecognizer.cancelsTouchesInView = true
        swipePanRecognizer.maximumNumberOfTouches = 1
        swipePanRecognizer.addTarget(self, action: #selector(handleSwipePan(_:)))
        contentView.addGestureRecognizer(swipePanRecognizer)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Close Tab") { [weak self] _ in
                self?.onClose?()
                return true
            }
        ]
    }

    @objc private func handleSwipePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            break
        case .changed:
            let tx = pan.translation(in: self).x
            cardContainer.transform = CGAffineTransform(translationX: tx, y: 0)
            let cardWidth = bounds.width > 0 ? bounds.width : 160
            let progress = min(1.0, abs(tx) / cardWidth)
            // Subtle dimming during swipe; card stays clearly visible
            cardContainer.alpha = max(0.85, 1.0 - (progress * 0.15))
        case .ended:
            finishSwipe(pan)
        case .cancelled, .failed:
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState]
            ) {
                self.cardContainer.transform = .identity
                self.cardContainer.alpha = 1
            }
        default:
            break
        }
    }

    private func finishSwipe(_ pan: UIPanGestureRecognizer) {
        let tx = pan.translation(in: self).x
        let vx = pan.velocity(in: self).x
        let cardWidth = bounds.width > 0 ? bounds.width : 160

        guard Self.shouldDismissSwipe(translationX: tx, velocityX: vx, cardWidth: cardWidth) else {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState]
            ) {
                self.cardContainer.transform = .identity
                self.cardContainer.alpha = 1
            }
            return
        }

        let direction: CGFloat = (tx != 0 ? tx : vx) > 0 ? 1 : -1
        let exitDistance = cardWidth + 120
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseOut],
            animations: {
                self.cardContainer.transform = CGAffineTransform(translationX: exitDistance * direction, y: 0)
                self.cardContainer.alpha = 0
            },
            completion: { _ in
                self.onClose?()
            }
        )
    }

    private func handleCloseTap() {
        UIView.animate(
            withDuration: 0.15,
            animations: {
                self.closeButton.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
                self.closeButton.alpha = 0
            },
            completion: { _ in self.onClose?() }
        )
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let swipePan = gestureRecognizer as? CardSwipePanGestureRecognizer {
            let velocity = swipePan.velocity(in: self)
            return Self.shouldBeginSwipe(isImmediate: swipePan.isImmediateSwipe, velocity: velocity)
        }
        return true
    }
}

// MARK: - UIGestureRecognizerDelegate

extension TabCardCell {
    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        // Horizontal swipe locks exclusivity once begun
        false
    }
}
