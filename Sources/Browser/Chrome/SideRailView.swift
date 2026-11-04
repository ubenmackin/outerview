// Chrome — Adaptive command rail with circular glass buttons and stack layout.

import UIKit

/// One circular rail button model: icon, accessibility label, and tap handler.
struct RailAction {
    let systemImageName: String
    let accessibilityLabel: String
    let isProminent: Bool
    let isEnabled: Bool
    let menu: UIMenu?
    let menuProvider: (@MainActor @Sendable () -> UIMenu?)?
    let showsMenuAsPrimaryAction: Bool
    let handler: @MainActor @Sendable () -> Void

    init(
        systemImageName: String,
        accessibilityLabel: String,
        isProminent: Bool = false,
        isEnabled: Bool = true,
        menu: UIMenu? = nil,
        menuProvider: (@MainActor @Sendable () -> UIMenu?)? = nil,
        showsMenuAsPrimaryAction: Bool = true,
        handler: @MainActor @Sendable @escaping () -> Void = {}
    ) {
        self.systemImageName = systemImageName
        self.accessibilityLabel = accessibilityLabel
        self.isProminent = isProminent
        self.isEnabled = isEnabled
        self.menu = menu
        self.menuProvider = menuProvider
        self.showsMenuAsPrimaryAction = showsMenuAsPrimaryAction
        self.handler = handler
    }

    static func back(
        isEnabled: Bool = true,
        menuProvider: (@MainActor @Sendable () -> UIMenu?)? = nil,
        handler: @MainActor @Sendable @escaping () -> Void
    ) -> RailAction {
        RailAction(
            systemImageName: "chevron.left",
            accessibilityLabel: "Back",
            isEnabled: isEnabled,
            menuProvider: menuProvider,
            showsMenuAsPrimaryAction: false,
            handler: handler
        )
    }

    static func bookmarks(handler: @MainActor @Sendable @escaping () -> Void) -> RailAction {
        RailAction(systemImageName: "book", accessibilityLabel: "Bookmarks", handler: handler)
    }

    static func newTab(handler: @MainActor @Sendable @escaping () -> Void) -> RailAction {
        RailAction(systemImageName: "plus", accessibilityLabel: "New Tab", handler: handler)
    }

    static func tabs(
        menuProvider: (@MainActor @Sendable () -> UIMenu?)? = nil,
        showsMenuAsPrimaryAction: Bool = false,
        handler: @MainActor @Sendable @escaping () -> Void
    ) -> RailAction {
        RailAction(
            systemImageName: "square.on.square",
            accessibilityLabel: "Tabs",
            menuProvider: menuProvider,
            showsMenuAsPrimaryAction: showsMenuAsPrimaryAction,
            handler: handler
        )
    }

    static func search(handler: @MainActor @Sendable @escaping () -> Void) -> RailAction {
        RailAction(systemImageName: "magnifyingglass", accessibilityLabel: "Search", handler: handler)
    }

    static func overviewMenu(menu: UIMenu) -> RailAction {
        RailAction(
            systemImageName: "ellipsis",
            accessibilityLabel: "Overview Menu",
            menu: menu
        )
    }

    static func done(handler: @MainActor @Sendable @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: "checkmark",
            accessibilityLabel: "Done",
            isProminent: true,
            handler: handler
        )
    }

    static func cancel(handler: @MainActor @Sendable @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: "xmark",
            accessibilityLabel: "Cancel",
            isProminent: false,
            handler: handler
        )
    }

    static func addFolder(handler: @MainActor @Sendable @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: "folder.badge.plus",
            accessibilityLabel: "New Folder",
            handler: handler
        )
    }

    static func edit(isEditing: Bool = false, handler: @MainActor @Sendable @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: isEditing ? "checkmark" : "pencil",
            accessibilityLabel: isEditing ? "Done Editing" : "Edit Bookmarks",
            handler: handler
        )
    }

    static func files(handler: @MainActor @Sendable @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: "folder",
            accessibilityLabel: "Files",
            handler: handler
        )
    }

    static func clear(label: String = "Clear History", isEnabled: Bool = true, handler: @MainActor @Sendable @escaping () -> Void) -> RailAction {
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

    static func deleteSelected(isEnabled: Bool = true, handler: @MainActor @Sendable @escaping () -> Void) -> RailAction {
        RailAction(
            systemImageName: "trash",
            accessibilityLabel: "Delete Selected",
            isEnabled: isEnabled,
            handler: handler
        )
    }
}

/// Circular 44 pt Liquid Glass button backing one `RailAction`.
/// Bottom-bar instances use 22 pt symbols with no per-button glass.
@MainActor
final class RailButton: UIButton {
    private let glassView: UIVisualEffectView
    private var action: RailAction?
    private(set) var isBottomBar = false

    init(action: RailAction, isBottomBar: Bool = false) {
        glassView = UIVisualEffectView(effect: GlassEffect.make())
        self.action = action
        self.isBottomBar = isBottomBar
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityLabel = action.accessibilityLabel
        isEnabled = action.isEnabled
        alpha = action.isEnabled ? 1.0 : 0.35
        applyStyle(isProminent: action.isProminent, isBottomBar: isBottomBar)
        let pointSize = isBottomBar ? SideRailView.bottomBarSymbolPointSize : SideRailView.railSymbolPointSize
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        setImage(
            UIImage(systemName: action.systemImageName, withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        if let menuProvider = action.menuProvider {
            self.menu = UIMenu(children: [
                UIDeferredMenuElement { completion in
                    let resolved = menuProvider()
                    completion(resolved?.children ?? [])
                }
            ])
            self.showsMenuAsPrimaryAction = action.showsMenuAsPrimaryAction
            if !action.showsMenuAsPrimaryAction {
                addAction(UIAction { [weak self] _ in self?.action?.handler() }, for: .touchUpInside)
            }
        } else if let menu = action.menu {
            self.menu = menu
            self.showsMenuAsPrimaryAction = action.showsMenuAsPrimaryAction
            if !action.showsMenuAsPrimaryAction {
                addAction(UIAction { [weak self] _ in self?.action?.handler() }, for: .touchUpInside)
            }
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
        if layer.cornerRadius != radius {
            layer.cornerRadius = radius
        }
        if glassView.layer.cornerRadius != radius {
            glassView.layer.cornerRadius = radius
        }
    }

    private func applyStyle(isProminent: Bool, isBottomBar: Bool = false) {
        if isProminent {
            tintColor = .white
            backgroundColor = .systemBlue
            glassView.alpha = 0
            glassView.isHidden = isBottomBar
        } else if isBottomBar {
            tintColor = .label
            backgroundColor = .clear
            glassView.alpha = 0
            glassView.isHidden = true
        } else {
            tintColor = .label
            backgroundColor = .clear
            glassView.alpha = 1
            glassView.isHidden = false
        }
    }

    private func setupGlass() {
        glassView.isUserInteractionEnabled = false
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.layer.zPosition = -1
        let radius = SideRailView.buttonDiameter / 2
        layer.cornerRadius = radius
        glassView.layer.cornerRadius = radius
        glassView.clipsToBounds = true
        if #available(iOS 26.0, *) {
            glassView.cornerConfiguration = .capsule()
        }
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
        if isMode3BottomBar {
            rebuildBottomBar(with: items)
            return
        }
        for arranged in arrangedSubviews {
            removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        for item in items {
            addArrangedSubview(RailButton(action: item))
        }
    }

    /// Toolbar-grade capsule for Mode 3 bottom stacks: one shared glass
    /// capsule per side holding 44 pt targets with 22 pt symbols at 4 pt spacing.
    func rebuildBottomBar(with items: [RailAction]) {
        for arranged in arrangedSubviews {
            removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        axis = .horizontal
        alignment = .center
        spacing = SideRailView.bottomBarSpacing
        ensureBottomBarCapsule()
        for item in items {
            addArrangedSubview(RailButton(action: item, isBottomBar: true))
        }
        layoutIfNeeded()
    }

    /// Bottom bars are the only stacks pinned to the 50 pt capsule height.
    private var isMode3BottomBar: Bool {
        constraints.contains {
            $0.firstAttribute == .height
                && abs($0.constant - SideRailView.bottomBarHeight) < 0.5
        }
    }

    /// Shared capsule glass behind the buttons. Reused across rebuilds
    /// so stale backgrounds never stack above the buttons.
    private func ensureBottomBarCapsule() {
        backgroundColor = .clear
        isOpaque = false
        layer.cornerRadius = SideRailView.bottomBarCornerRadius
        clipsToBounds = true
        let existing = subviews.first {
            $0 is UIVisualEffectView && !arrangedSubviews.contains($0)
        } as? UIVisualEffectView
        let capsule: UIVisualEffectView
        if let existing {
            capsule = existing
            if capsule.effect == nil {
                capsule.effect = GlassEffect.make()
            }
        } else {
            capsule = UIVisualEffectView(effect: GlassEffect.make())
            capsule.isUserInteractionEnabled = false
            capsule.translatesAutoresizingMaskIntoConstraints = false
            capsule.layer.cornerRadius = SideRailView.bottomBarCornerRadius
            capsule.clipsToBounds = true
            if #available(iOS 26.0, *) {
                capsule.cornerConfiguration = .capsule()
            }
            insertSubview(capsule, at: 0)
            NSLayoutConstraint.activate([
                capsule.leadingAnchor.constraint(equalTo: leadingAnchor),
                capsule.trailingAnchor.constraint(equalTo: trailingAnchor),
                capsule.topAnchor.constraint(equalTo: topAnchor),
                capsule.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        capsule.isHidden = false
        capsule.alpha = 1
        capsule.layer.cornerRadius = SideRailView.bottomBarCornerRadius
        capsule.clipsToBounds = true
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
    nonisolated static let bottomBarHeight: CGFloat = 50
    nonisolated static let bottomBarCornerRadius: CGFloat = 25
    nonisolated static let bottomBarSymbolPointSize: CGFloat = 22
    nonisolated static let bottomBarSpacing: CGFloat = 4
    nonisolated static let railSymbolPointSize: CGFloat = 18

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

    /// Camera/system occlusion union whose maxY pushes the column down. Read
    /// live in `layoutSubviews` together with the safe area.
    var reservedOcclusionUnion: CGRect = .zero

    /// Last rail state actually applied through `setRailState`. A repeat
    /// request for the same rail skips the spring so buttons never restart.
    private(set) var lastAppliedRail: RailState?

    /// Number of times the appear/disappear spring body actually ran.
    private(set) var applyCount: Int = 0

    private let topStack = UIStackView()
    private let bottomStack = UIStackView()

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
    }

    override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
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
            let showStacks = (rail == .visible)

            self.topStack.alpha = showStacks ? 1 : 0
            self.topStack.transform = showStacks ? .identity : CGAffineTransform(translationX: 30, y: 0)
            self.topStack.accessibilityElementsHidden = !showStacks

            self.bottomStack.alpha = showStacks ? 1 : 0
            self.bottomStack.transform = showStacks ? .identity : CGAffineTransform(translationX: 30, y: 0)
            self.bottomStack.accessibilityElementsHidden = !showStacks
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
    }
}
