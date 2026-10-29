//
//  TabGroupsSheetController.swift
//  OuterView
//

import UIKit

/// Snapshot of the tab-group state the sheet renders. The owner rebuilds it
/// on demand (`stateProvider`); the sheet never reaches into the overview's
/// internals, it only emits `TabGroupsSheetController.Action` values.
struct TabGroupsSheetState: Equatable, Sendable {
    let isPrivate: Bool
    let selectedGroupID: UUID?
    let standardCount: Int
    let privateCount: Int
    let groups: [GroupCapsuleItem]
}

/// Value-type cell descriptor driving both the sheet's table and the unit
/// tests, so row derivation stays testable without a runtime.
@MainActor
final class TabGroupsSheetRowCell: UITableViewCell {
    static let reuseIdentifier = "TabGroupsSheetRowCell"

    override init(style _: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        // Every row renders title + optional right-aligned count, so the
        // class fixes the style in one place regardless of registration.
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Standalone sheet listing All (Standard), Private, existing groups with
/// counts and active checkmarks, and both create rows. Selecting a mode or
/// group dismisses the sheet; rename/delete stay open and re-render from the
/// latest `stateProvider` snapshot.
@MainActor
final class TabGroupsSheetController: UIViewController {
    /// Selections and mutations the owner must apply. The owner resolves the
    /// member list: `withAllStandardTabs: false` creates an empty group,
    /// `true` assigns the current standard tabs after creation.
    enum Action {
        case selectStandardAll
        case selectPrivate
        case selectGroup(UUID)
        case createGroup(name: String, withAllStandardTabs: Bool)
        case renameGroup(UUID, name: String)
        case deleteGroup(UUID)
    }

    /// One table row: All / Private on top, existing groups in the middle,
    /// both create rows at the bottom.
    enum Row: Equatable {
        case allSelected(active: Bool)
        case privateRow(active: Bool)
        case group(UUID, String, Int, active: Bool)
        case createEmpty
        case createWithTabs(count: Int)
    }

    nonisolated static let headerTitle = "Tab Groups"
    nonisolated static let headerHeight: CGFloat = 52
    nonisolated static let closeButtonDiameter: CGFloat = 36

    var onAction: ((Action) -> Void)?

    private let stateProvider: () -> TabGroupsSheetState
    private var currentState = TabGroupsSheetState(
        isPrivate: false,
        selectedGroupID: nil,
        standardCount: 0,
        privateCount: 0,
        groups: []
    )
    private var currentRows: [Row] = []

    private let headerBar = UIView()
    private let headerTitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(stateProvider: @escaping () -> TabGroupsSheetState) {
        self.stateProvider = stateProvider
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHierarchy()
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    // MARK: - Row derivation

    /// Pure mapping from state to rows. All/Private always lead; groups
    /// follow in the order the owner supplied; `createWithTabs` is hidden
    /// when there are no standard tabs to bulk-group.
    nonisolated static func rows(for state: TabGroupsSheetState) -> [Row] {
        var rows: [Row] = [
            .allSelected(active: !state.isPrivate && state.selectedGroupID == nil),
            .privateRow(active: state.isPrivate)
        ]
        for item in state.groups {
            // Nil ids project the synthetic All capsule, which the sheet
            // already renders natively as `allSelected`.
            guard let id = item.id else { continue }
            rows.append(.group(id, item.title, item.count, active: id == state.selectedGroupID))
        }
        rows.append(.createEmpty)
        if state.standardCount > 0 {
            rows.append(.createWithTabs(count: state.standardCount))
        }
        return rows
    }

    private func reload() {
        currentState = stateProvider()
        currentRows = Self.rows(for: currentState)
        tableView.reloadData()
    }

    // MARK: - Row presentation

    private func title(for row: Row) -> String {
        switch row {
        case .allSelected:
            return "All (Standard)"
        case .privateRow:
            return "Private"
        case let .group(_, name, _, _):
            return name
        case .createEmpty:
            return "New Empty Tab Group"
        case .createWithTabs:
            let ending = TabOverviewViewController.tabsCapsuleCountTitle(count: currentState.standardCount)
            return "New Tab Group with \(ending)"
        }
    }

    private func detail(for row: Row) -> String? {
        switch row {
        case .allSelected:
            TabOverviewViewController.tabsCapsuleCountTitle(count: currentState.standardCount)
        case let .group(_, _, count, _):
            TabOverviewViewController.tabsCapsuleCountTitle(count: count)
        case .privateRow, .createEmpty, .createWithTabs:
            nil
        }
    }

    private nonisolated static func systemImageName(for row: Row) -> String {
        switch row {
        case .allSelected: "iphone"
        case .privateRow: "hand.raised"
        case .group: "folder"
        case .createEmpty, .createWithTabs: "folder.badge.plus"
        }
    }

    private nonisolated static func isActive(_ row: Row) -> Bool {
        switch row {
        case let .allSelected(active), let .privateRow(active):
            active
        case let .group(_, _, _, active):
            active
        case .createEmpty, .createWithTabs:
            false
        }
    }

    // MARK: - Forwarding

    /// Select-style actions change the visible tab set, so the sheet closes
    /// after the owner applies them.
    private func forwardAndDismiss(_ action: Action) {
        onAction?(action)
        reload()
        dismissSheet()
    }

    /// Rename/delete keep the sheet open; re-reading the provider is what
    /// re-renders the touched row.
    private func forwardKeepingSheetOpen(_ action: Action) {
        onAction?(action)
        reload()
    }

    private func dismissSheet() {
        dismiss(animated: true)
    }

    private func handleCloseTapped() {
        dismissSheet()
    }

    // MARK: - Prompts

    private func promptCreateGroup(withAllStandardTabs: Bool) {
        let alert = UIAlertController(title: "New Group", message: "Enter a name for this group.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Group Name"
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let raw = alert?.textFields?.first?.text,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            self.forwardAndDismiss(.createGroup(name: name, withAllStandardTabs: withAllStandardTabs))
        })
        present(alert, animated: true)
    }

    private func promptRenameGroup(id: UUID, name: String) {
        let alert = UIAlertController(title: "Rename Group", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = name
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let raw = alert?.textFields?.first?.text,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            self.forwardKeepingSheetOpen(.renameGroup(id, name: name))
        })
        present(alert, animated: true)
    }

    private func confirmDeleteGroup(id: UUID, name: String) {
        let alert = UIAlertController(
            title: "Delete Group?",
            message: "Tabs in “\(name)” stay open and move to All.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.forwardKeepingSheetOpen(.deleteGroup(id))
        })
        present(alert, animated: true)
    }

    // MARK: - Layout

    private func setupHierarchy() {
        view.backgroundColor = .systemBackground

        headerBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerBar)

        headerTitleLabel.text = Self.headerTitle
        headerTitleLabel.font = .preferredFont(forTextStyle: .headline)
        headerTitleLabel.adjustsFontForContentSizeCategory = true
        headerTitleLabel.textAlignment = .center
        headerTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerTitleLabel)

        // Mirrors the prominent rail check: solid blue circle, white glyph.
        closeButton.accessibilityIdentifier = "TabGroupsSheet.CloseButton"
        closeButton.accessibilityLabel = "Done"
        let checkGlyph = UIImage(
            systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        )
        closeButton.setImage(checkGlyph, for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = .systemBlue
        closeButton.layer.cornerRadius = Self.closeButtonDiameter / 2
        closeButton.layer.masksToBounds = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(
            UIAction { [weak self] _ in self?.handleCloseTapped() },
            for: .touchUpInside
        )
        headerBar.addSubview(closeButton)

        tableView.accessibilityIdentifier = "TabGroupsSheet.Table"
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(
            TabGroupsSheetRowCell.self,
            forCellReuseIdentifier: TabGroupsSheetRowCell.reuseIdentifier
        )
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            headerTitleLabel.centerXAnchor.constraint(equalTo: headerBar.centerXAnchor),
            headerTitleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            headerTitleLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: headerBar.leadingAnchor,
                constant: Self.closeButtonDiameter + 20
            ),

            closeButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: Self.closeButtonDiameter),
            closeButton.heightAnchor.constraint(equalToConstant: Self.closeButtonDiameter),

            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension TabGroupsSheetController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in _: UITableView) -> Int {
        1
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        currentRows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: TabGroupsSheetRowCell.reuseIdentifier,
            for: indexPath
        ) as? TabGroupsSheetRowCell
        else {
            return UITableViewCell()
        }
        let row = currentRows[indexPath.row]
        cell.imageView?.image = UIImage(systemName: Self.systemImageName(for: row))
        cell.textLabel?.text = title(for: row)
        cell.detailTextLabel?.text = detail(for: row)
        cell.accessoryType = Self.isActive(row) ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch currentRows[indexPath.row] {
        case .allSelected:
            forwardAndDismiss(.selectStandardAll)
        case .privateRow:
            forwardAndDismiss(.selectPrivate)
        case let .group(id, _, _, _):
            forwardAndDismiss(.selectGroup(id))
        case .createEmpty:
            promptCreateGroup(withAllStandardTabs: false)
        case .createWithTabs:
            promptCreateGroup(withAllStandardTabs: true)
        }
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        // Group rows only: Rename/Delete mutate a persisted group, so they
        // never surface on the mode or create rows.
        guard case let .group(id, name, _, _) = currentRows[indexPath.row] else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu() }
            return UIMenu(children: [
                UIAction(title: "Rename…") { _ in self.promptRenameGroup(id: id, name: name) },
                UIAction(title: "Delete", attributes: .destructive) { _ in self.confirmDeleteGroup(id: id, name: name) }
            ])
        }
    }
}
