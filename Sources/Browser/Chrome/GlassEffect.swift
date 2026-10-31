//
//  GlassEffect.swift
//  OuterView
//

import UIKit

/// Single owner of the Liquid Glass background effect.
/// Falls back to system material on older systems.
@MainActor
enum GlassEffect {
    static func make() -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            UIGlassEffect()
        } else {
            UIBlurEffect(style: .systemMaterial)
        }
    }
}

/// Single owner for the heavy-blur sheet dim alpha shared by overlay cards
/// and the address editor panel. Both surfaces consume this value so the dim
/// can never drift apart.
@MainActor
enum SheetDim {
    nonisolated static let alpha: CGFloat = 0.2
}
