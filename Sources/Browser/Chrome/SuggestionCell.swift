// Chrome — Suggestion row with favicon plus search affordance.
import UIKit

/// Suggestion list row showing a host favicon for site rows
/// and a magnifier for search rows.
@MainActor
final class SuggestionCell: UITableViewCell {
    static let reuseIdentifier = "SuggestionCell"
    nonisolated static let faviconLength: CGFloat = 28
    nonisolated static let cornerRadius: CGFloat = 6

    private let faviconView = UIImageView()
    private let textStack = UIStackView()
    private let primaryLabel = UILabel()
    private let secondaryLabel = UILabel()
    private var faviconTask: Task<Void, Never>?
    private var boundIdentity: UUID?
    private var boundURL: URL?
    private(set) var lastConfiguredIsPrivateForTesting: Bool?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
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
        boundIdentity = nil
        boundURL = nil
        lastConfiguredIsPrivateForTesting = nil
        faviconView.image = nil
        primaryLabel.text = nil
        secondaryLabel.text = nil
        accessibilityLabel = nil
    }

    func configure(for suggestion: Suggestion, engine: SearchEngine, isPrivate: Bool) {
        faviconTask?.cancel()
        faviconTask = nil
        boundIdentity = nil
        boundURL = nil
        lastConfiguredIsPrivateForTesting = isPrivate

        let viewModel = SuggestionRowViewModel.make(for: suggestion, engine: engine)
        primaryLabel.text = viewModel.primary
        if case .googleSuggest = suggestion.kind {
            secondaryLabel.text = nil
            secondaryLabel.isHidden = true
        } else if viewModel.secondary.isEmpty {
            secondaryLabel.text = nil
            secondaryLabel.isHidden = true
        } else {
            secondaryLabel.text = viewModel.secondary
            secondaryLabel.isHidden = false
        }
        if viewModel.secondary.isEmpty {
            accessibilityLabel = viewModel.primary
        } else {
            accessibilityLabel = "\(viewModel.primary), \(viewModel.secondary)"
        }

        switch suggestion.kind {
        case let .site(_, url, _), let .openTab(_, url, _):
            boundURL = url
            let identity = UUID()
            boundIdentity = identity
            faviconView.tintColor = nil
            faviconTask = FaviconService.shared.bind(
                url: url,
                into: faviconView,
                identity: identity,
                currentIdentity: { [weak self] in self?.boundIdentity },
                size: Self.faviconLength,
                isPrivate: isPrivate
            )
        case .googleSuggest, .search, .onPageFind:
            faviconView.image = UIImage(systemName: viewModel.systemImageName)
            faviconView.tintColor = .secondaryLabel
        }
    }

    var hasFaviconTaskForTesting: Bool {
        faviconTask != nil
    }

    var faviconImageForTesting: UIImage? {
        faviconView.image
    }

    var faviconTintForTesting: UIColor? {
        faviconView.tintColor
    }

    var boundURLForTesting: URL? {
        boundURL
    }

    private func setup() {
        backgroundColor = .clear

        faviconView.translatesAutoresizingMaskIntoConstraints = false
        faviconView.contentMode = .scaleAspectFit
        faviconView.layer.cornerRadius = Self.cornerRadius
        faviconView.clipsToBounds = true
        contentView.addSubview(faviconView)

        primaryLabel.translatesAutoresizingMaskIntoConstraints = false
        primaryLabel.font = .preferredFont(forTextStyle: .body)
        primaryLabel.adjustsFontForContentSizeCategory = true
        primaryLabel.textColor = .label
        primaryLabel.numberOfLines = 1
        primaryLabel.lineBreakMode = .byTruncatingTail

        secondaryLabel.translatesAutoresizingMaskIntoConstraints = false
        secondaryLabel.font = .preferredFont(forTextStyle: .footnote)
        secondaryLabel.adjustsFontForContentSizeCategory = true
        secondaryLabel.textColor = .secondaryLabel
        secondaryLabel.numberOfLines = 1
        secondaryLabel.lineBreakMode = .byTruncatingMiddle

        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.addArrangedSubview(primaryLabel)
        textStack.addArrangedSubview(secondaryLabel)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            faviconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            faviconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            faviconView.widthAnchor.constraint(equalToConstant: Self.faviconLength),
            faviconView.heightAnchor.constraint(equalToConstant: Self.faviconLength),
            textStack.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
}
