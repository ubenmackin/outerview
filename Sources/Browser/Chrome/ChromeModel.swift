//
//  ChromeModel.swift
//  OuterView
//

import CoreGraphics

/// Visibility of the side rail in the right screen column.
enum RailState: Sendable, Equatable {
    case visible
    case hidden
}

/// Appearance of the address pill.
enum PillState: Sendable, Equatable {
    case expanded
    case minified
    case editing
}

/// The full chrome appearance at a point in time.
struct ChromeState: Sendable, Equatable {
    static let initial = ChromeState(rail: .visible, pill: .expanded)

    var rail: RailState
    var pill: PillState
}

/// Per-field change set; `nil` means the field kept its previous value and
/// the view layer must leave its layout untouched.
struct ChromeCommands: Sendable, Equatable {
    static let noChange = ChromeCommands()

    var rail: RailState?
    var pill: PillState?
}

/// Inputs feeding the chrome state machine. Scroll deltas are the change in
/// scroll view content offset since the previous did-scroll call, so positive
/// values mean the user scrolled down. `dragBegan` fires when the user's
/// finger starts moving the page, in either direction.
enum ChromeInput: Sendable, Equatable {
    case scroll(offsetDelta: CGFloat)
    case dragBegan
    case editBegan
    case editEnded(submitted: Bool)
    case railGrabbed
    case railMenuTapped
    case browsingResumed
}
