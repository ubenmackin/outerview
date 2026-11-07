//
//  SegmentedAccessibility.swift
//  OuterView
//

import UIKit

/// Single owner of `UISegmentedControl` VoiceOver wiring.
/// Recursively resolves `UISegment` subviews in minX order, assigning pairwise
/// labels/identifiers for the library tab bar and tab-groups sheet pill.
@MainActor
enum SegmentedAccessibility {
    /// Private segment subviews backing `control`, ordered left-to-right.
    static func segmentViews(in control: UISegmentedControl) -> [UIView] {
        func findSegments(in parentView: UIView) -> [UIView] {
            var segments: [UIView] = []
            for child in parentView.subviews {
                if String(describing: type(of: child)).contains("Segment") {
                    segments.append(child)
                } else {
                    segments.append(contentsOf: findSegments(in: child))
                }
            }
            return segments
        }
        return findSegments(in: control).sorted { $0.frame.minX < $1.frame.minX }
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
