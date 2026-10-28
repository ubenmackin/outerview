//
//  TabOverviewViewController.swift
//  OuterView
//

import UIKit

/// Browsing mode filter for the tab overview. Raw values match the
/// segmented control indices so mapping stays total in both directions.
enum TabOverviewMode: Int, Sendable, CaseIterable {
    case standard = 0
    case privateMode = 1

    var isPrivate: Bool {
        self == .privateMode
    }

    nonisolated static func mode(forSegmentIndex index: Int) -> TabOverviewMode {
        TabOverviewMode(rawValue: index) ?? .standard
    }

    nonisolated static func segmentIndex(for mode: TabOverviewMode) -> Int {
        mode.rawValue
    }

    nonisolated func segmentTitle(count: Int) -> String {
        let base = self == .privateMode ? "Private" : "Standard"
        return "\(base) · \(count)"
    }
}

/// Lightweight tab description for the grid. The owner maps this to and
/// from `TabRecord`; the overview never touches persistence or the pool.
struct TabOverviewItem: Identifiable, Sendable, Equatable {
    let id: UUID
    var title: String?
    var host: String?
    var url: URL?
    var isPrivate: Bool

    init(id: UUID = UUID(), title: String?, host: String?, url: URL?, isPrivate: Bool) {
        self.id = id
        self.title = title
        self.host = host
        self.url = url
        self.isPrivate = isPrivate
    }
}

/// Owner hooks. When the last card closes the overview inserts a fresh
/// empty item and reports it as `replacementIfEmpty`, so the owner
/// materializes that exact id instead of inventing a second tab.
@MainActor
protocol TabOverviewViewControllerDelegate: AnyObject {
    func tabOverview(_ overview: TabOverviewViewController, didSelectTab id: UUID)
    func tabOverview(_ overview: TabOverviewViewController, didCloseTab id: UUID, replacementIfEmpty replacement: TabOverviewItem?)
    func tabOverviewDidRequestNewTab(_ overview: TabOverviewViewController, in mode: TabOverviewMode)
    func tabOverview(_ overview: TabOverviewViewController, didChangeMode mode: TabOverviewMode)
    func tabOverviewDidRequestCloseAll(_ overview: TabOverviewViewController, in mode: TabOverviewMode)
    func tabOverviewDidFinish(_ overview: TabOverviewViewController)
}

extension TabOverviewViewControllerDelegate {
    func tabOverview(_: TabOverviewViewController, didSelectTab _: UUID) {}
    func tabOverview(_: TabOverviewViewController, didCloseTab _: UUID, replacementIfEmpty _: TabOverviewItem?) {}
    func tabOverviewDidRequestNewTab(_: TabOverviewViewController, in _: TabOverviewMode) {}
    func tabOverview(_: TabOverviewViewController, didChangeMode _: TabOverviewMode) {}
    func tabOverviewDidRequestCloseAll(_: TabOverviewViewController, in _: TabOverviewMode) {}
    func tabOverviewDidFinish(_: TabOverviewViewController) {}
}

/// Full-screen replacement for the content layer while open. The grid
/// covers the web content so page input is unreachable; closing the
/// overview removes the cover and restores browsing chrome via the owner.
@MainActor
final class TabOverviewViewController: UIViewController {
    // MARK: - Pure helpers

    nonisolated static let cellSpacing: CGFloat = 12
    nonisolated static let lineSpacing: CGFloat = 16
    nonisolated static let horizontalInset: CGFloat = 16
    nonisolated static let stripHeight: CGFloat = 52

    /// Grid density: two columns minimum, one more per 180 pt of width.
    nonisolated static func columnCount(forWidth width: CGFloat) -> Int {
        max(2, Int(floor(width / 180)))
    }

    /// Live filter predicate: empty query matches everything, otherwise the
    /// query must appear in the title or host, case-insensitively.
    nonisolated static func matchesFilter(title: String?, host: String?, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let needle = trimmed.lowercased()
        if let title, title.lowercased().contains(needle) {
            return true
        }
        if let host, host.lowercased().contains(needle) {
            return true
        }
        return false
    }

    nonisolated static func tabs(_ tabs: [TabOverviewItem], in mode: TabOverviewMode) -> [TabOverviewItem] {
        tabs.filter { $0.isPrivate == mode.isPrivate }
    }

    nonisolated static func counts(_ tabs: [TabOverviewItem]) -> (standard: Int, privateCount: Int) {
        var standard = 0
        var privateCount = 0
        for tab in tabs {
            if tab.isPrivate {
                privateCount += 1
            } else {
                standard += 1
            }
        }
        return (standard, privateCount)
    }

    nonisolated static func visibleTabs(_ tabs: [TabOverviewItem], mode: TabOverviewMode, query: String) -> [TabOverviewItem] {
        Self.tabs(tabs, in: mode).filter {
            matchesFilter(title: $0.title, host: $0.host, query: query)
        }
    }

    /// Selection bookkeeping after a close: a non-selected close keeps the
    /// selection; closing the selection falls back to the newest remaining
    /// tab, or nil when nothing remains (caller inserts a fresh empty tab).
    nonisolated static func selectionAfterClosing(
        closedID: UUID,
        remainingTabs: [TabOverviewItem],
        selectedID: UUID?
    ) -> UUID? {
        guard selectedID == closedID else { return selectedID }
        return remainingTabs.last?.id
    }

    nonisolated static func fallbackTab(mode: TabOverviewMode) -> TabOverviewItem {
        TabOverviewItem(title: nil, host: nil, url: nil, isPrivate: mode.isPrivate)
    }

    // MARK: - State

    weak var delegate: TabOverviewViewControllerDelegate?

    /// Snapshot fetcher supplied by the owner (usually
    /// `WebPageController.takeSnapshot`). Called once per tab on open for
    /// tabs without a cached preview.
    var previewProvider: ((UUID, @escaping @MainActor (UIImage?) -> Void) -> Void)?

    private(set) var mode: TabOverviewMode = .standard
    private var allTabs: [TabOverviewItem] = []
    private var selectedID: UUID?
    private var previews: [UUID: UIImage] = [:]
    private var filterQuery = ""
    private var isFilterVisible = false

    private var visibleItems: [TabOverviewItem] {
        Self.visibleTabs(allTabs, mode: mode, query: filterQuery)
    }

    // MARK: - Views

    private let collectionView: UICollectionView
    private let flowLayout = UICollectionViewFlowLayout()
    private let filterRow = UIView()
    private let filterField = UITextField()
    private var filterHeightConstraint: NSLayoutConstraint!
    private let segmentCapsule = UIVisualEffectView(effect: GlassEffect.make())
    private let segmentedControl = UISegmentedControl(items: ["Standard", "Private"])
    private let emptyLabel = UILabel()

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHierarchy()
        updateAppearance()
        updateSegmentTitles()
        updateItemSize()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.endEditing(true)
        requestPreviews()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        view.endEditing(true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        segmentCapsule.layer.cornerRadius = segmentCapsule.bounds.height / 2
        segmentCapsule.clipsToBounds = true
        updateItemSize()
    }

    // MARK: - Configuration

    func configure(tabs: [TabOverviewItem], selectedID: UUID?, mode: TabOverviewMode) {
        adoptItems(tabs)
        self.selectedID = selectedID
        applyMode(mode, notify: false)
        requestPreviews()
    }

    func setItems(_ tabs: [TabOverviewItem], selectedID: UUID?) {
        adoptItems(tabs)
        self.selectedID = selectedID
        updateSegmentTitles()
        collectionView.reloadData()
        updateEmptyState()
    }

    func setFilterVisible(_ visible: Bool) {
        isFilterVisible = visible
        filterRow.isHidden = !visible
        filterHeightConstraint.constant = visible ? 44 : 0
        if !visible {
            filterQuery = ""
            filterField.text = ""
        } else {
            filterField.becomeFirstResponder()
        }
        collectionView.reloadData()
        updateEmptyState()
        view.setNeedsLayout()
    }

    /// Exact overview rail composition: search + page menu up top, new tab
    /// + done at the bottom. The owner forwards its `SideRailView` here so
    /// browsing and overview rails can never drift apart.
    func applyRailItems(to railView: SideRailView) {
        railView.setItems(
            prefix: [
                .search { [weak self] in
                    guard let self else { return }
                    self.setFilterVisible(!self.isFilterVisible)
                },
                .pageMenu { [weak self] in self?.showCloseAllSheet() }
            ],
            suffix: [
                .newTab { [weak self] in
                    guard let self else { return }
                    self.delegate?.tabOverviewDidRequestNewTab(self, in: self.mode)
                },
                .done { [weak self] in
                    guard let self else { return }
                    self.delegate?.tabOverviewDidFinish(self)
                }
            ]
        )
    }

    // MARK: - Private

    private func setupHierarchy() {
        view.backgroundColor = .systemBackground

        filterRow.isHidden = true
        filterRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filterRow)

        filterField.placeholder = "Search Tabs"
        filterField.accessibilityLabel = "Search open tabs"
        filterField.adjustsFontForContentSizeCategory = true
        filterField.borderStyle = .roundedRect
        filterField.clearButtonMode = .whileEditing
        filterField.autocapitalizationType = .none
        filterField.autocorrectionType = .no
        filterField.translatesAutoresizingMaskIntoConstraints = false
        filterField.accessibilityIdentifier = "TabOverview.FilterField"
        filterField.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                self.filterQuery = self.filterField.text ?? ""
                self.collectionView.reloadData()
                self.updateEmptyState()
            },
            for: .editingChanged
        )
        filterRow.addSubview(filterField)

        flowLayout.scrollDirection = .vertical
        flowLayout.minimumInteritemSpacing = Self.cellSpacing
        flowLayout.minimumLineSpacing = Self.lineSpacing
        flowLayout.sectionInset = UIEdgeInsets(
            top: 12, left: Self.horizontalInset, bottom: 76, right: Self.horizontalInset
        )

        collectionView.backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.accessibilityIdentifier = "TabOverview.Grid"
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(TabCardCell.self, forCellWithReuseIdentifier: TabCardCell.reuseIdentifier)
        view.addSubview(collectionView)

        emptyLabel.text = "No matching tabs"
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        segmentCapsule.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentCapsule)
        segmentedControl.selectedSegmentIndex = TabOverviewMode.segmentIndex(for: mode)
        segmentedControl.accessibilityIdentifier = "TabOverview.ModeSegment"
        segmentedControl.addTarget(self, action: #selector(handleModeChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentCapsule.contentView.addSubview(segmentedControl)

        filterHeightConstraint = filterRow.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            filterRow.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            filterRow.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            filterRow.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            filterHeightConstraint,

            filterField.leadingAnchor.constraint(equalTo: filterRow.leadingAnchor),
            filterField.trailingAnchor.constraint(equalTo: filterRow.trailingAnchor),
            filterField.centerYAnchor.constraint(equalTo: filterRow.centerYAnchor),

            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: filterRow.bottomAnchor, constant: 4),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            segmentCapsule.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16
            ),
            segmentCapsule.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12
            ),
            segmentedControl.leadingAnchor.constraint(equalTo: segmentCapsule.contentView.leadingAnchor, constant: 6),
            segmentedControl.trailingAnchor.constraint(equalTo: segmentCapsule.contentView.trailingAnchor, constant: -6),
            segmentedControl.topAnchor.constraint(equalTo: segmentCapsule.contentView.topAnchor, constant: 4),
            segmentedControl.bottomAnchor.constraint(equalTo: segmentCapsule.contentView.bottomAnchor, constant: -4)
        ])
        NSLayoutConstraint.activate([
            filterField.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func adoptItems(_ tabs: [TabOverviewItem]) {
        // The grid must never render an empty backing store: closing the
        // last card inserts a fresh empty tab in the current mode so the
        // overview can never dead-end.
        if tabs.isEmpty {
            allTabs = [Self.fallbackTab(mode: mode)]
            selectedID = allTabs.first?.id
        } else {
            allTabs = tabs
            let stale = Set(previews.keys).subtracting(tabs.map(\.id))
            for id in stale {
                previews[id] = nil
            }
        }
        updateSegmentTitles()
        collectionView.reloadData()
        updateEmptyState()
    }

    private func applyMode(_ newMode: TabOverviewMode, notify: Bool) {
        mode = newMode
        segmentedControl.selectedSegmentIndex = TabOverviewMode.segmentIndex(for: newMode)
        updateAppearance()
        updateSegmentTitles()
        collectionView.reloadData()
        updateEmptyState()
        if notify {
            delegate?.tabOverview(self, didChangeMode: newMode)
        }
    }

    private func updateAppearance() {
        let isPrivate = mode.isPrivate
        view.backgroundColor = isPrivate ? .black : .systemBackground
        overrideUserInterfaceStyle = isPrivate ? .dark : .unspecified
        segmentedControl.selectedSegmentTintColor = isPrivate ? .systemPurple : nil
        collectionView.backgroundColor = .clear
        collectionView.reloadData()
    }

    private func updateSegmentTitles() {
        let totals = Self.counts(allTabs)
        segmentedControl.setTitle(
            TabOverviewMode.standard.segmentTitle(count: totals.standard), forSegmentAt: 0
        )
        segmentedControl.setTitle(
            TabOverviewMode.privateMode.segmentTitle(count: totals.privateCount), forSegmentAt: 1
        )
    }

    private func updateItemSize() {
        let collectionWidth = collectionView.bounds.width > 0 ? collectionView.bounds.width : view.bounds.width
        let available = max(0, collectionWidth - flowLayout.sectionInset.left - flowLayout.sectionInset.right)
        let columns = Self.columnCount(forWidth: max(available, 1))
        let totalSpacing = CGFloat(max(columns - 1, 0)) * flowLayout.minimumInteritemSpacing
        let itemWidth = max(0, (available - totalSpacing) / CGFloat(columns))
        guard itemWidth > 0 else { return }
        let previewHeight = itemWidth * TabCardCell.previewAspectHeightOverWidth
        let itemHeight = previewHeight + Self.stripHeight
        let size = CGSize(width: itemWidth, height: itemHeight)
        if flowLayout.itemSize != size {
            flowLayout.itemSize = size
            flowLayout.invalidateLayout()
        }
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !visibleItems.isEmpty
    }

    private func requestPreviews() {
        guard let provider = previewProvider else { return }
        for tab in allTabs where previews[tab.id] == nil {
            let id = tab.id
            provider(id) { [weak self] image in
                guard let self, self.allTabs.contains(where: { $0.id == id }) else { return }
                self.previews[id] = image
                for (index, item) in self.visibleItems.enumerated() where item.id == id {
                    self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                    return
                }
            }
        }
    }

    private func closeTab(id: UUID) {
        guard let index = allTabs.firstIndex(where: { $0.id == id }) else { return }
        allTabs.remove(at: index)
        previews[id] = nil
        if allTabs.isEmpty {
            let replacement = Self.fallbackTab(mode: mode)
            allTabs.append(replacement)
            selectedID = replacement.id
            updateSegmentTitles()
            collectionView.reloadData()
            updateEmptyState()
            delegate?.tabOverview(self, didCloseTab: id, replacementIfEmpty: replacement)
            return
        }
        selectedID = Self.selectionAfterClosing(
            closedID: id, remainingTabs: allTabs, selectedID: selectedID
        )
        updateSegmentTitles()
        collectionView.reloadData()
        updateEmptyState()
        delegate?.tabOverview(self, didCloseTab: id, replacementIfEmpty: nil)
    }

    private func showCloseAllSheet() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Close All Tabs", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.delegate?.tabOverviewDidRequestCloseAll(self, in: self.mode)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(
                x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    @objc private func handleModeChanged() {
        applyMode(TabOverviewMode.mode(forSegmentIndex: segmentedControl.selectedSegmentIndex), notify: true)
    }
}

// MARK: - UICollectionViewDataSource, UICollectionViewDelegate

extension TabOverviewViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        visibleItems.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: TabCardCell.reuseIdentifier,
            for: indexPath
        ) as? TabCardCell
        else {
            return UICollectionViewCell()
        }
        let item = visibleItems[indexPath.item]
        cell.configure(with: item, preview: previews[item.id], isSelected: item.id == selectedID)
        cell.onClose = { [weak self] in self?.closeTab(id: item.id) }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let item = visibleItems[indexPath.item]
        delegate?.tabOverview(self, didSelectTab: item.id)
    }
}
