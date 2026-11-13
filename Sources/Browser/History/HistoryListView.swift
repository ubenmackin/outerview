//
//  HistoryListView.swift
//  OuterView
//

import os
import UIKit

/// Shared base for library list rows so later lists reuse one cell pattern.
@MainActor
class LibrarySubtitleCell: UITableViewCell {
    nonisolated static let selectionLeadingInset: CGFloat = 50

    private let selectionIndicatorView = UIImageView()
    private(set) var isShowingSelectionIndicator = false
    private(set) var isSelectionIndicatorChecked = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .secondarySystemGroupedBackground
        selectionIndicatorView.contentMode = .scaleAspectFit
        selectionIndicatorView.accessibilityIdentifier = "LibrarySubtitleCell.SelectionIndicator"
        selectionIndicatorView.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configureSelectionIndicator(visible: false, isSelected: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard selectionIndicatorView.superview === contentView, !selectionIndicatorView.isHidden else { return }
        let size: CGFloat = 22
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let originX: CGFloat = isRTL ? contentView.bounds.width - 16 - size : 16
        let originY = floor((contentView.bounds.height - size) / 2)
        selectionIndicatorView.frame = CGRect(x: originX, y: originY, width: size, height: size)
        contentView.bringSubviewToFront(selectionIndicatorView)
    }

    func configureSelectionIndicator(visible: Bool, isSelected: Bool) {
        isShowingSelectionIndicator = visible
        isSelectionIndicatorChecked = visible && isSelected
        guard visible else {
            selectionIndicatorView.isHidden = true
            selectionIndicatorView.removeFromSuperview()
            return
        }
        if selectionIndicatorView.superview !== contentView {
            contentView.addSubview(selectionIndicatorView)
        }
        selectionIndicatorView.isHidden = false
        let symbol = isSelected ? "checkmark.circle.fill" : "circle"
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        selectionIndicatorView.image = UIImage(systemName: symbol, withConfiguration: config)
        selectionIndicatorView.tintColor = isSelected ? .systemBlue : .tertiaryLabel
        setNeedsLayout()
    }
}

/// Subtitle-style cell so dequeued reuse keeps its detail label.
@MainActor
final class HistoryEntryCell: LibrarySubtitleCell {
    override init(style _: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Displays visited history segmented into Safari-style time buckets
/// with clear-all, multi-select deletion, pull-down to reveal search, and swipe-to-delete capabilities.
@MainActor
final class HistoryListView: UIView {
    var onOpenURL: (@MainActor (URL) -> Void)?
    var onStateChanged: (@MainActor () -> Void)?
    var onDidMutateHistory: (@MainActor () -> Void)?

    private let historyStore: HistoryStore
    private var sections: [HistorySection] = []

    private(set) var searchQuery: String = ""
    private(set) var isSelectionMode: Bool = false
    private(set) var selectedEntryIDs: Set<UUID> = []

    var canClearHistory: Bool {
        !sections.isEmpty || !searchQuery.isEmpty && !historyStore.fetchAll(limit: 1).isEmpty
    }

    var hasSelectedEntries: Bool {
        !selectedEntryIDs.isEmpty
    }

    private let headerBar = UIView()
    private var headerTopConstraint: NSLayoutConstraint?
    private var headerHeightConstraint: NSLayoutConstraint?
    private var hidesInlineHeaderBar = false
    private let titleLabel = UILabel()
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private let searchHeader = LibrarySearchHeaderView(
        frame: CGRect(x: 0, y: 0, width: 0, height: LibrarySearchHeaderView.defaultHeight)
    )

    private let searchTuck = LibrarySearchTuckController()

    func setHeaderBarHidden(_ hidden: Bool) {
        hidesInlineHeaderBar = hidden
        if !hidden, isSelectionMode {
            isSelectionMode = false
            selectedEntryIDs.removeAll()
        }
        headerBar.isHidden = hidden
        headerTopConstraint?.constant = hidden ? 0 : 4
        headerHeightConstraint?.constant = hidden ? 0 : 40
        tableView.reloadData()
    }

    func enterSelectionMode() {
        isSelectionMode = true
        selectedEntryIDs.removeAll()
        tableView.reloadData()
        reassertSearchTuck()
        onStateChanged?()
    }

    func exitSelectionMode() {
        guard isSelectionMode || !selectedEntryIDs.isEmpty else { return }
        isSelectionMode = false
        selectedEntryIDs.removeAll()
        tableView.reloadData()
        reassertSearchTuck()
        onStateChanged?()
    }

    func deleteSelectedEntries() {
        guard !selectedEntryIDs.isEmpty else { return }
        do {
            try historyStore.delete(ids: selectedEntryIDs)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("delete selected history entries failed: \(error.localizedDescription, privacy: .public)")
        }
        selectedEntryIDs.removeAll()
        reload()
        if sections.isEmpty {
            isSelectionMode = false
        }
        onDidMutateHistory?()
        onStateChanged?()
    }

    func visibleEntryID(at indexPath: IndexPath) -> UUID? {
        guard indexPath.section < sections.count,
              indexPath.row < sections[indexPath.section].entries.count
        else { return nil }
        return sections[indexPath.section].entries[indexPath.row].id
    }

    init(historyStore: HistoryStore) {
        self.historyStore = historyStore
        super.init(frame: .zero)
        setup()
        reload()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        let all = historyStore.fetchAll(limit: 500)
        let validIDs = Set(all.map(\.id))
        selectedEntryIDs.formIntersection(validIDs)
        if all.isEmpty {
            isSelectionMode = false
        }
        let filtered: [HistoryEntry]
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            filtered = all.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                    $0.url.absoluteString.localizedCaseInsensitiveContains(query)
            }
        } else {
            filtered = all
        }
        sections = HistorySegmenter.segment(entries: filtered)
        let isEmpty = sections.isEmpty
        if isEmpty {
            emptyLabel.text = query.isEmpty ? "No History" : "No Results for \"\(query)\""
        }
        emptyLabel.isHidden = !isEmpty
        tableView.reloadData()
        reassertSearchTuck()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSearchTuck()
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .clear

        headerBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerBar)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "History"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        headerBar.addSubview(titleLabel)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No History"
        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.alwaysBounceVertical = true
        tableView.register(HistoryEntryCell.self, forCellReuseIdentifier: "HistoryEntryCell")
        addSubview(tableView)

        searchTuck.wire(
            header: searchHeader,
            tableView: tableView,
            onQueryChanged: { [weak self] query in
                guard let self else { return }
                self.searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                self.reload()
            },
            onCleared: { [weak self] in
                guard let self else { return }
                self.searchQuery = ""
                self.reload()
            }
        )

        let headerTop = headerBar.topAnchor.constraint(equalTo: topAnchor, constant: 4)
        let headerHeight = headerBar.heightAnchor.constraint(equalToConstant: 40)
        headerTopConstraint = headerTop
        headerHeightConstraint = headerHeight

        NSLayoutConstraint.activate([
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            headerTop,
            headerHeight,

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

    func promptClearHistory() {
        guard let windowScene = window?.windowScene,
              let rootVC = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController
        else {
            return
        }
        var presenter = rootVC
        while let next = presenter.presentedViewController {
            presenter = next
        }

        let sheet = UIAlertController(title: "Clear History", message: "Clearing history will remove browsing data from OuterView.", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Clear All History", style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                try self.historyStore.clear()
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("clear history failed: \(error.localizedDescription, privacy: .public)")
            }
            self.isSelectionMode = false
            self.selectedEntryIDs.removeAll()
            self.reload()
            self.onDidMutateHistory?()
            self.onStateChanged?()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            if headerBar.isHidden {
                popover.sourceView = self
                popover.sourceRect = CGRect(x: bounds.midX, y: 24, width: 1, height: 1)
            } else {
                popover.sourceView = headerBar
                popover.sourceRect = headerBar.bounds
            }
            popover.permittedArrowDirections = []
        }
        presenter.present(sheet, animated: true)
    }

    private static func roundedFavicon(for url: URL, size: CGFloat = 26) -> UIImage {
        let base = FaviconService.shared.cachedFaviconOrMonogram(for: url, size: size)
        let targetSize = CGSize(width: size, height: size)
        return UIGraphicsImageRenderer(size: targetSize).image { _ in
            let rect = CGRect(origin: .zero, size: targetSize)
            UIBezierPath(roundedRect: rect, cornerRadius: 6).addClip()
            base.draw(in: rect)
        }
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension HistoryListView: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].entries.count
    }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryEntryCell", for: indexPath)
        let entry = sections[indexPath.section].entries[indexPath.row]
        let isRowSelected = isSelectionMode && selectedEntryIDs.contains(entry.id)
        cell.backgroundColor = isRowSelected ? .tertiarySystemGroupedBackground : .secondarySystemGroupedBackground

        if hidesInlineHeaderBar {
            let leadingMargin: CGFloat = isSelectionMode ? LibrarySubtitleCell.selectionLeadingInset : 16
            var content = UIListContentConfiguration.subtitleCell()
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(
                top: 10, leading: leadingMargin, bottom: 10, trailing: 16
            )
            content.textToSecondaryTextVerticalPadding = 3
            content.text = entry.title.isEmpty ? HostFormatter.host(of: entry.url) : entry.title
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.textProperties.color = .label
            content.secondaryText = entry.url.absoluteString
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            content.secondaryTextProperties.color = .secondaryLabel
            content.image = Self.roundedFavicon(for: entry.url)
            cell.contentConfiguration = content
            (cell as? LibrarySubtitleCell)?.configureSelectionIndicator(
                visible: isSelectionMode,
                isSelected: isRowSelected
            )
            return cell
        }

        (cell as? LibrarySubtitleCell)?.configureSelectionIndicator(visible: false, isSelected: false)
        cell.contentConfiguration = nil
        cell.textLabel?.text = entry.title.isEmpty ? HostFormatter.host(of: entry.url) : entry.title
        cell.detailTextLabel?.text = HostFormatter.host(of: entry.url)
        cell.imageView?.image = UIImage(systemName: "clock")
        cell.imageView?.tintColor = .secondaryLabel

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = sections[indexPath.section].entries[indexPath.row]
        if isSelectionMode {
            if selectedEntryIDs.contains(entry.id) {
                selectedEntryIDs.remove(entry.id)
            } else {
                selectedEntryIDs.insert(entry.id)
            }
            tableView.reloadRows(at: [indexPath], with: .none)
            onStateChanged?()
            return
        }
        onOpenURL?(entry.url)
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !isSelectionMode else { return nil }
        let entry = sections[indexPath.section].entries[indexPath.row]
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            do {
                try self.historyStore.delete(id: entry.id)
                self.reload()
                self.onDidMutateHistory?()
                self.onStateChanged?()
                completion(true)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "History")
                    .error("swipe delete history entry failed: \(error.localizedDescription, privacy: .public)")
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

extension HistoryListView: LibrarySearchTuckable {
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
