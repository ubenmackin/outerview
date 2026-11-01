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

/// Single owner for the regular header opaque-vs-translucent switch.
/// Both `TopBarView` and `TabStripView` delegate here so the collapsed
/// translucent remnant and the expanded opaque bar can never drift apart.
@MainActor
enum RegularHeaderBackground {
    static func apply(to view: UIView, blurView: UIVisualEffectView, isCollapsed: Bool) {
        if isCollapsed {
            view.backgroundColor = .clear
            view.isOpaque = false
            blurView.isHidden = false
        } else {
            view.backgroundColor = .systemBackground
            view.isOpaque = true
            blurView.isHidden = true
        }
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
/// Toolbar height TopBarView.barHeight, strip height TabStripView.stripHeight,
/// remnant height equals toolbar height, trailing status clearance 96,
/// expanded top inset equals toolbar plus visible strip.
/// Shared Contract REGULAR-COLLAPSE: collapsed keeps topBarView visible with
/// both stacks plus strip hidden and the pill minified centered in its slot
/// through slot-scoped centerX plus width constraints; expanded is unchanged;
/// collapsed top inset equals TopBarView.remnantHeight; additionalSafeArea top
/// is zero in every placement and state; no remnant view exists anywhere.
@MainActor
final class TopBarView: UIView {
    nonisolated static let barHeight: CGFloat = 56
    nonisolated static let horizontalInset: CGFloat = 12
    nonisolated static let clusterSpacing: CGFloat = 8
    nonisolated static let trailingClearance: CGFloat = 96
    nonisolated static var remnantHeight: CGFloat {
        barHeight
    }

    let leadingStack = UIStackView()
    let trailingStack = UIStackView()
    let pillSlotView = UIView()
    private let blurView = UIVisualEffectView(effect: GlassEffect.make())

    var isBlurVisible: Bool {
        !blurView.isHidden
    }

    func applyHeaderBackground(isCollapsed: Bool) {
        RegularHeaderBackground.apply(to: self, blurView: blurView, isCollapsed: isCollapsed)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setItems(prefix: [RailAction], suffix: [RailAction]) {
        leadingStack.rebuild(with: prefix)
        trailingStack.rebuild(with: suffix)
        setNeedsLayout()
    }

    private func setup() {
        RegularHeaderBackground.pinBlur(blurView, in: self)
        applyHeaderBackground(isCollapsed: false)
        for stack in [leadingStack, trailingStack] {
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = Self.clusterSpacing
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
        }
        pillSlotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pillSlotView)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.barHeight),
            leadingStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            leadingStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            trailingStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillSlotView.leadingAnchor.constraint(
                equalTo: leadingStack.trailingAnchor, constant: Self.clusterSpacing
            ),
            pillSlotView.trailingAnchor.constraint(
                equalTo: trailingStack.leadingAnchor, constant: -Self.clusterSpacing
            ),
            pillSlotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillSlotView.heightAnchor.constraint(equalToConstant: AddressBarView.expandedHeight),
            pillSlotView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 6),
            pillSlotView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6)
        ])
    }
}
