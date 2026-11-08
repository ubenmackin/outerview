// Chrome — Thumb-reachable vertical liquid glass tab bar for portrait tablet/foldable mode.

import UIKit

@MainActor
final class VerticalTabBarView: UIView {
    nonisolated static let barWidth: CGFloat = 52
    nonisolated static let itemSize: CGFloat = 40
    nonisolated static let iconSize: CGFloat = 20
    nonisolated static let spacing: CGFloat = 8
    nonisolated static let cornerRadius: CGFloat = 26
    /// Matches the 8 pt top plus 8 pt bottom scroll insets so the
    /// intrinsic height tracks the laid-out content height.
    nonisolated static let verticalPadding: CGFloat = 16
    /// Caps the floating bar so long tab lists scroll instead of
    /// stretching past thumb reach.
    nonisolated static let maxHeight: CGFloat = 480

    var onSelectTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    var onNewTab: (() -> Void)?

    private(set) var displayedTabs: [TabOverviewItem] = []
    private(set) var displayedSelectedID: UUID?

    private let blurView = UIVisualEffectView(effect: GlassEffect.makeBlur())
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let newTabButton = UIButton(type: .system)
    private(set) var itemViews: [UUID: VerticalTabItemView] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let contentHeight = CGFloat(displayedTabs.count + 1) * Self.itemSize
            + CGFloat(displayedTabs.count) * Self.spacing + Self.verticalPadding
        return CGSize(width: Self.barWidth, height: min(contentHeight, Self.maxHeight))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateBorder()
    }

    func render(tabs: [TabOverviewItem], selectedID: UUID?) {
        displayedTabs = tabs
        displayedSelectedID = selectedID

        for view in stackView.arrangedSubviews {
            (view as? VerticalTabItemView)?.cancelFaviconLoad()
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        itemViews.removeAll()

        for tab in tabs {
            let isSelected = (tab.id == selectedID)
            let itemView = VerticalTabItemView(item: tab, isSelected: isSelected)
            itemView.onTap = { [weak self] in
                self?.onSelectTab?(tab.id)
            }
            itemView.onClose = { [weak self] in
                self?.onCloseTab?(tab.id)
            }
            itemViews[tab.id] = itemView
            stackView.addArrangedSubview(itemView)
        }

        stackView.addArrangedSubview(newTabButton)
        invalidateIntrinsicContentSize()
    }

    private func updateBorder() {
        let scale = max(1, traitCollection.displayScale)
        layer.borderWidth = 1.0 / scale
        layer.borderColor = UIColor.separator.withAlphaComponent(0.35).resolvedColor(with: traitCollection).cgColor
    }

    private func setup() {
        layer.cornerRadius = Self.cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true
        backgroundColor = .clear

        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        addSubview(scrollView)

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = Self.spacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        newTabButton.setImage(
            UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)),
            for: .normal
        )
        newTabButton.tintColor = .label
        newTabButton.accessibilityLabel = "New Tab"
        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.addAction(UIAction { [weak self] _ in self?.onNewTab?() }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            newTabButton.widthAnchor.constraint(equalToConstant: Self.itemSize),
            newTabButton.heightAnchor.constraint(equalToConstant: Self.itemSize)
        ])
    }
}

@MainActor
final class VerticalTabItemView: UIView, UIContextMenuInteractionDelegate {
    var onTap: (() -> Void)?
    var onClose: (() -> Void)?

    private let item: TabOverviewItem
    private let isTabSelected: Bool
    private let faviconView = UIImageView()
    private var faviconTask: Task<Void, Never>?

    init(item: TabOverviewItem, isSelected: Bool) {
        self.item = item
        self.isTabSelected = isSelected
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Explicit favicon cancellation owns the task lifecycle; render calls it
    /// before dropping the view so no MainActor-isolated access runs in deinit.
    func cancelFaviconLoad() {
        faviconTask?.cancel()
        faviconTask = nil
    }

    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        // Detached without a render pass (owner dealloc) still drops the
        // in-flight bind so it never touches a deallocated image view.
        if newSuperview == nil {
            cancelFaviconLoad()
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true

        if isTabSelected {
            backgroundColor = .secondarySystemFill
            let scale = max(1, traitCollection.displayScale)
            layer.borderWidth = 1.0 / scale
            layer.borderColor = UIColor.separator.withAlphaComponent(0.55).resolvedColor(with: traitCollection).cgColor
        } else {
            backgroundColor = .clear
            layer.borderWidth = 0
            layer.borderColor = nil
        }

        faviconView.contentMode = .scaleAspectFit
        faviconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(faviconView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: VerticalTabBarView.itemSize),
            heightAnchor.constraint(equalToConstant: VerticalTabBarView.itemSize),

            faviconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            faviconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            faviconView.widthAnchor.constraint(equalToConstant: VerticalTabBarView.iconSize),
            faviconView.heightAnchor.constraint(equalToConstant: VerticalTabBarView.iconSize)
        ])

        if let url = item.url {
            let itemID = item.id
            faviconTask = FaviconService.shared.bind(
                url: url,
                into: faviconView,
                identity: itemID,
                currentIdentity: { itemID },
                size: VerticalTabBarView.iconSize,
                isPrivate: item.isPrivate
            )
        } else {
            let globeConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            faviconView.image = UIImage(systemName: "globe", withConfiguration: globeConfig)
            faviconView.tintColor = .secondaryLabel
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true

        addInteraction(UIContextMenuInteraction(delegate: self))

        isAccessibilityElement = true
        accessibilityTraits = isTabSelected ? [.button, .selected] : [.button]
        if let title = item.title, let host = item.host, !host.isEmpty, !title.contains(host) {
            accessibilityLabel = "\(title), \(host)"
        } else {
            accessibilityLabel = item.title ?? item.host ?? "New Tab"
        }
        accessibilityHint = "Double tap to switch to tab"
    }

    @objc func handleTap() {
        onTap?()
    }

    override func accessibilityActivate() -> Bool {
        onTap?()
        return true
    }

    func contextMenuInteraction(
        _: UIContextMenuInteraction,
        configurationForMenuAtLocation _: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu() }
            var actions: [UIMenuElement] = []

            if let url = self.item.url {
                let copyAction = UIAction(
                    title: "Copy Link",
                    image: UIImage(systemName: "doc.on.doc")
                ) { _ in
                    UIPasteboard.general.url = url
                }
                actions.append(copyAction)
            }

            let closeAction = UIAction(
                title: "Close Tab",
                image: UIImage(systemName: "xmark"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.onClose?()
            }
            actions.append(closeAction)

            return UIMenu(title: self.item.title ?? "", children: actions)
        }
    }
}
