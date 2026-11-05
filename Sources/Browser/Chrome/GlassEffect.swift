// Chrome — Liquid Glass background effect shared by chrome surfaces.

import UIKit

/// Single owner of the Liquid Glass background effect.
/// Falls back to system material on older systems.
@MainActor
enum GlassEffect {
    static func make() -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            return effect
        } else {
            return UIBlurEffect(style: .systemMaterial)
        }
    }

    /// Blur-only variant for bar appearances, which accept
    /// `UIBlurEffect` rather than arbitrary visual effects.
    static func makeBlur() -> UIBlurEffect {
        UIBlurEffect(style: .systemMaterial)
    }
}

/// Single owner for the heavy-blur sheet dim alpha shared by overlay cards
/// and the address editor panel. Both surfaces consume this value so the dim
/// can never drift apart.
@MainActor
enum SheetDim {
    nonisolated static let alpha: CGFloat = 0.2
}
