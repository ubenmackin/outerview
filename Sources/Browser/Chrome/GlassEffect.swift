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
