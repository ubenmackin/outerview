//
//  LibrarySearchHeaderView.swift
//  OuterView
//

import UIKit

@MainActor
final class LibrarySearchHeaderView: UIView, UISearchBarDelegate {
    nonisolated static let defaultHeight: CGFloat = 64

    var onQueryChanged: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onBeginEditing: (() -> Void)?

    let searchBar = UISearchBar()

    var text: String {
        get { searchBar.text ?? "" }
        set { searchBar.text = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = .clear
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = "Search"
        searchBar.accessibilityLabel = "Search"
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.showsCancelButton = false
        searchBar.delegate = self
        addSubview(searchBar)

        // 6 pt top + 44 pt bar + 14 pt bottom reveal gap (spacing between the
        // revealed bar and the list content) = defaultHeight.
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            searchBar.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            searchBar.heightAnchor.constraint(equalToConstant: 44),
            searchBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }

    func reset() {
        searchBar.text = ""
        searchBar.setShowsCancelButton(false, animated: true)
        searchBar.resignFirstResponder()
    }

    // MARK: - UISearchBarDelegate

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
        onBeginEditing?()
    }

    func searchBar(_: UISearchBar, textDidChange searchText: String) {
        onQueryChanged?(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.setShowsCancelButton(false, animated: true)
        searchBar.resignFirstResponder()
        onQueryChanged?("")
        onCancel?()
    }
}

/// Shared pull-down search tuck for the library lists. Each list owns one
/// controller and forwards its table view; the tuck offset, first-layout
/// tuck, header wiring, and snap-back stay identical across History,
/// Reading List, and Bookmarks.
@MainActor
final class LibrarySearchTuckController {
    private var hasTuckedSearch = false

    /// Re-tuck only when editing ended, no query filters the list, and the
    /// table sits at or above the hidden offset (including negative pull-down
    /// bounce), so reloads never re-expose a revealed bar.
    nonisolated static func shouldRetuck(
        isEditing: Bool,
        isFiltering: Bool,
        offsetY: CGFloat,
        headerHeight: CGFloat = LibrarySearchHeaderView.defaultHeight
    ) -> Bool {
        !isEditing && !isFiltering && offsetY < headerHeight
    }

    func tuck(_ tableView: UITableView, animated: Bool) {
        let tuckOffset = CGPoint(x: 0, y: LibrarySearchHeaderView.defaultHeight)
        tableView.setContentOffset(tuckOffset, animated: animated)
    }

    /// Re-asserts the hidden bar immediately after a reload without animating.
    func enforceTuck(_ tableView: UITableView, isEditing: Bool, isFiltering: Bool) {
        guard Self.shouldRetuck(
            isEditing: isEditing,
            isFiltering: isFiltering,
            offsetY: tableView.contentOffset.y
        ) else { return }
        tuck(tableView, animated: false)
    }

    func layoutTuckIfNeeded(host: UIView, tableView: UITableView) {
        if !hasTuckedSearch, host.bounds.width > 0 {
            hasTuckedSearch = true
            tuck(tableView, animated: false)
        }
    }

    func snapBackIfNeeded(_ scrollView: UIScrollView, searchBar: UISearchBar, isFiltering: Bool) {
        guard !searchBar.isFirstResponder, !isFiltering else { return }
        let defaultH = LibrarySearchHeaderView.defaultHeight
        let offsetY = scrollView.contentOffset.y
        if offsetY > 0, offsetY < defaultH {
            let targetY = offsetY < defaultH / 2 ? 0 : defaultH
            scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: true)
        }
    }

    func wire(
        header: LibrarySearchHeaderView,
        tableView: UITableView,
        onQueryChanged: @escaping (String) -> Void,
        onCleared: @escaping () -> Void
    ) {
        header.onQueryChanged = { query in
            onQueryChanged(query)
        }
        header.onCancel = { [weak self, weak tableView] in
            onCleared()
            guard let tableView else { return }
            self?.tuck(tableView, animated: true)
        }
        header.onBeginEditing = { [weak tableView] in
            tableView?.setContentOffset(.zero, animated: true)
        }
        tableView.tableHeaderView = header
    }
}
