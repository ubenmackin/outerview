//
//  ChromeStateController.swift
//  OuterView
//

import CoreGraphics

/// Pure, value-semantic owner of rail × pill visibility. The 8 pt rail-hide
/// and 24 pt pill-minify share one down-scroll accumulator; the 32 pt reveal
/// uses the up-scroll accumulator. Reports only the chrome fields that
/// actually changed; all layout and animation stays in the view layer.
struct ChromeStateController: Sendable {
    /// Accumulated down-scroll distance, in points, required to hide the
    /// rail. Keeps small drifts and finger jitter from collapsing it.
    static let hideThreshold: CGFloat = 8

    /// Accumulated down-scroll distance, in points, required to minify the
    /// pill.
    static let minifyThreshold: CGFloat = 24

    /// Accumulated up-scroll distance, in points, required to bring the
    /// chrome back. Keeps finger jitter and small bounces from popping it.
    static let revealThreshold: CGFloat = 32

    private(set) var state: ChromeState = .initial

    /// Cumulative downward scroll offset since the last reset (up-scroll,
    /// editBegan, or browsingResumed).
    private var downOffsetAccumulator: CGFloat = 0

    /// Cumulative upward scroll offset since the last down-scroll or reset.
    private var upOffsetAccumulator: CGFloat = 0

    init() {}

    @discardableResult
    mutating func handle(_ input: ChromeInput) -> ChromeCommands {
        switch input {
        case let .scroll(offsetDelta):
            handleScroll(offsetDelta)
        case .dragBegan:
            handleDragBegan()
        case .editBegan:
            handleEditBegan()
        case let .editEnded(submitted):
            handleEditEnded(submitted: submitted)
        case .railGrabbed:
            handleRailGrabbed()
        case .railMenuTapped:
            handleRailMenuTapped()
        case .browsingResumed:
            handleBrowsingResumed()
        }
    }

    private mutating func handleScroll(_ offsetDelta: CGFloat) -> ChromeCommands {
        // Scrolling never exits editing; only editEnded may leave it so the
        // editor keeps first responder until an explicit cancel or submit.
        guard state.pill != .editing else { return .noChange }
        var commands = ChromeCommands()
        // A zero delta is neither an up- nor down-scroll and must not
        // touch the accumulator.
        if offsetDelta > 0 {
            applyDownScroll(offsetDelta, commands: &commands)
        } else if offsetDelta < 0 {
            applyUpScroll(-offsetDelta, commands: &commands)
        }
        return commands
    }

    private mutating func handleDragBegan() -> ChromeCommands {
        guard state.pill != .editing else { return .noChange }
        // Finger-down never hides chrome on its own; it only resets the
        // gesture accumulators for the fresh drag.
        downOffsetAccumulator = 0
        upOffsetAccumulator = 0
        return .noChange
    }

    private mutating func applyDownScroll(_ offsetDelta: CGFloat, commands: inout ChromeCommands) {
        downOffsetAccumulator += offsetDelta
        upOffsetAccumulator = 0
        if downOffsetAccumulator >= Self.hideThreshold, state.rail != .hidden {
            state.rail = .hidden
            commands.rail = .hidden
        }
        if downOffsetAccumulator >= Self.minifyThreshold, state.pill != .minified {
            state.pill = .minified
            commands.pill = .minified
        }
    }

    private mutating func applyUpScroll(_ distance: CGFloat, commands: inout ChromeCommands) {
        downOffsetAccumulator = 0
        upOffsetAccumulator += distance
        guard upOffsetAccumulator >= Self.revealThreshold else { return }
        upOffsetAccumulator = 0
        if state.rail != .visible {
            state.rail = .visible
            commands.rail = .visible
        }
        if state.pill != .expanded {
            state.pill = .expanded
            commands.pill = .expanded
        }
    }

    private mutating func handleEditBegan() -> ChromeCommands {
        var commands = ChromeCommands()
        downOffsetAccumulator = 0
        upOffsetAccumulator = 0
        if state.pill != .editing {
            state.pill = .editing
            commands.pill = .editing
        }
        if state.rail != .hidden {
            state.rail = .hidden
            commands.rail = .hidden
        }
        return commands
    }

    private mutating func handleEditEnded(submitted _: Bool) -> ChromeCommands {
        var commands = ChromeCommands()
        // Submitting or cancelling both restore the full pill; only a real
        // down-scroll may minify it (Safari parity: large bar until scroll).
        if state.pill != .expanded {
            state.pill = .expanded
            commands.pill = .expanded
        }
        if state.rail != .visible {
            state.rail = .visible
            commands.rail = .visible
        }
        return commands
    }

    private mutating func handleRailGrabbed() -> ChromeCommands {
        var commands = ChromeCommands()
        // Only the rail reacts; the pill keeps its current state.
        if state.rail != .visible {
            state.rail = .visible
            commands.rail = .visible
        }
        return commands
    }

    private mutating func handleRailMenuTapped() -> ChromeCommands {
        guard state.pill != .editing else { return .noChange }
        var commands = ChromeCommands()
        downOffsetAccumulator = 0
        upOffsetAccumulator = 0
        if state.rail != .visible {
            state.rail = .visible
            commands.rail = .visible
        }
        if state.pill != .expanded {
            state.pill = .expanded
            commands.pill = .expanded
        }
        return commands
    }

    private mutating func handleBrowsingResumed() -> ChromeCommands {
        var commands = ChromeCommands()
        downOffsetAccumulator = 0
        upOffsetAccumulator = 0
        if state.rail != .visible {
            state.rail = .visible
            commands.rail = .visible
        }
        if state.pill != .expanded {
            state.pill = .expanded
            commands.pill = .expanded
        }
        return commands
    }
}
