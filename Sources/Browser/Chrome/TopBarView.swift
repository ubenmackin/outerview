//
//  TopBarView.swift
//  OuterView
//

import UIKit

/// Compact width uses the bottom pill plus right rail; regular width uses a
/// top toolbar with the centered pill, a live tab strip, and no rail.
enum ChromePlacement: Sendable, Equatable {
    case compact
    case regular
}

/// Placement-driven chrome surface: stores a `ChromePlacement` and re-applies
/// layout when it changes. The `applyPlacement(for:)` forwarder lives here so
/// conforming views never triplicate it.
@MainActor
protocol ChromePlacementDriven: AnyObject {
    var chromePlacement: ChromePlacement { get set }
    func applyPlacement()
}

extension ChromePlacementDriven {
    func applyPlacement(for placement: ChromePlacement) {
        if chromePlacement != placement {
            chromePlacement = placement
        } else {
            applyPlacement()
        }
    }
}

/// Single owner for the regular header background. The bar spans edge to
/// edge with blurred page content behind it in every state.
@MainActor
enum RegularHeaderBackground {
    static func makeBlurEffect() -> UIVisualEffect {
        UIBlurEffect(style: .systemChromeMaterial)
    }

    static func apply(to view: UIView, blurView: UIVisualEffectView) {
        view.backgroundColor = .clear
        view.isOpaque = false
        if blurView.effect == nil {
            blurView.effect = makeBlurEffect()
        }
        blurView.isHidden = false
    }

    static func pinBlur(_ blurView: UIVisualEffectView, in view: UIView) {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

/// Regular-width toolbar owning button clusters flanking the shared pill slot.
/// The bar spans edge to edge with blurred page content behind it; leading
/// cluster inset 28, trailing cluster inset 164 (expanding dynamically for
/// top-right status occlusions), cluster spacing 12.
/// Expanded bar height is 84 pt and collapses to 48 pt on scroll; expanded
/// pill caps at 380 centered on the bar; collapsed keeps the mini capsule
/// centered.
@MainActor
final class TopBarView: UIView {
    nonisolated static let barHeight: CGFloat = 84
    nonisolated static let remnantHeight: CGFloat = 48
    nonisolated static let horizontalInset: CGFloat = 28
    nonisolated static let trailingStatusInset: CGFloat = 164
    nonisolated static let clusterSpacing: CGFloat = 12
    nonisolated static let expandedPillMaxWidth: CGFloat = 380
    nonisolated static var minifiedPillMinWidth: CGFloat {
        AddressBarView.minifiedPillMinWidth
    }

    nonisolated static let expandedControlVerticalOffset: CGFloat = 4
    nonisolated static let dynamicInsetMinimumBoundsWidth: CGFloat = 600
    nonisolated static let minimumSlotContentWidth: CGFloat = 320

    let leadingStack = UIStackView()
    let trailingStack = UIStackView()
    let pillSlotView = UIView()
    private let blurView = UIVisualEffectView(effect: RegularHeaderBackground.makeBlurEffect())

    private(set) var isCollapsed = false
    private var barHeightConstraint: NSLayoutConstraint!
    private var leadingInsetConstraint: NSLayoutConstraint!
    private var trailingInsetConstraint: NSLayoutConstraint!
    private var leadingCenterYConstraint: NSLayoutConstraint!
    private var trailingCenterYConstraint: NSLayoutConstraint!
    private var slotCenterYConstraint: NSLayoutConstraint!
    private var slotHeightConstraint: NSLayoutConstraint!

    var isBlurVisible: Bool {
        !blurView.isHidden
    }

    var currentHeightConstant: CGFloat {
        barHeightConstraint.constant
    }

    func applyHeaderBackground() {
        RegularHeaderBackground.apply(to: self, blurView: blurView)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var bounds: CGRect {
        didSet {
            if oldValue.size != bounds.size {
                setNeedsUpdateConstraints()
            }
        }
    }

    override func updateConstraints() {
        updateHorizontalInsets()
        super.updateConstraints()
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        barHeightConstraint.constant = collapsed ? Self.remnantHeight : Self.barHeight
        let verticalOffset = collapsed ? 0 : Self.expandedControlVerticalOffset
        leadingCenterYConstraint.constant = verticalOffset
        trailingCenterYConstraint.constant = verticalOffset
        slotCenterYConstraint.constant = verticalOffset
        slotHeightConstraint.constant = collapsed ? AddressBarView.minifiedHeight : AddressBarView.expandedHeight
        setNeedsUpdateConstraints()
    }

    func setItems(prefix: [RailAction], suffix: [RailAction]) {
        leadingStack.rebuild(with: prefix)
        trailingStack.rebuild(with: suffix)
        setNeedsUpdateConstraints()
        setNeedsLayout()
    }

    private func updateHorizontalInsets() {
        var leading = Self.horizontalInset
        var trailing = isCollapsed ? Self.horizontalInset : Self.trailingStatusInset
        if !isCollapsed, bounds.width >= Self.dynamicInsetMinimumBoundsWidth {
            let barInsets = directionalEdgeInsets(for: .bar(onEdge: NSDirectionalRectEdge.top, extent: Self.barHeight))
            leading = max(leading, barInsets.leading)
            trailing = max(trailing, barInsets.trailing)
            for region in reservedRegions(kind: .occlusion) {
                if region.frame.minY < Self.barHeight, region.frame.midX > bounds.midX {
                    let regionTrailing = bounds.width - region.frame.minX
                    trailing = max(trailing, regionTrailing)
                }
            }
            let maxTrailing = max(Self.trailingStatusInset, bounds.width - leading - Self.minimumSlotContentWidth)
            trailing = min(trailing, maxTrailing)
        }
        if leadingInsetConstraint.constant != leading {
            leadingInsetConstraint.constant = leading
        }
        if trailingInsetConstraint.constant != -trailing {
            trailingInsetConstraint.constant = -trailing
        }
    }

    private func setup() {
        RegularHeaderBackground.pinBlur(blurView, in: self)
        applyHeaderBackground()
        for stack in [leadingStack, trailingStack] {
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = Self.clusterSpacing
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
        }
        pillSlotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pillSlotView)

        barHeightConstraint = heightAnchor.constraint(equalToConstant: Self.barHeight)
        leadingInsetConstraint = leadingStack.leadingAnchor.constraint(
            equalTo: leadingAnchor, constant: Self.horizontalInset
        )
        leadingCenterYConstraint = leadingStack.centerYAnchor.constraint(
            equalTo: centerYAnchor, constant: Self.expandedControlVerticalOffset
        )
        trailingInsetConstraint = trailingStack.trailingAnchor.constraint(
            equalTo: trailingAnchor, constant: -Self.trailingStatusInset
        )
        trailingCenterYConstraint = trailingStack.centerYAnchor.constraint(
            equalTo: centerYAnchor, constant: Self.expandedControlVerticalOffset
        )
        slotCenterYConstraint = pillSlotView.centerYAnchor.constraint(
            equalTo: centerYAnchor, constant: Self.expandedControlVerticalOffset
        )
        slotHeightConstraint = pillSlotView.heightAnchor.constraint(
            equalToConstant: AddressBarView.expandedHeight
        )
        slotHeightConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            barHeightConstraint,
            leadingInsetConstraint,
            leadingCenterYConstraint,
            trailingInsetConstraint,
            trailingCenterYConstraint,
            pillSlotView.leadingAnchor.constraint(
                equalTo: leadingStack.trailingAnchor, constant: Self.clusterSpacing
            ),
            pillSlotView.trailingAnchor.constraint(
                equalTo: trailingStack.leadingAnchor, constant: -Self.clusterSpacing
            ),
            slotCenterYConstraint,
            slotHeightConstraint
        ])
    }
}
