// Bookmarks — Recent search query list with select and clear-all actions.

import UIKit

@MainActor
final class RecentSearchesView: UIView {
    var onSelectQuery: (@MainActor (String) -> Void)?
    var onDeleteQuery: (@MainActor (UUID) -> Void)?
    var onClearAll: (@MainActor () -> Void)?

    private let recentSearchStore: RecentSearchStore?
    private var entries: [RecentSearch] = []

    private let headerContainer = UIView()
    private let titleLabel = UILabel()
    private let clearAllButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    init(recentSearchStore: RecentSearchStore?) {
        self.recentSearchStore = recentSearchStore
        super.init(frame: .zero)
        setup()
        reload()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        entries = recentSearchStore?.fetchRecents() ?? []
        clearAllButton.isHidden = entries.isEmpty
        emptyLabel.isHidden = !entries.isEmpty
        tableView.reloadData()
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear

        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerContainer)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Recent Searches"
        let baseTitleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: baseTitleFont)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        headerContainer.addSubview(titleLabel)

        clearAllButton.translatesAutoresizingMaskIntoConstraints = false
        clearAllButton.setTitle("Clear All", for: .normal)
        clearAllButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        clearAllButton.tintColor = .secondaryLabel
        clearAllButton.accessibilityLabel = "Clear All Recent Searches"
        clearAllButton.addAction(UIAction { [weak self] _ in
            self?.onClearAll?()
        }, for: .touchUpInside)
        headerContainer.addSubview(clearAllButton)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = .separator.withAlphaComponent(0.4)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(RecentSearchCell.self, forCellReuseIdentifier: RecentSearchCell.reuseIdentifier)
        tableView.rowHeight = 52
        tableView.keyboardDismissMode = .onDrag
        addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No Recent Searches"
        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            headerContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            headerContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            headerContainer.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            headerContainer.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

            clearAllButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            clearAllButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 8),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 40)
        ])
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension RecentSearchesView: UITableViewDataSource, UITableViewDelegate {
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: RecentSearchCell.reuseIdentifier,
            for: indexPath
        ) as? RecentSearchCell else {
            return UITableViewCell()
        }
        let entry = entries[indexPath.row]
        cell.configure(
            with: entry,
            onDelete: { [weak self] in self?.onDeleteQuery?(entry.id) },
            onSelect: { [weak self] in self?.onSelectQuery?(entry.query) }
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = entries[indexPath.row]
        onSelectQuery?(entry.query)
    }
}

// MARK: - RecentSearchCell

private final class RecentSearchCell: UITableViewCell {
    static let reuseIdentifier = "RecentSearchCell"

    private let iconBadge = UIView()
    private let iconImageView = UIImageView()
    private let queryLabel = UILabel()
    private let selectButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private var onDelete: (@MainActor () -> Void)?
    private var onSelect: (@MainActor () -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with entry: RecentSearch, onDelete: @MainActor @escaping () -> Void, onSelect: @MainActor @escaping () -> Void) {
        self.onDelete = onDelete
        self.onSelect = onSelect
        queryLabel.text = entry.query
    }

    private func setup() {
        backgroundColor = .clear
        selectionStyle = .default

        iconBadge.translatesAutoresizingMaskIntoConstraints = false
        iconBadge.backgroundColor = .secondarySystemFill
        iconBadge.layer.cornerRadius = 8
        iconBadge.clipsToBounds = true
        contentView.addSubview(iconBadge)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconImageView.image = UIImage(systemName: "magnifyingglass", withConfiguration: config)
        iconImageView.tintColor = .secondaryLabel
        iconImageView.contentMode = .center
        iconBadge.addSubview(iconImageView)

        queryLabel.translatesAutoresizingMaskIntoConstraints = false
        queryLabel.font = .preferredFont(forTextStyle: .body)
        queryLabel.textColor = .label
        contentView.addSubview(queryLabel)

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        let deleteConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        deleteButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: deleteConfig), for: .normal)
        deleteButton.tintColor = .tertiaryLabel
        deleteButton.accessibilityLabel = "Remove from Recent Searches"
        deleteButton.addAction(UIAction { [weak self] _ in
            self?.onDelete?()
        }, for: .touchUpInside)
        contentView.addSubview(deleteButton)

        selectButton.translatesAutoresizingMaskIntoConstraints = false
        let selectConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        selectButton.setImage(UIImage(systemName: "chevron.right", withConfiguration: selectConfig), for: .normal)
        selectButton.tintColor = .tertiaryLabel
        selectButton.accessibilityLabel = "Select query"
        selectButton.addAction(UIAction { [weak self] _ in
            self?.onSelect?()
        }, for: .touchUpInside)
        contentView.addSubview(selectButton)

        NSLayoutConstraint.activate([
            iconBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconBadge.widthAnchor.constraint(equalToConstant: 28),
            iconBadge.heightAnchor.constraint(equalToConstant: 28),

            iconImageView.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),

            queryLabel.leadingAnchor.constraint(equalTo: iconBadge.trailingAnchor, constant: 12),
            queryLabel.trailingAnchor.constraint(lessThanOrEqualTo: selectButton.leadingAnchor, constant: -8),
            queryLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            selectButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -4),
            selectButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectButton.widthAnchor.constraint(equalToConstant: 32),
            selectButton.heightAnchor.constraint(equalToConstant: 32),

            deleteButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            deleteButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 32),
            deleteButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
}
