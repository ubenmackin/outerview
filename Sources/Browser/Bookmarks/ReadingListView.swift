// Bookmarks — Saved-pages list with display modes plus filtering and batch delete.

import os
import UIKit

enum ReadingListDisplayMode: String, Sendable {
    case compact
    case large
}

enum ReadingListFilterMode: String, Sendable {
    case all
    case unreadOnly
}

/// Custom cell supporting Compact and Large display modes, row selection indicator,
/// and preview snippet display.
@MainActor
final class ReadingListItemCell: LibrarySubtitleCell {
    private let selectionCheckImageView = UIImageView()
    private let faviconImageView = UIImageView()
    private let textStack = UIStackView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let previewLabel = UILabel()

    private var selectionCheckWidthConstraint: NSLayoutConstraint?
    private var selectionCheckMarginConstraint: NSLayoutConstraint?
    private var faviconWidthConstraint: NSLayoutConstraint?
    private var faviconHeightConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground

        isAccessibilityElement = true
        accessibilityTraits = .button

        selectionCheckImageView.translatesAutoresizingMaskIntoConstraints = false
        selectionCheckImageView.contentMode = .scaleAspectFit
        selectionCheckImageView.clipsToBounds = true
        contentView.addSubview(selectionCheckImageView)

        faviconImageView.translatesAutoresizingMaskIntoConstraints = false
        faviconImageView.contentMode = .scaleAspectFill
        faviconImageView.clipsToBounds = true
        contentView.addSubview(faviconImageView)

        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.alignment = .leading
        contentView.addSubview(textStack)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        textStack.addArrangedSubview(titleLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        textStack.addArrangedSubview(detailLabel)

        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.adjustsFontForContentSizeCategory = true
        previewLabel.font = .preferredFont(forTextStyle: .footnote)
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 2
        textStack.addArrangedSubview(previewLabel)

        let checkWidth = selectionCheckImageView.widthAnchor.constraint(equalToConstant: 24)
        let checkMargin = faviconImageView.leadingAnchor.constraint(equalTo: selectionCheckImageView.trailingAnchor, constant: 10)
        let favWidth = faviconImageView.widthAnchor.constraint(equalToConstant: 26)
        let favHeight = faviconImageView.heightAnchor.constraint(equalToConstant: 26)

        selectionCheckWidthConstraint = checkWidth
        selectionCheckMarginConstraint = checkMargin
        faviconWidthConstraint = favWidth
        faviconHeightConstraint = favHeight

        NSLayoutConstraint.activate([
            selectionCheckImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            selectionCheckImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectionCheckImageView.heightAnchor.constraint(equalToConstant: 24),
            checkWidth,

            checkMargin,
            faviconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            favWidth,
            favHeight,

            textStack.leadingAnchor.constraint(equalTo: faviconImageView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    func configure(
        item: ReadingListItem,
        displayMode: ReadingListDisplayMode,
        isSelectionMode: Bool,
        isRowSelected: Bool
    ) {
        let isLarge = (displayMode == .large)
        let host = HostFormatter.host(of: item.url)
        let displayTitle = item.title.isEmpty ? host : item.title

        titleLabel.text = displayTitle
        if isLarge {
            titleLabel.font = item.isRead
                ? .preferredFont(forTextStyle: .headline)
                : UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .headline).pointSize, weight: .bold)
        } else {
            let bodyFont = UIFont.preferredFont(forTextStyle: .body)
            titleLabel.font = item.isRead
                ? bodyFont
                : UIFont.systemFont(ofSize: bodyFont.pointSize, weight: .semibold)
        }

        detailLabel.text = host

        // Preview snippet (first sentence or two) in Large mode
        if isLarge, let preview = item.previewText, !preview.isEmpty {
            previewLabel.text = preview
            previewLabel.isHidden = false
        } else {
            previewLabel.text = nil
            previewLabel.isHidden = true
        }

        // Favicon sizing
        let iconSize: CGFloat = isLarge ? 44 : 26
        faviconWidthConstraint?.constant = iconSize
        faviconHeightConstraint?.constant = iconSize
        faviconImageView.layer.cornerRadius = isLarge ? 8 : 6
        faviconImageView.image = FaviconService.shared.cachedFaviconOrMonogram(for: item.url, size: iconSize)

        // Selection mode display
        if isSelectionMode {
            selectionCheckImageView.isHidden = false
            selectionCheckWidthConstraint?.constant = 24
            selectionCheckMarginConstraint?.constant = 10

            if isRowSelected {
                selectionCheckImageView.image = UIImage(systemName: "checkmark.circle.fill")
                selectionCheckImageView.tintColor = .systemBlue
                backgroundColor = .tertiarySystemGroupedBackground
            } else {
                selectionCheckImageView.image = UIImage(systemName: "circle")
                selectionCheckImageView.tintColor = .tertiaryLabel
                backgroundColor = .secondarySystemGroupedBackground
            }
        } else {
            selectionCheckImageView.isHidden = true
            selectionCheckWidthConstraint?.constant = 0
            selectionCheckMarginConstraint?.constant = 0
            backgroundColor = .secondarySystemGroupedBackground
        }

        isAccessibilityElement = true
        accessibilityTraits = .button
        if !host.isEmpty, !displayTitle.contains(host) {
            accessibilityLabel = "\(displayTitle), \(host)"
        } else {
            accessibilityLabel = displayTitle
        }
        var valueParts = [item.isRead ? "Read" : "Unread"]
        if isLarge, let preview = item.previewText, !preview.isEmpty {
            valueParts.append(preview)
        }
        accessibilityValue = valueParts.joined(separator: ", ")
        accessibilityHint = "Double tap to open saved page"
    }
}

/// Displays pages saved for later with Compact / Large views, All / Unread filtering,
/// pull-down to reveal search, and batch selection deletion.
@MainActor
final class ReadingListView: UIView {
    var onOpenURL: ((URL) -> Void)?
    var onStateChanged: (() -> Void)?
    var onSelectionModeChanged: ((Bool) -> Void)?

    private let store: ReadingListStore
    private let defaults: UserDefaults
    private var items: [ReadingListItem] = []

    private(set) var displayMode: ReadingListDisplayMode = .compact
    private(set) var filterMode: ReadingListFilterMode = .all
    private(set) var isSelectionMode: Bool = false
    private(set) var selectedItemIDs: Set<UUID> = []
    private(set) var searchQuery: String = ""

    var hasSelectedItems: Bool {
        !selectedItemIDs.isEmpty
    }

    private let headerBar = UIView()
    private var headerTopConstraint: NSLayoutConstraint!
    private var headerHeightConstraint: NSLayoutConstraint!
    private let titleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private let searchHeader = LibrarySearchHeaderView(
        frame: CGRect(x: 0, y: 0, width: 0, height: LibrarySearchHeaderView.defaultHeight)
    )

    private let searchTuck = LibrarySearchTuckController()

    func setHeaderBarHidden(_ hidden: Bool) {
        headerBar.isHidden = hidden
        headerTopConstraint.constant = hidden ? 0 : 4
        headerHeightConstraint.constant = hidden ? 0 : 40
    }

    nonisolated static let displayModeDefaultsKey = "readingList.displayMode"
    nonisolated static let filterModeDefaultsKey = "readingList.filterMode"

    nonisolated static func storedDisplayMode(defaults: UserDefaults = .standard) -> ReadingListDisplayMode {
        guard let raw = defaults.string(forKey: displayModeDefaultsKey),
              let mode = ReadingListDisplayMode(rawValue: raw)
        else {
            return .compact
        }
        return mode
    }

    nonisolated static func storedFilterMode(defaults: UserDefaults = .standard) -> ReadingListFilterMode {
        guard let raw = defaults.string(forKey: filterModeDefaultsKey),
              let mode = ReadingListFilterMode(rawValue: raw)
        else {
            return .all
        }
        return mode
    }

    nonisolated static func persist(displayMode: ReadingListDisplayMode, defaults: UserDefaults = .standard) {
        defaults.set(displayMode.rawValue, forKey: displayModeDefaultsKey)
    }

    nonisolated static func persist(filterMode: ReadingListFilterMode, defaults: UserDefaults = .standard) {
        defaults.set(filterMode.rawValue, forKey: filterModeDefaultsKey)
    }

    init(store: ReadingListStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        super.init(frame: .zero)
        displayMode = Self.storedDisplayMode(defaults: defaults)
        filterMode = Self.storedFilterMode(defaults: defaults)
        setup()
        reload()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        items = store.fetchAll()
        updateEmptyState()
        tableView.reloadData()
        reassertSearchTuck()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSearchTuck()
    }

    // MARK: - Menu & Display Modes

    func setDisplayMode(_ mode: ReadingListDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode
        Self.persist(displayMode: mode, defaults: defaults)
        tableView.reloadData()
        reassertSearchTuck()
        onStateChanged?()
    }

    func setFilterMode(_ mode: ReadingListFilterMode) {
        guard filterMode != mode else { return }
        filterMode = mode
        Self.persist(filterMode: mode, defaults: defaults)
        updateEmptyState()
        tableView.reloadData()
        reassertSearchTuck()
        onStateChanged?()
    }

    func enterSelectionMode() {
        isSelectionMode = true
        selectedItemIDs.removeAll()
        searchHeader.reset()
        searchQuery = ""
        updateEmptyState()
        tableView.reloadData()
        reassertSearchTuck()
        onSelectionModeChanged?(true)
    }

    func exitSelectionMode() {
        isSelectionMode = false
        selectedItemIDs.removeAll()
        updateEmptyState()
        tableView.reloadData()
        reassertSearchTuck()
        onSelectionModeChanged?(false)
    }

    func deleteSelectedItems() {
        guard !selectedItemIDs.isEmpty else { return }
        let idsToDelete = selectedItemIDs
        do {
            try store.delete(ids: idsToDelete)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("delete selected reading list items failed: \(error.localizedDescription, privacy: .public)")
        }
        selectedItemIDs.removeAll()
        reload()
        onStateChanged?()
    }

    func makeMenu() -> UIMenu {
        let largeAction = UIAction(
            title: "Large",
            image: UIImage(systemName: "rectangle.grid.1x2"),
            state: displayMode == .large ? .on : .off
        ) { [weak self] _ in
            self?.setDisplayMode(.large)
        }

        let compactAction = UIAction(
            title: "Compact",
            image: UIImage(systemName: "list.bullet"),
            state: displayMode == .compact ? .on : .off
        ) { [weak self] _ in
            self?.setDisplayMode(.compact)
        }

        let allAction = UIAction(
            title: "All",
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            state: filterMode == .all ? .on : .off
        ) { [weak self] _ in
            self?.setFilterMode(.all)
        }

        let unreadAction = UIAction(
            title: "Unread Only",
            image: UIImage(systemName: "circle"),
            state: filterMode == .unreadOnly ? .on : .off
        ) { [weak self] _ in
            self?.setFilterMode(.unreadOnly)
        }

        let selectAction = UIAction(
            title: "Select Items",
            image: UIImage(systemName: "checkmark.circle")
        ) { [weak self] _ in
            self?.enterSelectionMode()
        }

        let displaySection = UIMenu(title: "", options: .displayInline, children: [largeAction, compactAction])
        let filterSection = UIMenu(title: "", options: .displayInline, children: [allAction, unreadAction])
        let actionsSection = UIMenu(title: "", options: .displayInline, children: [selectAction])

        return UIMenu(title: "", children: [displaySection, filterSection, actionsSection])
    }

    // MARK: - Private

    private var filteredItems: [ReadingListItem] {
        items.filter { item in
            if filterMode == .unreadOnly, item.isRead {
                return false
            }
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                let host = HostFormatter.host(of: item.url)
                let matchesTitle = item.title.localizedCaseInsensitiveContains(query)
                let matchesHost = host.localizedCaseInsensitiveContains(query)
                let matchesPreview = item.previewText?.localizedCaseInsensitiveContains(query) ?? false
                if !matchesTitle, !matchesHost, !matchesPreview {
                    return false
                }
            }
            return true
        }
    }

    private func updateEmptyState() {
        let visible = filteredItems
        let isEmpty = visible.isEmpty
        if isEmpty {
            if !searchQuery.isEmpty {
                emptyLabel.text = "No Results for \"\(searchQuery)\""
            } else if filterMode == .unreadOnly {
                emptyLabel.text = "No Unread Pages"
            } else {
                emptyLabel.text = "No Saved Pages — Use the page menu to add pages for later."
            }
        }
        emptyLabel.isHidden = !isEmpty
        tableView.isHidden = false
    }

    private func setup() {
        backgroundColor = .clear

        headerBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerBar)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Reading List"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        headerBar.addSubview(titleLabel)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No Saved Pages — Use the page menu to add pages for later."
        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.alwaysBounceVertical = true
        tableView.register(ReadingListItemCell.self, forCellReuseIdentifier: "ReadingListItemCell")
        addSubview(tableView)

        searchTuck.wire(
            header: searchHeader,
            tableView: tableView,
            onQueryChanged: { [weak self] query in
                guard let self else { return }
                self.searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                self.updateEmptyState()
                self.tableView.reloadData()
                self.reassertSearchTuck()
            },
            onCleared: { [weak self] in
                guard let self else { return }
                self.searchQuery = ""
                self.updateEmptyState()
                self.tableView.reloadData()
                self.reassertSearchTuck()
            }
        )

        headerTopConstraint = headerBar.topAnchor.constraint(equalTo: topAnchor, constant: 4)
        headerHeightConstraint = headerBar.heightAnchor.constraint(equalToConstant: 40)

        NSLayoutConstraint.activate([
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            headerTopConstraint,
            headerHeightConstraint,

            titleLabel.centerXAnchor.constraint(equalTo: headerBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension ReadingListView: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in _: UITableView) -> Int {
        1
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        filteredItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: "ReadingListItemCell",
            for: indexPath
        ) as? ReadingListItemCell else {
            return UITableViewCell()
        }

        let item = filteredItems[indexPath.row]
        let isSelected = selectedItemIDs.contains(item.id)
        cell.configure(
            item: item,
            displayMode: displayMode,
            isSelectionMode: isSelectionMode,
            isRowSelected: isSelected
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = filteredItems[indexPath.row]
        if isSelectionMode {
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)
            } else {
                selectedItemIDs.insert(item.id)
            }
            tableView.reloadRows(at: [indexPath], with: .none)
            onStateChanged?()
        } else {
            do {
                try store.setRead(id: item.id, isRead: true)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("mark reading list item read failed: \(error.localizedDescription, privacy: .public)")
            }
            reload()
            onOpenURL?(item.url)
        }
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !isSelectionMode else { return nil }
        let item = filteredItems[indexPath.row]
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            do {
                try self.store.delete(id: item.id)
                self.reload()
                self.onStateChanged?()
                completion(true)
            } catch {
                completion(false)
            }
        }
        deleteAction.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        handleTuckScroll(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        handleTuckEndDragging(scrollView, willDecelerate: willDecelerate)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        handleTuckEndDecelerating(scrollView)
    }
}

// MARK: - LibrarySearchTuckable

extension ReadingListView: LibrarySearchTuckable {
    var tuckController: LibrarySearchTuckController {
        searchTuck
    }

    var tuckTableView: UITableView {
        tableView
    }

    var tuckSearchHeader: LibrarySearchHeaderView {
        searchHeader
    }

    var isTuckFiltering: Bool {
        !searchQuery.isEmpty
    }
}
