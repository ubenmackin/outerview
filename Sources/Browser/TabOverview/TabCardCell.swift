//
//  TabCardCell.swift
//  OuterView
//

import UIKit

/// Single tab card: portrait-ratio preview above a favicon + title + host
/// strip. Previews arrive asynchronously from the owner's snapshot provider;
/// until then a host-tinted placeholder keeps the grid stable. Closing is a
/// visible 28 pt xmark or a velocity-gated flick along the dominant axis;
/// slow drags are never claimed, so grid scrolling is unaffected.
@MainActor
final class TabCardCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    static let reuseIdentifier = "TabCardCell"
    static let cornerRadius: CGFloat = 16
    static let previewAspectHeightOverWidth: CGFloat = 4.0 / 3.0

    /// Flick gate: only fast dominant-axis motions claim the touch, so the
    /// collection's pan keeps slow drags. Vertical claims still require a
    /// steep angle; horizontal claims need only dominant speed.
    nonisolated static let flickBeginVelocity: CGFloat = 1000
    nonisolated static let flickDismissDistance: CGFloat = 96
    nonisolated static let flickDismissVelocity: CGFloat = 1400

    /// Deterministic tint for the snapshot placeholder so the same host
    /// always renders the same muted hue.
    nonisolated static func placeholderColor(forHost host: String?) -> UIColor {
        guard let host, !host.isEmpty else { return .secondarySystemFill }
        let hue = CGFloat(HostFormatter.stableHue(forHost: host))
        return UIColor(hue: hue, saturation: 0.25, brightness: 0.92, alpha: 1.0)
    }

    nonisolated static func shouldBeginCardFlick(velocity: CGPoint) -> Bool {
        let ax = abs(velocity.x)
        let ay = abs(velocity.y)
        if ax > ay {
            return ax >= flickBeginVelocity
        }
        return ay >= flickBeginVelocity && ay > ax * 1.4
    }

    nonisolated static func shouldClaimFlick(velocity: CGPoint, alreadyClaimed: Bool) -> Bool {
        alreadyClaimed || shouldBeginCardFlick(velocity: velocity)
    }

    private nonisolated static func isHorizontalFlick(translation: CGPoint, velocity: CGPoint) -> Bool {
        // Translation decides when the axes differ; a tied translation
        // (including rest) falls back to velocity so zero-travel flings
        // still pick a direction.
        let tx = abs(translation.x)
        let ty = abs(translation.y)
        if tx != ty {
            return tx > ty
        }
        return abs(velocity.x) > abs(velocity.y)
    }

    nonisolated static func shouldDismissFlick(translation: CGPoint, velocity: CGPoint) -> Bool {
        if isHorizontalFlick(translation: translation, velocity: velocity) {
            return abs(translation.x) >= flickDismissDistance || abs(velocity.x) >= flickDismissVelocity
        }
        return abs(translation.y) >= flickDismissDistance || abs(velocity.y) >= flickDismissVelocity
    }

    var onClose: (() -> Void)?

    private var flickClaimed = false

    private let previewContainer = UIView()
    private let previewImageView = UIImageView()
    private let placeholderLabel = UILabel()
    private let stripStack = UIStackView()
    private let faviconView = UIImageView()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let cardFlickPan = UIPanGestureRecognizer()

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
        flickClaimed = false
        onClose = nil
        previewImageView.image = nil
        previewImageView.isHidden = true
        titleLabel.text = nil
        hostLabel.text = nil
        contentView.layer.removeAllAnimations()
        contentView.transform = .identity
        contentView.alpha = 1
        closeButton.transform = .identity
        closeButton.alpha = 1
    }

    func configure(with item: TabOverviewItem, preview: UIImage?, isSelected: Bool) {
        let host = item.host
        if let url = item.url {
            let display = HostFormatter.displayTitle(url: url, title: item.title)
            titleLabel.text = display.isEmpty ? "New Tab" : display
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

        contentView.layer.borderWidth = isSelected ? 2 : 0
        contentView.layer.borderColor = isSelected ? tintColor.cgColor : nil
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

        previewContainer.layer.cornerRadius = Self.cornerRadius
        previewContainer.clipsToBounds = true
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(previewContainer)

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
        contentView.addSubview(stripStack)

        NSLayoutConstraint.activate([
            previewContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            previewContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
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
            stripStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            stripStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            stripStack.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 6),
            stripStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])

        // Simultaneous with the collection's pan lets the flick claim an
        // already-scrolling touch; the grid's scroll recognizer is disabled
        // only after the flick latches on speed.
        cardFlickPan.delegate = self
        cardFlickPan.cancelsTouchesInView = false
        cardFlickPan.addTarget(self, action: #selector(handlePan(_:)))
        contentView.addGestureRecognizer(cardFlickPan)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Close Tab") { [weak self] _ in
                self?.onClose?()
                return true
            }
        ]
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let collectionPan = (superview as? UICollectionView)?.panGestureRecognizer
        switch pan.state {
        case .began:
            flickClaimed = false
        case .changed:
            let velocity = pan.velocity(in: self)
            guard Self.shouldClaimFlick(velocity: velocity, alreadyClaimed: flickClaimed) else { return }
            flickClaimed = true
            collectionPan?.isEnabled = false
            let maxDrag: CGFloat = 240
            let raw = pan.translation(in: self)
            let tx = min(maxDrag, max(-maxDrag, raw.x))
            let ty = min(maxDrag, max(-maxDrag, raw.y))
            contentView.transform = CGAffineTransform(translationX: tx, y: ty)
            contentView.alpha = 1 - min(0.5, max(abs(tx), abs(ty)) / maxDrag)
        case .ended, .cancelled:
            collectionPan?.isEnabled = true
            if flickClaimed {
                flickClaimed = false
                finishFlick(pan)
            } else {
                contentView.transform = .identity
                contentView.alpha = 1
            }
        default:
            collectionPan?.isEnabled = true
        }
    }

    private func finishFlick(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: self)
        let velocity = pan.velocity(in: self)
        guard Self.shouldDismissFlick(translation: translation, velocity: velocity) else {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState]
            ) {
                self.contentView.transform = .identity
                self.contentView.alpha = 1
            }
            return
        }
        // Zero-travel dismissals come from the velocity leg, so fall back to the velocity sign.
        let isHorizontal = Self.isHorizontalFlick(translation: translation, velocity: velocity)
        let exitDistance: CGFloat = 220
        let direction: CGFloat = if isHorizontal {
            translation.x != 0 ? (translation.x < 0 ? -1 : 1) : (velocity.x < 0 ? -1 : 1)
        } else {
            translation.y != 0 ? (translation.y < 0 ? -1 : 1) : (velocity.y < 0 ? -1 : 1)
        }
        let exit = exitDistance * direction
        UIView.animate(
            withDuration: 0.18,
            animations: {
                self.contentView.transform = CGAffineTransform(
                    translationX: isHorizontal ? exit : 0,
                    y: isHorizontal ? 0 : exit
                )
                self.contentView.alpha = 0
            },
            completion: { _ in self.onClose?() }
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

    override func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - UIGestureRecognizerDelegate

extension TabCardCell {
    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
