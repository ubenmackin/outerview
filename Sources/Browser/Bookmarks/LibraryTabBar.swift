//
//  LibraryTabBar.swift
//  OuterView
//

import UIKit

enum LibraryTab: Int, CaseIterable, Sendable {
    case favorites = 0
    case bookmarks = 1
    case history = 2

    var title: String {
        switch self {
        case .favorites: "Favorites"
        case .bookmarks: "Bookmarks"
        case .history: "History"
        }
    }

    var systemImageName: String {
        switch self {
        case .favorites: "star"
        case .bookmarks: "book"
        case .history: "clock"
        }
    }
}

/// Top tab bar for the Bookmarks & History library overlay, letting users switch
/// between Favorites, Bookmarks, and History.
@MainActor
final class LibraryTabBar: UIView {
    var onTabSelected: ((LibraryTab) -> Void)?

    private(set) var selectedTab: LibraryTab = .favorites

    private let segmentedControl: UISegmentedControl

    init() {
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
        let segments = segmentedControl.subviews.filter {
            String(describing: type(of: $0)).contains("Segment")
        }.sorted { $0.frame.minX < $1.frame.minX }

        for (index, tab) in LibraryTab.allCases.enumerated() where index < segments.count {
            segments[index].accessibilityLabel = tab.title
            segments[index].accessibilityIdentifier = "LibraryTab.\(tab.title)"
        }
    }
}
