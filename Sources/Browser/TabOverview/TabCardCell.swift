//
//  TabCardCell.swift
//  OuterView
//

import UIKit

/// Single tab card: portrait-ratio preview above a favicon + title + host
/// strip. Previews arrive asynchronously from the owner's snapshot provider;
/// until then a host-tinted placeholder keeps the grid stable.
@MainActor
final class TabCardCell: UICollectionViewCell {
    static let reuseIdentifier = "TabCardCell"
    static let cornerRadius: CGFloat = 16
    static let previewAspectHeightOverWidth: CGFloat = 4.0 / 3.0

    /// Deterministic tint for the snapshot placeholder so the same host
    /// always renders the same muted hue.
    nonisolated static func placeholderColor(forHost host: String?) -> UIColor {
        guard let host, !host.isEmpty else { return .secondarySystemFill }
        let hue = CGFloat(HostFormatter.stableHue(forHost: host))
        return UIColor(hue: hue, saturation: 0.25, brightness: 0.92, alpha: 1.0)
    }

    var onClose: (() -> Void)?

    private let previewContainer = UIView()
    private let previewImageView = UIImageView()
    private let placeholderLabel = UILabel()
    private let stripStack = UIStackView()
    private let faviconView = UIImageView()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()

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
        previewImageView.image = nil
        previewImageView.isHidden = true
        titleLabel.text = nil
        hostLabel.text = nil
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
            stripStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            stripStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            stripStack.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 6),
            stripStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])

        // Either vertical swipe dismisses the card; the collection's pan
        // recognizer still wins for diagonal drags, so scrolling is unaffected.
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
        swipeUp.direction = .up
        contentView.addGestureRecognizer(swipeUp)
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
        swipeDown.direction = .down
        contentView.addGestureRecognizer(swipeDown)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Close Tab") { [weak self] _ in
                self?.onClose?()
                return true
            }
        ]
    }

    @objc private func handleSwipe() {
        onClose?()
    }
}
