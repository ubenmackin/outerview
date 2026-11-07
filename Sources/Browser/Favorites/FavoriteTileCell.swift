// Favorites — Large favicon tile plus folder preview cell.

import UIKit

/// Shared large favicon tile cell with Google S2 / monogram fallback and title.
@MainActor
final class FavoriteTileCell: UICollectionViewCell {
    static let reuseIdentifier = "FavoriteTileCell"
    static let tileLength: CGFloat = 76
    static let cellHeight: CGFloat = 112

    var onCopyURL: (() -> Void)?
    var onDelete: (() -> Void)?

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private var currentURL: URL?
    private var faviconTask: Task<Void, Never>?

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
        currentURL = nil
        onCopyURL = nil
        onDelete = nil
        accessibilityCustomActions = nil
        iconView.image = nil
        titleLabel.text = nil
    }

    private func setup() {
        backgroundColor = .clear

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Double tap to open favorite"

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFill
        iconView.layer.cornerRadius = 18
        iconView.clipsToBounds = true
        iconView.layer.borderWidth = 0.5
        iconView.layer.borderColor = UIColor.separator.cgColor
        contentView.addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor),
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.tileLength),
            iconView.heightAnchor.constraint(equalToConstant: Self.tileLength),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }

    func configure(with bookmark: Bookmark) {
        currentURL = bookmark.url
        let host = HostFormatter.host(of: bookmark.url)
        let displayTitle = bookmark.title.isEmpty ? host : bookmark.title
        titleLabel.text = displayTitle

        isAccessibilityElement = true
        accessibilityTraits = .button
        if !host.isEmpty, !displayTitle.contains(host) {
            accessibilityLabel = "\(displayTitle), \(host)"
        } else {
            accessibilityLabel = displayTitle
        }
        accessibilityHint = "Double tap to open favorite"
        accessibilityIdentifier = "StartPage.Favorite.\(bookmark.url.absoluteString)"

        var actions: [UIAccessibilityCustomAction] = []
        if let onCopyURL {
            actions.append(UIAccessibilityCustomAction(name: "Copy URL") { _ in
                onCopyURL()
                return true
            })
        }
        if let onDelete {
            actions.append(UIAccessibilityCustomAction(name: "Remove from Favorites") { _ in
                onDelete()
                return true
            })
        }
        accessibilityCustomActions = actions

        iconView.image = FaviconService.shared.cachedFaviconOrMonogram(for: bookmark.url, size: Self.tileLength)

        faviconTask?.cancel()
        faviconTask = Task { [weak self, targetURL = bookmark.url] in
            let image = await FaviconService.shared.favicon(for: targetURL, size: Self.tileLength)
            guard !Task.isCancelled, self?.currentURL == targetURL else { return }
            self?.iconView.image = image
        }
    }

    func configure(with folder: BookmarkFolder, previewBookmarks: [Bookmark]) {
        faviconTask?.cancel()
        faviconTask = nil
        currentURL = nil
        titleLabel.text = folder.title

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(folder.title), folder"
        accessibilityHint = "Double tap to open folder"
        accessibilityIdentifier = "StartPage.Folder.\(folder.title)"

        var actions: [UIAccessibilityCustomAction] = []
        if let onDelete {
            actions.append(UIAccessibilityCustomAction(name: "Delete Folder") { _ in
                onDelete()
                return true
            })
        }
        accessibilityCustomActions = actions

        iconView.image = BookmarkFolderIconRenderer.folderBadge(
            for: folder,
            previewBookmarks: previewBookmarks,
            size: Self.tileLength,
            cornerRadius: 18
        )
    }

    func configure(with item: FavoriteItem, previewBookmarks: [Bookmark] = []) {
        switch item {
        case let .bookmark(bookmark):
            configure(with: bookmark)
        case let .folder(folder):
            configure(with: folder, previewBookmarks: previewBookmarks)
        }
    }
}
