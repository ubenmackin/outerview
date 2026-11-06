// TabOverview — Visual grid plus system toolbar chrome.

import os
import UIKit

/// UserDefaults keys libraryTab, overviewMode, and overviewGroup.
/// Private mode is never written; unparseable values fall back to defaults.
/// Unknown group id restores as nil.
enum TabOverviewMode: Int, Sendable, CaseIterable {
    case standard = 0
    case privateMode = 1

    var isPrivate: Bool {
        self == .privateMode
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
    var groupId: UUID?
    var groupName: String?

    init(
        id: UUID = UUID(),
        title: String?,
        host: String?,
        url: URL?,
        isPrivate: Bool,
        groupId: UUID? = nil,
        groupName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.host = host
        self.url = url
        self.isPrivate = isPrivate
        self.groupId = groupId
        self.groupName = groupName
    }
}

struct GroupCapsuleItem: Sendable, Equatable {
    let id: UUID?
    let title: String
    let count: Int
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
    func tabOverview(_ overview: TabOverviewViewController, didCreateGroup name: String, withTabIDs: [UUID])
    func tabOverview(_ overview: TabOverviewViewController, didAssignTab id: UUID, toGroup groupId: UUID?)
    func tabOverview(_ overview: TabOverviewViewController, didRenameGroup id: UUID, toName name: String)
    func tabOverview(_ overview: TabOverviewViewController, didDeleteGroup id: UUID)
    func tabOverview(_ overview: TabOverviewViewController, didReorderTabs orderedIDs: [UUID])
}

extension TabOverviewViewControllerDelegate {
    func tabOverview(_: TabOverviewViewController, didSelectTab _: UUID) {}
    func tabOverview(_: TabOverviewViewController, didCloseTab _: UUID, replacementIfEmpty _: TabOverviewItem?) {}
    func tabOverviewDidRequestNewTab(_: TabOverviewViewController, in _: TabOverviewMode) {}
    func tabOverview(_: TabOverviewViewController, didChangeMode _: TabOverviewMode) {}
    func tabOverviewDidRequestCloseAll(_: TabOverviewViewController, in _: TabOverviewMode) {}
    func tabOverviewDidFinish(_: TabOverviewViewController) {}
    func tabOverview(_: TabOverviewViewController, didCreateGroup _: String, withTabIDs _: [UUID]) {}
    func tabOverview(_: TabOverviewViewController, didAssignTab _: UUID, toGroup _: UUID?) {}
    func tabOverview(_: TabOverviewViewController, didRenameGroup _: UUID, toName _: String) {}
    func tabOverview(_: TabOverviewViewController, didDeleteGroup _: UUID) {}
    func tabOverview(_: TabOverviewViewController, didReorderTabs _: [UUID]) {}
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

    /// Grid density: two columns minimum, one more per 180 pt of width (260 pt on regular).
    nonisolated static func columnCount(forWidth width: CGFloat, isRegular: Bool = false) -> Int {
        if isRegular {
            return max(2, Int(floor(width / 260)))
        }
        return max(2, Int(floor(width / 180)))
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

    nonisolated static func tabsCapsuleCountTitle(count: Int) -> String {
        count == 1 ? "1 Tab" : "\(count) Tabs"
    }

    nonisolated static func otherModeTitle(for mode: TabOverviewMode) -> String {
        mode == .standard ? "Private" : "Standard"
    }

    nonisolated static func visibleTabs(
        _ tabs: [TabOverviewItem],
        mode: TabOverviewMode,
        query: String,
        groupId: UUID? = nil
    ) -> [TabOverviewItem] {
        Self.tabs(tabs, in: mode).filter {
            (groupId == nil || $0.groupId == groupId)
                && matchesFilter(title: $0.title, host: $0.host, query: query)
        }
    }

    static func groupCapsuleItems(
        groups: [TabGroup],
        tabs: [TabOverviewItem]
    ) -> [GroupCapsuleItem] {
        var items: [GroupCapsuleItem] = [GroupCapsuleItem(id: nil, title: "All", count: tabs.count)]
        var counts: [UUID: Int] = [:]
        for tab in tabs {
            if let groupId = tab.groupId {
                counts[groupId, default: 0] += 1
            }
        }
        for group in groups {
            let count = counts[group.id, default: 0]
            guard count > 0 else { continue }
            items.append(GroupCapsuleItem(id: group.id, title: group.name, count: count))
        }
        return items
    }

    /// A nil group selects everything (the All capsule); otherwise only
    /// members of that group survive.
    nonisolated static func members(tabs: [TabOverviewItem], of groupId: UUID?) -> [TabOverviewItem] {
        guard let groupId else { return tabs }
        return tabs.filter { $0.groupId == groupId }
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

    /// Reorder math for drag and drop. `to` is clamped into bounds; an
    /// out-of-range `from` returns the input unchanged.
    nonisolated static func moveID(_ ids: [UUID], from: Int, to: Int) -> [UUID] {
        guard !ids.isEmpty, ids.indices.contains(from) else { return ids }
        let clampedTo = min(max(to, 0), ids.count - 1)
        guard from != clampedTo else { return ids }
        var result = ids
        let element = result.remove(at: from)
        result.insert(element, at: clampedTo)
        return result
    }

    /// Multi-item drop math in pre-drop coordinates; nil means trailing edge.
    /// Dragged IDs keep drop order as one block; unknown/duplicates ignored.
    /// Single dragged tab reuses `moveID` to stay on production path.
    nonisolated static func reorderedIDs(
        currentIDs: [UUID],
        draggedIDs: [UUID],
        destinationIndex: Int
    ) -> [UUID] {
        guard !currentIDs.isEmpty, !draggedIDs.isEmpty else { return currentIDs }
        var orderedDragged: [UUID] = []
        orderedDragged.reserveCapacity(draggedIDs.count)
        var seen = Set<UUID>()
        let currentSet = Set(currentIDs)
        for id in draggedIDs {
            guard currentSet.contains(id), !seen.contains(id) else { continue }
            seen.insert(id)
            orderedDragged.append(id)
        }
        guard !orderedDragged.isEmpty else { return currentIDs }
        if orderedDragged.count == 1, let only = orderedDragged.first,
           let from = currentIDs.firstIndex(of: only)
        {
            let clampedDestination = min(max(destinationIndex, 0), currentIDs.count - 1)
            return moveID(currentIDs, from: from, to: clampedDestination)
        }
        let clamped = min(max(destinationIndex, 0), currentIDs.count)
        var draggedBefore = 0
        for (index, id) in currentIDs.enumerated() {
            if index >= clamped {
                break
            }

            if seen.contains(id) {
                draggedBefore += 1
            }
        }
        let remaining = currentIDs.filter { !seen.contains($0) }
        let insertion = min(max(clamped - draggedBefore, 0), remaining.count)
        var result = remaining
        result.insert(contentsOf: orderedDragged, at: insertion)
        return result
    }

    /// Mode-first splice: grid-ordered mode tabs first, then untouched strip order.
    /// Pure so mixed-mode splicing tests without persistence or pool.
    /// Grid IDs missing from the strip are dropped.
    nonisolated static func spliceTabOrder(
        currentIDs: [UUID],
        privacyByID: [UUID: Bool],
        orderedIDs: [UUID],
        isPrivate: Bool
    ) -> [UUID] {
        let currentSet = Set(currentIDs)
        var reordered: [UUID] = []
        reordered.reserveCapacity(orderedIDs.count)
        var reorderedSet = Set<UUID>()
        for id in orderedIDs {
            guard currentSet.contains(id), privacyByID[id] == isPrivate,
                  !reorderedSet.contains(id)
            else { continue }
            reorderedSet.insert(id)
            reordered.append(id)
        }
        var untouched: [UUID] = []
        untouched.reserveCapacity(currentIDs.count)
        for id in currentIDs where !reorderedSet.contains(id) {
            untouched.append(id)
        }
        return reordered + untouched
    }

    /// Item-level mode-first splice sharing `spliceTabOrder` so the grid
    /// model and the persisted strip resolve to the same order.
    nonisolated static func spliceTabItems(
        current: [TabOverviewItem],
        orderedIDs: [UUID],
        isPrivate: Bool
    ) -> [TabOverviewItem] {
        var privacyByID: [UUID: Bool] = [:]
        privacyByID.reserveCapacity(current.count)
        var byID: [UUID: TabOverviewItem] = [:]
        byID.reserveCapacity(current.count)
        for item in current {
            privacyByID[item.id] = item.isPrivate
            byID[item.id] = item
        }
        let splicedIDs = spliceTabOrder(
            currentIDs: current.map(\.id),
            privacyByID: privacyByID,
            orderedIDs: orderedIDs,
            isPrivate: isPrivate
        )
        return splicedIDs.compactMap { byID[$0] }
    }

    // MARK: - State

    weak var delegate: TabOverviewViewControllerDelegate?

    /// Snapshot fetcher supplied by the owner (usually
    /// `WebPageController.takeSnapshot`). Called once per tab on open for
    /// tabs without a cached preview.
    var previewProvider: ((UUID, @escaping @MainActor (UIImage?) -> Void) -> Void)?

    var selectionDefaults: UserDefaults = .standard

    private(set) var mode: TabOverviewMode = .standard
    var allTabs: [TabOverviewItem] = []
    private(set) var allGroups: [TabGroup] = []
    private(set) var selectedGroupID: UUID?
    var selectedID: UUID?
    var previews: [UUID: UIImage] = [:]
    var filterQuery = ""
    private var isFilterVisible = false
    var isDragReordering = false
    var pendingPreviewIDs = Set<UUID>()

    var showsInlineCommands = false {
        didSet {
            guard isViewLoaded, oldValue != showsInlineCommands else { return }
            applyInlineCommandsVisibility()
        }
    }

    var isRegular = false {
        didSet {
            guard oldValue != isRegular else { return }
            externalHeaderHeight = isRegular ? TopBarView.barHeight : 0
            if isViewLoaded {
                updateItemSize()
                applyInlineCommandsVisibility()
            }
        }
    }

    var externalHeaderHeight: CGFloat = 0 {
        didSet {
            guard oldValue != externalHeaderHeight else { return }
            inlineBarTopConstraint?.constant = externalHeaderHeight + 8
            viewIfLoaded?.setNeedsLayout()
        }
    }

    var visibleItems: [TabOverviewItem] {
        Self.visibleTabs(allTabs, mode: mode, query: filterQuery, groupId: selectedGroupID)
    }

    // MARK: - Views

    let collectionView: UICollectionView
    private let flowLayout = UICollectionViewFlowLayout()
    private let filterRow = UIView()
    let filterField = UITextField()
    private var filterHeightConstraint: NSLayoutConstraint!
    private let inlineBar = UIToolbar()
    private var inlineBarHeightConstraint: NSLayoutConstraint!
    private var inlineBarTopConstraint: NSLayoutConstraint?
    let pickerBar = TabGroupPickerBar()
    private let emptyLabel = UILabel()

    var overviewToolbar: UIToolbar {
        inlineBar
    }

    var isInlineBarVisible: Bool {
        isViewLoaded && !inlineBar.isHidden
    }

    var isInlineSearchVisible: Bool {
        isInlineBarVisible && (inlineBar.items?.contains { $0.accessibilityLabel == "Search" } ?? false)
    }

    var isInlineMenuVisible: Bool {
        isInlineBarVisible && (inlineBar.items?.contains { $0.accessibilityLabel == "Overview Menu" } ?? false)
    }

    var isInlineDoneVisible: Bool {
        isInlineBarVisible && (inlineBar.items?.contains { $0.accessibilityLabel == "Done" } ?? false)
    }

    var inlineMenu: UIMenu? {
        makeInlineOverviewMenu()
    }

    func performInlineDone() {
        delegate?.tabOverviewDidFinish(self)
    }

    func refreshOverviewToolbar() {
        let items = overviewChromeItems()
        inlineBar.items = SystemToolbarMapper.makeOverviewToolbarItems(prefix: items.prefix, suffix: items.suffix)
    }

    func setToolbarItems(_ items: [UIBarButtonItem]) {
        inlineBar.items = items
    }

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
        applyInlineCommandsVisibility()
        updateAppearance()
        updatePickerBar()
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
        updateItemSize()
    }

    // MARK: - Configuration

    func configure(
        tabs: [TabOverviewItem],
        selectedID: UUID?,
        mode: TabOverviewMode,
        groups: [TabGroup] = [],
        selectedGroupID: UUID? = nil
    ) {
        adoptItems(tabs)
        self.selectedID = selectedID
        allGroups = groups
        self.selectedGroupID = selectedGroupID.flatMap { id in groups.contains(where: { $0.id == id }) ? id : nil }
        applyMode(mode, notify: false)
        updatePickerBar()
        if isViewLoaded {
            applyInlineCommandsVisibility()
        }
        requestPreviews()
    }

    func setItems(_ tabs: [TabOverviewItem], selectedID: UUID?) {
        adoptItems(tabs)
        self.selectedID = selectedID
        updatePickerBar()
        collectionView.reloadData()
        updateEmptyState()
    }

    /// Frame of the selected tab card converted to the target coordinate space,
    /// used by interactive swipe-to-overview commit animations.
    func selectedCardFrame(in targetCoordinateSpace: UICoordinateSpace) -> CGRect? {
        guard isViewLoaded, let selectedID else { return nil }
        view.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        guard let index = visibleItems.firstIndex(where: { $0.id == selectedID }) else { return nil }
        let indexPath = IndexPath(item: index, section: 0)
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
        let frameInTarget = collectionView.convert(attributes.frame, to: targetCoordinateSpace)
        guard frameInTarget.width > 0, frameInTarget.height > 0 else { return nil }
        return frameInTarget
    }

    func setGroups(_ groups: [TabGroup], selectedGroupID: UUID?) {
        allGroups = groups
        if let selectedGroupID, groups.contains(where: { $0.id == selectedGroupID }) {
            self.selectedGroupID = selectedGroupID
        } else {
            self.selectedGroupID = nil
        }
        updatePickerBar()
        collectionView.reloadData()
        updateEmptyState()
    }

    func setGroupFilter(_ groupId: UUID?) {
        if let groupId, !allGroups.contains(where: { $0.id == groupId }) {
            return
        }
        selectedGroupID = groupId
        updatePickerBar()
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

    /// Exact overview rail: search plus menu on top, new tab plus done below.
    /// Owner forwards chrome here so browsing and overview never drift.
    /// Regular mirrors prefix/suffix into top toolbar while rail hides.
    func overviewChromeItems() -> (prefix: [RailAction], suffix: [RailAction]) {
        let prefix: [RailAction] = [
            .search { [weak self] in
                guard let self else { return }
                self.setFilterVisible(!self.isFilterVisible)
            },
            .overviewMenu(menu: makeOverviewMenu(includesCloseAll: true))
        ]
        let suffix: [RailAction] = [
            .newTab { [weak self] in
                guard let self else { return }
                self.delegate?.tabOverviewDidRequestNewTab(self, in: self.mode)
            },
            .done { [weak self] in
                guard let self else { return }
                self.delegate?.tabOverviewDidFinish(self)
            }
        ]
        return (prefix, suffix)
    }

    // MARK: - Private

    private func setupHierarchy() {
        view.backgroundColor = .systemBackground
        setupInlineBarViews()
        setupFilterViews()
        setupGridViews()
        activateHierarchyConstraints()
    }

    private func setupInlineBarViews() {
        inlineBar.isHidden = true
        inlineBar.translatesAutoresizingMaskIntoConstraints = false
        // Shared glass styling stays in the mapper via its factory.
        inlineBar.isTranslucent = true
        inlineBar.backgroundColor = .clear
        let appearance = SystemToolbarMapper.toolbarAppearance()
        inlineBar.standardAppearance = appearance
        inlineBar.scrollEdgeAppearance = appearance
        inlineBar.accessibilityIdentifier = "TabOverview.Toolbar"
        view.addSubview(inlineBar)
        refreshOverviewToolbar()
    }

    private func setupFilterViews() {
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
    }

    private func setupGridViews() {
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
        collectionView.dragInteractionEnabled = true
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
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

        pickerBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pickerBar)
        pickerBar.onTap = { [weak self] in self?.showGroupsSheet() }
        pickerBar.onScrubSelect = { [weak self] in self?.applyPickerSelection($0) }
        pickerBar.onScrubEnd = { [weak self] in self?.applyPickerSelection($0) }
        updatePickerBar()
    }

    private func activateHierarchyConstraints() {
        filterHeightConstraint = filterRow.heightAnchor.constraint(equalToConstant: 0)
        inlineBarHeightConstraint = inlineBar.heightAnchor.constraint(equalToConstant: 0)
        let barTop = inlineBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: externalHeaderHeight + 8)
        inlineBarTopConstraint = barTop
        NSLayoutConstraint.activate([
            inlineBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            inlineBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            barTop,
            inlineBarHeightConstraint,

            filterRow.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            filterRow.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            filterRow.topAnchor.constraint(equalTo: inlineBar.bottomAnchor),
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

            pickerBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pickerBar.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16
            ),
            pickerBar.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16
            ),
            pickerBar.trailingAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16
            )
        ])
        let filterHeight = filterField.heightAnchor.constraint(equalToConstant: 36)
        filterHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            filterHeight
        ])
    }

    func applyInlineCommandsVisibility() {
        guard isViewLoaded else { return }
        let showsInline = showsInlineCommands
        inlineBar.isHidden = !showsInline
        inlineBarHeightConstraint.constant = showsInline ? 44 : 0
        refreshOverviewToolbar()
        filterRow.isHidden = !isFilterVisible
        filterHeightConstraint.constant = isFilterVisible ? 44 : 0
        filterField.text = filterQuery
        collectionView.reloadData()
        updateEmptyState()
        view.setNeedsLayout()
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
        updatePickerBar()
        collectionView.reloadData()
        updateEmptyState()
    }

    /// Cross-file entry for the picker extension: the extension lives in its
    /// own file so mode application stays internal here rather than private.
    func applyMode(_ newMode: TabOverviewMode, notify: Bool) {
        mode = newMode
        updateAppearance()
        updatePickerBar()
        collectionView.reloadData()
        updateEmptyState()
        if notify {
            delegate?.tabOverview(self, didChangeMode: newMode)
        }
    }

    /// Single-refresh mode + filter application for scrub ticks. `applyMode`
    /// followed by `setGroupFilter` would pay two picker rebuilds and two
    /// grid reloads per tick; this batches them into one.
    func applySelectionBatched(mode newMode: TabOverviewMode, groupID: UUID?, notify: Bool) {
        // Re-applying the current mode + filter is a no-op; skip reload and delegate.
        if mode == newMode {
            if let groupID {
                if allGroups.contains(where: { $0.id == groupID }) {
                    if selectedGroupID == groupID {
                        return
                    }
                } else {
                    return
                }
            } else if selectedGroupID == nil {
                return
            }
        }
        let modeChanged = mode != newMode
        mode = newMode
        if let groupID {
            if allGroups.contains(where: { $0.id == groupID }) {
                selectedGroupID = groupID
            }
        } else {
            selectedGroupID = nil
        }
        Self.persistOverviewSelection(mode: newMode, groupID: selectedGroupID, defaults: selectionDefaults)
        if modeChanged {
            updateAppearance()
        } else {
            collectionView.reloadData()
        }
        updatePickerBar()
        updateEmptyState()
        if notify {
            delegate?.tabOverview(self, didChangeMode: newMode)
        }
    }

    private func updateAppearance() {
        let isPrivate = mode.isPrivate
        view.backgroundColor = isPrivate ? .black : .systemBackground
        overrideUserInterfaceStyle = isPrivate ? .dark : .unspecified
        collectionView.backgroundColor = .clear
        collectionView.reloadData()
    }

    private func updateItemSize() {
        let collectionWidth = collectionView.bounds.width > 0 ? collectionView.bounds.width : view.bounds.width
        let available = max(0, collectionWidth - flowLayout.sectionInset.left - flowLayout.sectionInset.right)
        let columns = Self.columnCount(forWidth: max(available, 1), isRegular: isRegular)
        let totalSpacing = CGFloat(max(columns - 1, 0)) * flowLayout.minimumInteritemSpacing
        let itemWidth = max(0, (available - totalSpacing) / CGFloat(columns))
        guard itemWidth > 0 else { return }
        let aspect = isRegular ? TabCardCell.landscapeAspectHeightOverWidth : TabCardCell.previewAspectHeightOverWidth
        let previewHeight = itemWidth * aspect
        let itemHeight = previewHeight + Self.stripHeight
        let size = CGSize(width: itemWidth, height: itemHeight)
        if flowLayout.itemSize != size {
            flowLayout.itemSize = size
            flowLayout.invalidateLayout()
        }
    }

    func updateEmptyState() {
        emptyLabel.isHidden = !visibleItems.isEmpty
    }

    private func requestPreviews() {
        guard let provider = previewProvider else { return }
        for tab in allTabs where previews[tab.id] == nil {
            let id = tab.id
            provider(id) { [weak self] image in
                guard let self, self.allTabs.contains(where: { $0.id == id }) else { return }
                self.previews[id] = image
                if self.isDragReordering || self.collectionView.hasActiveDrag || self.collectionView.hasActiveDrop {
                    self.pendingPreviewIDs.insert(id)
                    return
                }
                for (index, item) in self.visibleItems.enumerated() where item.id == id {
                    self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                    return
                }
            }
        }
    }

    /// Mirrors the owner's mode-first splice so the grid model already
    /// matches the persisted order before the drop animation completes.
    func applyLocalReorder(orderedIDs: [UUID]) {
        allTabs = Self.spliceTabItems(
            current: allTabs,
            orderedIDs: orderedIDs,
            isPrivate: mode.isPrivate
        )
        updatePickerBar()
    }

    func closeTab(id: UUID) {
        guard let index = allTabs.firstIndex(where: { $0.id == id }) else { return }
        allTabs.remove(at: index)
        previews[id] = nil
        if allTabs.isEmpty {
            let replacement = Self.fallbackTab(mode: mode)
            allTabs.append(replacement)
            selectedID = replacement.id
            updatePickerBar()
            collectionView.reloadData()
            updateEmptyState()
            delegate?.tabOverview(self, didCloseTab: id, replacementIfEmpty: replacement)
            return
        }
        selectedID = Self.selectionAfterClosing(
            closedID: id, remainingTabs: allTabs, selectedID: selectedID
        )
        updatePickerBar()
        collectionView.reloadData()
        updateEmptyState()
        delegate?.tabOverview(self, didCloseTab: id, replacementIfEmpty: nil)
    }

    /// Confirm sheet for closing all tabs in the current mode. Internal
    /// because the picker extension presents it from the rail ellipsis menu.
    func showCloseAllSheet() {
        guard presentedViewController == nil else { return }
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
}
