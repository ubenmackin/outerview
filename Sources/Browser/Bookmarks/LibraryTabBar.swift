//
//  LibraryTabBar.swift
//  OuterView
//

import UIKit

enum LibraryTab: Int, CaseIterable, Sendable {
    case favorites = 0
    case bookmarks = 1
    case history = 2
    case readingList = 3

    var title: String {
        switch self {
        case .favorites: "Favorites"
        case .bookmarks: "Bookmarks"
        case .history: "History"
        case .readingList: "Reading List"
        }
    }

    var systemImageName: String {
        switch self {
        case .favorites: "star"
        case .bookmarks: "book"
        case .history: "clock"
        case .readingList: "eyeglasses"
        }
    }
}

/// Single owner for per-tab library commands. Both the regular inline header
/// (`BookmarksLibraryView.updateInlineCommands`) and the compact rail
/// (`BrowserRootViewController.updateLibraryRailItems`) render from this model
/// so per-tab branching (bookmarks add/edit, history clear, reading-list
/// menu/delete/selection, favorites empty plus Done/exit-selection semantics)
/// can never drift apart.
struct LibraryTabCommands: Sendable, Equatable {
    var showsAdd: Bool
    var showsEdit: Bool
    var isEditingBookmarks: Bool
    var showsClear: Bool
    var canClearHistory: Bool
    var showsMenu: Bool
    var showsDelete: Bool
    var canDeleteSelection: Bool
    var doneExitsSelection: Bool

    static func make(
        for tab: LibraryTab,
        isEditingBookmarks: Bool,
        canClearHistory: Bool,
        isInSelection: Bool,
        canDeleteSelection: Bool,
        hasReadingListMenu: Bool
    ) -> LibraryTabCommands {
        switch tab {
        case .bookmarks, .history, .readingList:
            if isInSelection {
                return LibraryTabCommands(
                    showsAdd: false,
                    showsEdit: false,
                    isEditingBookmarks: false,
                    showsClear: false,
                    canClearHistory: false,
                    showsMenu: false,
                    showsDelete: true,
                    canDeleteSelection: canDeleteSelection,
                    doneExitsSelection: true
                )
            }
        case .favorites:
            break
        }

        switch tab {
        case .bookmarks:
            return LibraryTabCommands(
                showsAdd: true,
                showsEdit: true,
                isEditingBookmarks: isEditingBookmarks,
                showsClear: false,
                canClearHistory: false,
                showsMenu: false,
                showsDelete: false,
                canDeleteSelection: false,
                doneExitsSelection: false
            )
        case .history:
            return LibraryTabCommands(
                showsAdd: false,
                showsEdit: false,
                isEditingBookmarks: false,
                showsClear: true,
                canClearHistory: canClearHistory,
                showsMenu: false,
                showsDelete: false,
                canDeleteSelection: false,
                doneExitsSelection: false
            )
        case .readingList:
            return LibraryTabCommands(
                showsAdd: false,
                showsEdit: false,
                isEditingBookmarks: false,
                showsClear: false,
                canClearHistory: false,
                showsMenu: hasReadingListMenu,
                showsDelete: false,
                canDeleteSelection: false,
                doneExitsSelection: false
            )
        case .favorites:
            return LibraryTabCommands(
                showsAdd: false,
                showsEdit: false,
                isEditingBookmarks: false,
                showsClear: false,
                canClearHistory: false,
                showsMenu: false,
                showsDelete: false,
                canDeleteSelection: false,
                doneExitsSelection: false
            )
        }
    }
}

/// Top tab bar for the Bookmarks & History library overlay, letting users switch
/// between Favorites, Bookmarks, History, and Reading List.
/// UserDefaults keys libraryTab as Int, overviewMode as String, and overviewGroup as String.
/// Values are read at init and setup and written on every change; private mode is never
/// written and restores as standard. Unparseable values fall back to bookmarks, standard,
/// and nil; a stored group id resolving to no existing group restores as nil.
@MainActor
final class LibraryTabBar: UIView {
    nonisolated static let libraryTabDefaultsKey = "libraryTab"

    nonisolated static func storedTab(defaults: UserDefaults = .standard) -> LibraryTab {
        guard let object = defaults.object(forKey: libraryTabDefaultsKey),
              let raw = object as? Int,
              let tab = LibraryTab(rawValue: raw)
        else {
            return .bookmarks
        }
        return tab
    }

    nonisolated static func persist(tab: LibraryTab, defaults: UserDefaults = .standard) {
        defaults.set(tab.rawValue, forKey: libraryTabDefaultsKey)
    }

    var onTabSelected: ((LibraryTab) -> Void)?

    private(set) var selectedTab: LibraryTab = .bookmarks

    private let defaults: UserDefaults
    private let segmentedControl: UISegmentedControl

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedTab = Self.storedTab(defaults: defaults)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let items = LibraryTab.allCases.map { tab in
            let image = UIImage(systemName: tab.systemImageName, withConfiguration: config) ?? UIImage()
            image.accessibilityLabel = tab.title
            return image
        }
        segmentedControl = UISegmentedControl(items: items)
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSegmentAccessibility()
    }

    func selectTab(_ tab: LibraryTab, notify: Bool = true) {
        selectedTab = tab
        Self.persist(tab: tab, defaults: defaults)
        segmentedControl.selectedSegmentIndex = tab.rawValue
        updateSegmentAccessibility()
        if notify {
            onTabSelected?(tab)
        }
    }

    func segmentAccessibilityLabel(at index: Int) -> String? {
        guard index >= 0, index < LibraryTab.allCases.count else { return nil }
        return LibraryTab(rawValue: index)?.title
    }

    // MARK: - Private

    private func setup() {
        segmentedControl.selectedSegmentIndex = selectedTab.rawValue
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.accessibilityIdentifier = "LibraryTabBar.SegmentedControl"
        segmentedControl.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if let tab = LibraryTab(rawValue: self.segmentedControl.selectedSegmentIndex) {
                self.selectedTab = tab
                Self.persist(tab: tab, defaults: self.defaults)
                self.updateSegmentAccessibility()
                self.onTabSelected?(tab)
            }
        }, for: .valueChanged)

        addSubview(segmentedControl)
        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            segmentedControl.trailingAnchor.constraint(equalTo: trailingAnchor),
            segmentedControl.topAnchor.constraint(equalTo: topAnchor),
            segmentedControl.bottomAnchor.constraint(equalTo: bottomAnchor),
            segmentedControl.heightAnchor.constraint(equalToConstant: 40)
        ])
        updateSegmentAccessibility()
    }

    private func updateSegmentAccessibility() {
        let labels = LibraryTab.allCases.map(\.title)
        let identifiers = LibraryTab.allCases.map { "LibraryTab.\($0.title)" }
        SegmentedAccessibility.update(segmentedControl, labels: labels, identifiers: identifiers)
    }
}
