//
//  LibrarySearchHeaderView.swift
//  OuterView
//

import UIKit

@MainActor
final class LibrarySearchHeaderView: UIView, UISearchBarDelegate {
    nonisolated static let defaultHeight: CGFloat = 64
    nonisolated static let revealThreshold: CGFloat = -28

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

    nonisolated static func requiresCollapse(
        contentHeight: CGFloat,
        boundsHeight: CGFloat,
        headerHeight: CGFloat = LibrarySearchHeaderView.defaultHeight
    ) -> Bool {
        // Zero-geometry tables never collapse.
        guard boundsHeight > 0 else { return false }
        return contentHeight < boundsHeight + headerHeight
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

    func reassert(
        tableView: UITableView,
        header: LibrarySearchHeaderView,
        searchBar: UISearchBar,
        isFiltering: Bool
    ) {
        if searchBar.isFirstResponder || isFiltering || tableView.isEditing {
            if tableView.tableHeaderView == nil {
                attach(header, to: tableView)
            }
            return
        }
        // contentSize is stale until layout runs after reloadData; force it current.
        tableView.layoutIfNeeded()
        let headerHeight = LibrarySearchHeaderView.defaultHeight
        let rawContentHeight = tableView.contentSize.height
        // Normalize: a detached header excludes its height from contentSize, so add
        // it back for a state-independent verdict (attached R+H vs detached R).
        let effectiveContentHeight = tableView.tableHeaderView == nil
            ? rawContentHeight + headerHeight
            : rawContentHeight
        if Self.requiresCollapse(
            contentHeight: effectiveContentHeight,
            boundsHeight: tableView.bounds.height,
            headerHeight: headerHeight
        ) {
            tableView.tableHeaderView = nil
        } else {
            if tableView.tableHeaderView == nil {
                attach(header, to: tableView)
            }
            enforceTuck(tableView, isEditing: searchBar.isFirstResponder, isFiltering: isFiltering)
        }
    }

    func handleScroll(
        _ scrollView: UIScrollView,
        tableView: UITableView,
        header: LibrarySearchHeaderView,
        searchBar: UISearchBar,
        isFiltering: Bool
    ) {
        guard tableView.tableHeaderView == nil, !tableView.isEditing, !searchBar.isFirstResponder, !isFiltering else { return }
        // Pull past the reveal threshold reattaches the header on short lists.
        if scrollView.contentOffset.y < LibrarySearchHeaderView.revealThreshold {
            attach(header, to: tableView)
        }
    }

    private func attach(_ header: LibrarySearchHeaderView, to tableView: UITableView) {
        var frame = header.frame
        frame.size.width = tableView.bounds.width
        frame.size.height = LibrarySearchHeaderView.defaultHeight
        header.frame = frame
        tableView.tableHeaderView = header
    }

    func layoutTuckIfNeeded(
        host: UIView,
        tableView: UITableView,
        header: LibrarySearchHeaderView,
        searchBar: UISearchBar,
        isFiltering: Bool
    ) {
        guard !hasTuckedSearch, host.bounds.width > 0, tableView.bounds.height > 0 else { return }
        hasTuckedSearch = true
        reassert(tableView: tableView, header: header, searchBar: searchBar, isFiltering: isFiltering)
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
        header.onCancel = {
            onCleared()
        }
        header.onBeginEditing = { [weak tableView] in
            tableView?.setContentOffset(.zero, animated: true)
        }
        tableView.tableHeaderView = header
    }
}

/// Shared tuck wiring for the library lists (Bookmarks, History, Reading List).
/// Each host forwards its table view, search header, and filtering state; the
/// scroll snap-back, reassert, and first-layout tuck stay identical here so the
/// three lists never drift.
@MainActor
protocol LibrarySearchTuckable: AnyObject {
    var tuckController: LibrarySearchTuckController { get }
    var tuckTableView: UITableView { get }
    var tuckSearchHeader: LibrarySearchHeaderView { get }
    var isTuckFiltering: Bool { get }
    func reassertSearchTuck()
}

@MainActor
extension LibrarySearchTuckable {
    func reassertSearchTuck() {
        tuckController.reassert(
            tableView: tuckTableView,
            header: tuckSearchHeader,
            searchBar: tuckSearchHeader.searchBar,
            isFiltering: isTuckFiltering
        )
    }

    func handleTuckScroll(_ scrollView: UIScrollView) {
        tuckController.handleScroll(
            scrollView,
            tableView: tuckTableView,
            header: tuckSearchHeader,
            searchBar: tuckSearchHeader.searchBar,
            isFiltering: isTuckFiltering
        )
    }

    func handleTuckEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        guard !willDecelerate else { return }
        tuckController.snapBackIfNeeded(
            scrollView,
            searchBar: tuckSearchHeader.searchBar,
            isFiltering: isTuckFiltering
        )
    }

    func handleTuckEndDecelerating(_ scrollView: UIScrollView) {
        tuckController.snapBackIfNeeded(
            scrollView,
            searchBar: tuckSearchHeader.searchBar,
            isFiltering: isTuckFiltering
        )
    }
}

@MainActor
extension LibrarySearchTuckable where Self: UIView {
    func layoutSearchTuck() {
        tuckController.layoutTuckIfNeeded(
            host: self,
            tableView: tuckTableView,
            header: tuckSearchHeader,
            searchBar: tuckSearchHeader.searchBar,
            isFiltering: isTuckFiltering
        )
    }
}
