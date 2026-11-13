// Chrome — System toolbar mapping from rail actions to bar button items.

import UIKit

/// Single owner mapping `RailAction` models to system bar items and buttons.
/// Hosts always remove every stale view before rebuilding through this mapper.
@MainActor
enum SystemToolbarMapper {
    nonisolated static let symbolPointSize: CGFloat = 18
    nonisolated static let hitTarget: CGFloat = 44
    nonisolated static let bottomBarHeight: CGFloat = 44
    nonisolated static let bottomBarCornerRadius: CGFloat = 22
    nonisolated static let bottomBarSymbolPointSize: CGFloat = 18
    nonisolated static let bottomBarSpacing: CGFloat = 8

    /// Symbol image honoring the 17–22 pt fail-closed band.
    static func symbolImage(named systemImageName: String) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
        return UIImage(systemName: systemImageName, withConfiguration: config)?
            .withRenderingMode(.alwaysTemplate)
    }

    /// Symbol image for one rail action. Main-actor isolated so the
    /// non-Sendable action never crosses isolation boundaries.
    static func symbolImage(for action: RailAction) -> UIImage? {
        symbolImage(named: action.systemImageName)
    }

    /// Shared menu for bar items and buttons. Deferred providers hop
    /// back to the main actor before vending children.
    private static func resolveMenu(for action: RailAction) -> UIMenu? {
        if let direct = action.menu {
            return direct
        }
        guard let provider = action.menuProvider else { return nil }
        return UIMenu(children: [
            UIDeferredMenuElement.uncached { completion in
                completion(provider()?.children ?? [])
            }
        ])
    }

    /// Whether a tap action coexists with the menu. Menu-primary
    /// actions omit the tap so press shows the menu with elasticity.
    private static func needsTap(menu: UIMenu?, showsMenuAsPrimaryAction: Bool) -> Bool {
        menu == nil || !showsMenuAsPrimaryAction
    }

    /// Bar-item tap invoking the main-actor action directly.
    private static func barTap(for action: RailAction) -> UIAction {
        let handler = action.handler
        let image = symbolImage(for: action)
        return UIAction(title: action.accessibilityLabel, image: image) { _ in
            handler()
        }
    }

    /// Button tap for stack hosts invoking the main-actor action directly.
    private static func buttonTap(for action: RailAction) -> UIAction {
        let handler = action.handler
        return UIAction { _ in
            handler()
        }
    }

    /// Remove every view so stale items and backgrounds never survive a reload.
    static func clearStack(_ stack: UIStackView) {
        for arranged in stack.arrangedSubviews {
            stack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        for subview in stack.subviews {
            subview.removeFromSuperview()
        }
    }

    /// One action to one bar item, keeping label, enabled state, menu, and tap.
    /// Disabled items stay in a visible toolbar; the system dims them.
    static func makeItem(for action: RailAction) -> UIBarButtonItem {
        let image = symbolImage(for: action)
        let menu = resolveMenu(for: action)
        let primary: UIAction? = needsTap(
            menu: menu,
            showsMenuAsPrimaryAction: action.showsMenuAsPrimaryAction
        ) ? barTap(for: action) : nil
        let item = UIBarButtonItem(
            title: action.accessibilityLabel,
            image: image,
            primaryAction: primary,
            menu: menu
        )
        item.accessibilityLabel = action.accessibilityLabel
        item.accessibilityIdentifier = action.accessibilityLabel
        item.isEnabled = action.isEnabled
        if action.isProminent {
            item.tintColor = .systemBlue
        } else {
            item.tintColor = .label
        }
        return item
    }

    /// One cluster of actions to bar items, preserving order.
    static func makeItems(_ actions: [RailAction]) -> [UIBarButtonItem] {
        actions.map(makeItem(for:))
    }

    /// Both clusters to bar items. Hosts insert their own flexible spacing, so
    /// counts and labels stay identical across rail, top, and bottom hosts.
    static func makeToolbarItems(prefix: [RailAction], suffix: [RailAction]) -> [UIBarButtonItem] {
        makeItems(prefix) + makeItems(suffix)
    }

    /// Overview bar items with flexible space separating leading and trailing clusters.
    static func makeOverviewToolbarItems(prefix: [RailAction], suffix: [RailAction]) -> [UIBarButtonItem] {
        var mapped = makeItems(prefix)
        if !prefix.isEmpty, !suffix.isEmpty {
            let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            mapped.append(spacer)
        }
        mapped.append(contentsOf: makeItems(suffix))
        return mapped
    }

    /// Shared appearance for every chrome toolbar. Hosts configuring a
    /// custom toolbar instance apply this instead of copying a template.
    static func toolbarAppearance() -> UIToolbarAppearance {
        let appearance = UIToolbarAppearance()
        appearance.configureWithTransparentBackground()
        // Appearance accepts blur only; glass lives in effect views.
        appearance.backgroundEffect = GlassEffect.makeBlur()
        appearance.shadowColor = .clear
        return appearance
    }

    /// Shared glass toolbar for one cluster. Every chrome toolbar funnels here
    /// so the glass background can never drift between hosts.
    static func toolbar(items: [UIBarButtonItem]) -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.isTranslucent = true
        toolbar.backgroundColor = .clear
        let appearance = toolbarAppearance()
        toolbar.standardAppearance = appearance
        toolbar.scrollEdgeAppearance = appearance
        toolbar.items = items
        // System hit target: every chrome toolbar stands 44 pt tall.
        toolbar.heightAnchor.constraint(equalToConstant: hitTarget).isActive = true
        return toolbar
    }

    /// One vertical rail toolbar per action. Centralizes the N-toolbar
    /// vertical exception so rail and mapper can never drift apart.
    static func railToolbar(for action: RailAction) -> UIToolbar {
        let bar = toolbar(items: [makeItem(for: action)])
        bar.widthAnchor.constraint(equalToConstant: hitTarget).isActive = true
        return bar
    }

    /// Vertical rail cluster as one toolbar per action with shared glass.
    static func railToolbars(for actions: [RailAction]) -> [UIToolbar] {
        actions.map(railToolbar(for:))
    }

    /// System button for stack hosts with no toolbar of their own.
    /// Uses native Liquid Glass button configuration with capsule geometry.
    static func makeButton(for action: RailAction) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        let symbol = UIImage.SymbolConfiguration(
            pointSize: bottomBarSymbolPointSize,
            weight: .medium
        )
        config.image = UIImage(systemName: action.systemImageName, withConfiguration: symbol)?
            .withRenderingMode(.alwaysTemplate)
        config.contentInsets = .zero
        // Glass ignores view tint/background, so prominence lives in base colors.
        if action.isProminent {
            config.baseBackgroundColor = .systemBlue
            config.baseForegroundColor = .white
        } else {
            config.baseBackgroundColor = .clear
            config.baseForegroundColor = .label
        }
        button.configuration = config
        button.accessibilityLabel = action.accessibilityLabel
        button.isEnabled = action.isEnabled
        // Disabled actions stay visible at reduced alpha, never hidden.
        button.alpha = action.isEnabled ? 1.0 : 0.35
        let menu = resolveMenu(for: action)
        if let menu {
            button.menu = menu
            button.showsMenuAsPrimaryAction = action.showsMenuAsPrimaryAction
        }
        if needsTap(menu: menu, showsMenuAsPrimaryAction: action.showsMenuAsPrimaryAction) {
            button.addAction(buttonTap(for: action), for: .touchUpInside)
        }
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: hitTarget),
            button.heightAnchor.constraint(equalToConstant: hitTarget)
        ])
        return button
    }

    /// Populates any UIStackView host with native Liquid Glass buttons.
    /// Used by SideRailView (Mode 1), TopBarView (Mode 2), and bottom stacks (Mode 3).
    static func populateStack(
        _ stack: UIStackView,
        with actions: [RailAction],
        axis: NSLayoutConstraint.Axis,
        spacing: CGFloat = bottomBarSpacing
    ) {
        clearStack(stack)
        stack.axis = axis
        stack.alignment = .center
        stack.spacing = spacing
        stack.backgroundColor = .clear
        stack.isOpaque = false
        for action in actions {
            stack.addArrangedSubview(makeButton(for: action))
        }
        stack.layoutIfNeeded()
    }

    /// Bottom-stack host: full remove plus rebuild with native glass buttons,
    /// so stale buttons never survive a state change.
    static func populateBottomStack(_ stack: UIStackView, with actions: [RailAction]) {
        populateStack(stack, with: actions, axis: .horizontal, spacing: bottomBarSpacing)
    }
}
