//
//  LibrarySearchHeaderView.swift
//  OuterView
//

import UIKit

@MainActor
final class LibrarySearchHeaderView: UIView, UISearchBarDelegate {
    static let defaultHeight: CGFloat = 52

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

        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            searchBar.topAnchor.constraint(equalTo: topAnchor),
            searchBar.bottomAnchor.constraint(equalTo: bottomAnchor)
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

    func tuck(_ tableView: UITableView, animated: Bool) {
        let tuckOffset = CGPoint(x: 0, y: LibrarySearchHeaderView.defaultHeight)
        tableView.setContentOffset(tuckOffset, animated: animated)
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
