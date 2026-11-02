//
//  SideRailView.swift
//  OuterView
//

import UIKit

/// One circular rail button model: icon, accessibility label, and tap handler.
struct RailAction {
    let systemImageName: String
    let accessibilityLabel: String
    let isProminent: Bool
    let isEnabled: Bool
    let menu: UIMenu?
    let handler: () -> Void

    init(
        systemImageName: String,
        accessibilityLabel: String,
        isProminent: Bool = false,
        isEnabled: Bool = true,
        menu: UIMenu? = nil,
        handler: @escaping () -> Void = {}
    ) {
        self.systemImageName = systemImageName
        self.accessibilityLabel = accessibilityLabel
        self.isProminent = isProminent
        self.isEnabled = isEnabled
        self.menu = menu
        self.handler = handler
    }

    static func back(isEnabled: Bool = true, handler: @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: "chevron.left",
            accessibilityLabel: "Back",
            isEnabled: isEnabled,
            handler: handler
        )
    }

    static func bookmarks(handler: @escaping () -> Void) -> RailAction {
        RailAction(systemImageName: "book", accessibilityLabel: "Bookmarks", handler: handler)
    }

    static func newTab(handler: @escaping () -> Void) -> RailAction {
        RailAction(systemImageName: "plus", accessibilityLabel: "New Tab", handler: handler)
    }

    static func tabs(handler: @escaping () -> Void) -> RailAction {
        RailAction(systemImageName: "square.on.square", accessibilityLabel: "Tabs", handler: handler)
    }

    static func search(handler: @escaping () -> Void) -> RailAction {
        RailAction(systemImageName: "magnifyingglass", accessibilityLabel: "Search", handler: handler)
    }

    static func overviewMenu(menu: UIMenu) -> RailAction {
        RailAction(
            systemImageName: "ellipsis",
            accessibilityLabel: "Overview Menu",
            menu: menu
        )
    }

    static func done(handler: @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: "checkmark",
            accessibilityLabel: "Done",
            isProminent: true,
            handler: handler
        )
    }

    static func cancel(handler: @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: "xmark",
            accessibilityLabel: "Cancel",
            isProminent: false,
            handler: handler
        )
    }

    static func addFolder(handler: @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: "folder.badge.plus",
            accessibilityLabel: "New Folder",
            handler: handler
        )
    }

    static func edit(isEditing: Bool = false, handler: @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: isEditing ? "checkmark" : "pencil",
            accessibilityLabel: isEditing ? "Done Editing" : "Edit Bookmarks",
            handler: handler
        )
    }

    static func files(handler: @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: "folder",
            accessibilityLabel: "Files",
            handler: handler
        )
    }

    static func clear(label: String = "Clear History", isEnabled: Bool = true, handler: @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: "trash",
            accessibilityLabel: label,
            isEnabled: isEnabled,
            handler: handler
        )
    }

    static func readingListMenu(menu: UIMenu) -> RailAction {
        RailAction(
            systemImageName: "ellipsis",
            accessibilityLabel: "Reading List Options",
            menu: menu
        )
    }

    static func deleteSelected(isEnabled: Bool = true, handler: @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: "trash",
            accessibilityLabel: "Delete Selected",
            isEnabled: isEnabled,
            handler: handler
        )
    }
}

/// Circular 44 pt Liquid Glass button backing one `RailAction`.
@MainActor
final class RailButton: UIButton {
    private let glassView: UIVisualEffectView
    private var action: RailAction?

    init(action: RailAction) {
        glassView = UIVisualEffectView(effect: GlassEffect.make())
        self.action = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityLabel = action.accessibilityLabel
        isEnabled = action.isEnabled
        alpha = action.isEnabled ? 1.0 : 0.35
        applyStyle(isProminent: action.isProminent)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        setImage(
            UIImage(systemName: action.systemImageName, withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        if let menu = action.menu {
            self.menu = menu
            self.showsMenuAsPrimaryAction = true
        } else {
            addAction(UIAction { [weak self] _ in self?.action?.handler() }, for: .touchUpInside)
        }
        setupGlass()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = bounds.width / 2
        layer.cornerRadius = radius
        glassView.layer.cornerRadius = radius
        glassView.clipsToBounds = true
        if #available(iOS 26.0, *) {
            glassView.cornerConfiguration = .capsule()
        }
        sendSubviewToBack(glassView)
    }

    private func applyStyle(isProminent: Bool) {
        if isProminent {
            tintColor = .white
            backgroundColor = .systemBlue
            glassView.alpha = 0
        } else {
            tintColor = .label
            backgroundColor = .clear
            glassView.alpha = 1
        }
    }

    private func setupGlass() {
        glassView.isUserInteractionEnabled = false
        glassView.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(glassView, at: 0)
        let widthConstraint = widthAnchor.constraint(equalToConstant: SideRailView.buttonDiameter)
        let heightConstraint = heightAnchor.constraint(equalToConstant: SideRailView.buttonDiameter)
        widthConstraint.priority = UILayoutPriority(999)
        heightConstraint.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthConstraint,
            heightConstraint
        ])
        clipsToBounds = true
    }
}

/// Single owner for rail-button stack rebuilds. Both `SideRailView` and
/// `TopBarView` compose the same `RailAction` arrays, so they share this
/// helper instead of triplicating the remove-and-rebuild loop.
@MainActor
extension UIStackView {
    func rebuild(with items: [RailAction]) {
        for arranged in arrangedSubviews {
            removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        for item in items {
            addArrangedSubview(RailButton(action: item))
        }
    }
}

/// Vertical rail overlay. The view itself is pinned full-bleed by its owner so
/// its safe area always matches the window; the two button stacks render as a
/// 60 pt column centered in the right system column (the reported right
/// safe-area inset, 84 pt on the Duo outer display). Only the stacks
/// participate in hit testing so web content stays tappable everywhere else.
@MainActor
final class SideRailView: UIView {
    nonisolated static let buttonDiameter: CGFloat = 44
    nonisolated static let spacing: CGFloat = 8
    nonisolated static let columnWidth: CGFloat = 60
    nonisolated static let safeColumnWidth: CGFloat = 84
    nonisolated static let topPadding: CGFloat = 12
    nonisolated static let bottomPadding: CGFloat = 4
    nonisolated static let reservedOcclusionHeight: CGFloat = 174

    /// Width of the system column the rail lives in: the live right inset
    /// when the system reports one, otherwise the measured Duo column.
    nonisolated static func systemColumnWidth(safeAreaRight: CGFloat) -> CGFloat {
        safeAreaRight > 0 ? safeAreaRight : safeColumnWidth
    }

    /// Top of the column: below both the safe area and any camera occlusion.
    /// The outer display reports zero top safe area, so the height floor keeps
    /// chrome below the status/camera region even when no occlusion is vended.
    nonisolated static func topOffset(safeAreaTop: CGFloat, reservedMaxY: CGFloat) -> CGFloat {
        max(safeAreaTop, reservedMaxY, reservedOcclusionHeight) + topPadding
    }

    /// X origin of the rail column centered in the right system column.
    nonisolated static func columnOriginX(boundsMaxX: CGFloat, safeAreaRight: CGFloat = 0) -> CGFloat {
        boundsMaxX - systemColumnWidth(safeAreaRight: safeAreaRight) / 2 - columnWidth / 2
    }

    /// Y of the suffix group bottom edge.
    nonisolated static func suffixBottomY(boundsMaxY: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        boundsMaxY - safeAreaBottom - bottomPadding
    }

    /// Full column frame inside `bounds`, centered in the right system column.
    nonisolated static func columnFrame(
        bounds: CGRect,
        safeAreaTop: CGFloat,
        reservedMaxY: CGFloat,
        safeAreaBottom: CGFloat,
        safeAreaRight: CGFloat = 0
    ) -> CGRect {
        let top = topOffset(safeAreaTop: safeAreaTop, reservedMaxY: reservedMaxY)
        let bottom = suffixBottomY(boundsMaxY: bounds.maxY, safeAreaBottom: safeAreaBottom)
        return CGRect(
            x: columnOriginX(boundsMaxX: bounds.maxX, safeAreaRight: safeAreaRight),
            y: top,
            width: columnWidth,
            height: max(0, bottom - top)
        )
    }

    /// Menu button frame in the bottom right corner, aligned with minified address pill.
    nonisolated static func menuButtonFrame(
        bounds: CGRect,
        safeAreaBottom: CGFloat,
        safeAreaRight: CGFloat = 0
    ) -> CGRect {
        let originX = columnOriginX(boundsMaxX: bounds.maxX, safeAreaRight: safeAreaRight)
        let buttonX = originX + (columnWidth - buttonDiameter) / 2
        let bottomOffset = max(safeAreaBottom, 20)
        let buttonY = bounds.maxY - bottomOffset - buttonDiameter
        return CGRect(x: buttonX, y: buttonY, width: buttonDiameter, height: buttonDiameter)
    }

    /// Camera/system occlusion union whose maxY pushes the column down. Read
    /// live in `layoutSubviews` together with the safe area.
    var reservedOcclusionUnion: CGRect = .zero

    /// Called when the bottom-right quick menu button is tapped.
    var onQuickMenuTapped: (() -> Void)?

    /// Last rail state actually applied through `setRailState`. A repeat
    /// request for the same rail skips the spring so buttons never restart.
    private(set) var lastAppliedRail: RailState?

    /// Number of times the appear/disappear spring body actually ran.
    private(set) var applyCount: Int = 0

    private let topStack = UIStackView()
    private let bottomStack = UIStackView()
    private lazy var quickMenuButton: RailButton = {
        let action = RailAction(
            systemImageName: "line.3.horizontal",
            accessibilityLabel: "Page and Navigation Menu",
            handler: { [weak self] in
                self?.onQuickMenuTapped?()
            }
        )
        return RailButton(action: action)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    nonisolated static func expectedStackHeight(itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        return CGFloat(itemCount) * buttonDiameter + CGFloat(itemCount - 1) * spacing
    }

    private func updateStack(_ stack: UIStackView, with items: [RailAction]) {
        let targetHeight = Self.expectedStackHeight(itemCount: items.count)
        if targetHeight > stack.bounds.height {
            stack.frame.size = CGSize(width: Self.columnWidth, height: targetHeight)
        }
        stack.rebuild(with: items)
        if targetHeight < stack.bounds.height {
            stack.frame.size = CGSize(width: Self.columnWidth, height: targetHeight)
        }
    }

    func setItems(prefix: [RailAction], suffix: [RailAction]) {
        updateStack(topStack, with: prefix)
        updateStack(bottomStack, with: suffix)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let top = Self.topOffset(
            safeAreaTop: safeAreaInsets.top,
            reservedMaxY: reservedOcclusionUnion.maxY
        )
        let bottom = Self.suffixBottomY(
            boundsMaxY: bounds.maxY,
            safeAreaBottom: safeAreaInsets.bottom
        )
        let originX = Self.columnOriginX(boundsMaxX: bounds.maxX, safeAreaRight: safeAreaInsets.right)
        let width = Self.columnWidth
        let targetSize = CGSize(width: width, height: UIView.noIntrinsicMetric)
        let topHeight = topStack.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .defaultHigh,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        topStack.frame = CGRect(x: originX, y: top, width: width, height: topHeight)
        let bottomHeight = bottomStack.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .defaultHigh,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        bottomStack.frame = CGRect(x: originX, y: bottom - bottomHeight, width: width, height: bottomHeight)

        quickMenuButton.frame = Self.menuButtonFrame(
            bounds: bounds,
            safeAreaBottom: safeAreaInsets.bottom,
            safeAreaRight: safeAreaInsets.right
        )
    }

    override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
        if quickMenuButton.alpha > 0.1, quickMenuButton.frame.contains(point) {
            return true
        }
        if topStack.alpha > 0.1, topStack.frame.contains(point) {
            return true
        }
        if bottomStack.alpha > 0.1, bottomStack.frame.contains(point) {
            return true
        }
        return false
    }

    func setRailState(_ rail: RailState, pill _: PillState, animated: Bool) {
        guard rail != lastAppliedRail else { return }
        let update = { [weak self] in
            guard let self else { return }
            // Quick menu appears as soon as the rail collapses so a restore
            // affordance remains before the pill minifies.
            let showMenu = (rail == .hidden)
            let showStacks = (rail == .visible)

            self.topStack.alpha = showStacks ? 1 : 0
            self.topStack.transform = showStacks ? .identity : CGAffineTransform(translationX: 30, y: 0)
            self.topStack.accessibilityElementsHidden = !showStacks

            self.bottomStack.alpha = showStacks ? 1 : 0
            self.bottomStack.transform = showStacks ? .identity : CGAffineTransform(translationX: 30, y: 0)
            self.bottomStack.accessibilityElementsHidden = !showStacks

            self.quickMenuButton.alpha = showMenu ? 1 : 0
            self.quickMenuButton.transform = showMenu ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
            self.quickMenuButton.accessibilityElementsHidden = !showMenu
        }
        if animated {
            UIView.animate(
                withDuration: BrowserRootViewController.railHideDuration,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0.5,
                options: [.curveEaseInOut, .allowUserInteraction],
                animations: update
            )
        } else {
            update()
        }
        lastAppliedRail = rail
        applyCount += 1
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .clear
        isOpaque = false
        for stack in [topStack, bottomStack] {
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = Self.spacing
            addSubview(stack)
        }
        addSubview(quickMenuButton)
        quickMenuButton.alpha = 0
        quickMenuButton.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
    }
}
