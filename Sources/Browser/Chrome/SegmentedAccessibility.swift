//
//  SegmentedAccessibility.swift
//  OuterView
//

import UIKit

/// Single owner of `UISegmentedControl` VoiceOver wiring.
///
/// Both the library tab bar and the tab-groups sheet pill drive private
/// `UISegment` subviews, so segment discovery (type-name filter +
/// left-to-right sort) and per-index label/identifier assignment live here
/// instead of being mirrored in each host view.
@MainActor
enum SegmentedAccessibility {
    /// Private segment subviews backing `control`, ordered left-to-right.
    static func segmentViews(in control: UISegmentedControl) -> [UIView] {
        control.subviews.filter {
            String(describing: type(of: $0)).contains("Segment")
        }.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Assigns VoiceOver labels/identifiers pairwise. Extra segment views
    /// beyond the arrays are left untouched, matching the previous
    /// `where index < ...count` loops at each call site.
    static func update(_ control: UISegmentedControl, labels: [String], identifiers: [String]) {
        let views = segmentViews(in: control)
        for (index, view) in views.enumerated() where index < labels.count && index < identifiers.count {
            view.accessibilityLabel = labels[index]
            view.accessibilityIdentifier = identifiers[index]
        }
    }
}
