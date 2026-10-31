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

/// Regular-width toolbar owning button clusters flanking the shared pill slot.
@MainActor
final class TopBarView: UIView {
    nonisolated static let barHeight: CGFloat = 56
    nonisolated static let horizontalInset: CGFloat = 12
    nonisolated static let clusterSpacing: CGFloat = 8

    let leadingStack = UIStackView()
    let trailingStack = UIStackView()
    let pillSlotView = UIView()

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
        backgroundColor = .clear
        isOpaque = false
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
