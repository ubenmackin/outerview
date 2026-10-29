//
//  HistoryListView.swift
//  OuterView
//

import os
import UIKit

/// Shared base for library list rows so later lists reuse one cell pattern.
@MainActor
class LibrarySubtitleCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .secondarySystemGroupedBackground
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
/// with clear-all, pull-down to reveal search, and swipe-to-delete capabilities.
@MainActor
final class HistoryListView: UIView {
    var onOpenURL: ((URL) -> Void)?

    private let historyStore: HistoryStore
    private var sections: [HistorySection] = []

    private(set) var searchQuery: String = ""

    var canClearHistory: Bool {
        !sections.isEmpty
    }

    private let headerBar = UIView()
    private let titleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private let searchHeader = LibrarySearchHeaderView(
        frame: CGRect(x: 0, y: 0, width: 0, height: LibrarySearchHeaderView.defaultHeight)
    )

    private let searchTuck = LibrarySearchTuckController()

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
        searchTuck.enforceTuck(tableView, isEditing: searchHeader.searchBar.isFirstResponder, isFiltering: !searchQuery.isEmpty)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        searchTuck.layoutTuckIfNeeded(host: self, tableView: tableView)
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
                self.searchQuery = query
                self.reload()
            },
            onCleared: { [weak self] in
                guard let self else { return }
                self.searchQuery = ""
                self.reload()
            }
        )

        NSLayoutConstraint.activate([
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            headerBar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            headerBar.heightAnchor.constraint(equalToConstant: 40),

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

        let sheet = UIAlertController(title: "Clear History", message: "Clearing history will remove browsing data from OuterView.", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Clear All History", style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                try self.historyStore.clear()
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("clear history failed: \(error.localizedDescription, privacy: .public)")
            }
            self.reload()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = headerBar
            popover.sourceRect = headerBar.bounds
            popover.permittedArrowDirections = []
        }
        rootVC.present(sheet, animated: true)
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
        cell.backgroundColor = .secondarySystemGroupedBackground

        let entry = sections[indexPath.section].entries[indexPath.row]
        cell.textLabel?.text = entry.title.isEmpty ? HostFormatter.host(of: entry.url) : entry.title
        cell.detailTextLabel?.text = HostFormatter.host(of: entry.url)
        cell.imageView?.image = UIImage(systemName: "clock")
        cell.imageView?.tintColor = .secondaryLabel

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = sections[indexPath.section].entries[indexPath.row]
        onOpenURL?(entry.url)
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let entry = sections[indexPath.section].entries[indexPath.row]
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            do {
                try self.historyStore.delete(id: entry.id)
                self.reload()
                completion(true)
            } catch {
                completion(false)
            }
        }
        deleteAction.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate _: Bool) {
        searchTuck.snapBackIfNeeded(scrollView, searchBar: searchHeader.searchBar, isFiltering: !searchQuery.isEmpty)
    }
}
