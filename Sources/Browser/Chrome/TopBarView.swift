// Chrome — Four-mode toolbar + BrowserInterfaceMode declaration.

import UIKit

/// Compact uses bottom pill plus rail or stacks; regular landscape
/// uses top toolbar, regular portrait (Mode 4) bottom plus vertical bar.
enum ChromePlacement: Sendable, Equatable {
    case compact
    case regular
}

/// Interface modes: duoOuter (outer rail + bottom pill),
/// duoInnerOrPadLandscape (inner/iPad landscape top bar + tab strip),
/// duoInnerOrPadPortrait (inner/iPad portrait bottom bar + vertical tab bar),
/// nonDuoPhone (bottom pill + top toolbar buttons).
enum BrowserInterfaceMode: Sendable, Equatable {
    case duoOuter
    case duoInnerOrPadLandscape
    case duoInnerOrPadPortrait
    case nonDuoPhone
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
    /// Shared glass: toolbar appearances vend the same blur, so no seam forms.
    static func makeBlurEffect() -> UIVisualEffect {
        GlassEffect.makeBlur()
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

/// Regular-width toolbar flanking the shared pill slot; blurred behind.
/// Leading inset 28, trailing inset 84, pill gaps plus stack spacing 12.
/// Expanded 84 pt collapses to 48 pt; pill caps at 380 centered.
@MainActor
final class TopBarView: UIView {
    nonisolated static let barHeight: CGFloat = 84
    nonisolated static let remnantHeight: CGFloat = 48
    nonisolated static let mode3BarHeight: CGFloat = 44
    nonisolated static let horizontalInset: CGFloat = 28
    nonisolated static let nonDuoHorizontalInset: CGFloat = 16
    nonisolated static let trailingStatusInset: CGFloat = 84
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
    var onSlotWidthChanged: (() -> Void)?
    private let blurView = UIVisualEffectView(effect: RegularHeaderBackground.makeBlurEffect())

    var leadingButtons: [UIButton] {
        leadingStack.arrangedSubviews.compactMap { $0 as? UIButton }
    }

    var trailingButtons: [UIButton] {
        trailingStack.arrangedSubviews.compactMap { $0 as? UIButton }
    }

    var isNonDuoPhone: Bool = false {
        didSet {
            if oldValue != isNonDuoPhone {
                barHeightConstraint.constant = isCollapsed
                    ? (isNonDuoPhone ? 0 : Self.remnantHeight)
                    : (isNonDuoPhone ? Self.mode3BarHeight : Self.barHeight)
                let verticalOffset = isNonDuoPhone ? 0 : (isCollapsed ? 0 : Self.expandedControlVerticalOffset)
                leadingCenterYConstraint.constant = verticalOffset
                trailingCenterYConstraint.constant = verticalOffset
                slotCenterYConstraint.constant = verticalOffset
                updateHorizontalInsets()
                setNeedsUpdateConstraints()
                setNeedsLayout()
            }
        }
    }

    private(set) var isCollapsed = false
    private var lastNotifiedSlotWidth: CGFloat = -1
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

    var showsBackgroundBar: Bool = true {
        didSet {
            applyHeaderBackground()
        }
    }

    var currentHeightConstant: CGFloat {
        barHeightConstraint.constant
    }

    func applyHeaderBackground() {
        if showsBackgroundBar {
            RegularHeaderBackground.apply(to: self, blurView: blurView)
        } else {
            backgroundColor = .clear
            blurView.isHidden = true
        }
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

    override func layoutSubviews() {
        super.layoutSubviews()
        let slotWidth = pillSlotView.bounds.width
        if abs(slotWidth - lastNotifiedSlotWidth) > 0.01 {
            lastNotifiedSlotWidth = slotWidth
            onSlotWidthChanged?()
        }
    }

    func setCollapsed(_ collapsed: Bool) {
        let targetHeight: CGFloat = isNonDuoPhone
            ? (collapsed ? 0 : Self.mode3BarHeight)
            : (collapsed ? Self.remnantHeight : Self.barHeight)
        let verticalOffset: CGFloat = isNonDuoPhone ? 0 : (collapsed ? 0 : Self.expandedControlVerticalOffset)
        let targetSlotHeight: CGFloat = collapsed ? AddressBarView.minifiedHeight : AddressBarView.expandedHeight
        let targetAlpha: CGFloat = (isNonDuoPhone && collapsed) ? 0 : 1

        guard isCollapsed != collapsed
            || barHeightConstraint.constant != targetHeight
            || leadingCenterYConstraint.constant != verticalOffset
            || slotHeightConstraint.constant != targetSlotHeight
            || leadingStack.alpha != targetAlpha
        else { return }

        isCollapsed = collapsed
        barHeightConstraint.constant = targetHeight
        if isNonDuoPhone {
            leadingStack.alpha = targetAlpha
            trailingStack.alpha = targetAlpha
        }
        leadingCenterYConstraint.constant = verticalOffset
        trailingCenterYConstraint.constant = verticalOffset
        slotCenterYConstraint.constant = verticalOffset
        slotHeightConstraint.constant = targetSlotHeight
        updateHorizontalInsets()
        setNeedsUpdateConstraints()
    }

    func setItems(prefix: [RailAction], suffix: [RailAction]) {
        // Full reset through the mapper: stale items never survive a reload.
        // Stack arranges native glass buttons directly.
        SystemToolbarMapper.populateStack(leadingStack, with: prefix, axis: .horizontal, spacing: Self.clusterSpacing)
        SystemToolbarMapper.populateStack(trailingStack, with: suffix, axis: .horizontal, spacing: Self.clusterSpacing)
        setNeedsUpdateConstraints()
        setNeedsLayout()
    }

    private func updateHorizontalInsets() {
        if isNonDuoPhone {
            if leadingInsetConstraint.constant != Self.nonDuoHorizontalInset {
                leadingInsetConstraint.constant = Self.nonDuoHorizontalInset
            }
            if trailingInsetConstraint.constant != -Self.nonDuoHorizontalInset {
                trailingInsetConstraint.constant = -Self.nonDuoHorizontalInset
            }
            return
        }
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
