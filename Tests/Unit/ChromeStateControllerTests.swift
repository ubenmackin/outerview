//
//  ChromeStateControllerTests.swift
//  OuterView
//

import CoreGraphics
@testable import OuterView
import XCTest

/// Exhaustive table of input sequences → final rail/pill for every branch of
/// the chrome state machine, plus changed-fields-only command probes,
/// idempotence probes, and value-semantics checks.
final class ChromeStateControllerTests: XCTestCase {
    private struct MatrixCase: Sendable {
        let label: String
        let inputs: [ChromeInput]
        let rail: RailState
        let pill: PillState
    }

    private static func down(_ delta: CGFloat) -> ChromeInput {
        .scroll(offsetDelta: delta)
    }

    private static func up(_ delta: CGFloat) -> ChromeInput {
        .scroll(offsetDelta: -delta)
    }

    private static let matrix: [MatrixCase] = [
        // Initial state
        MatrixCase(
            label: "no input starts at visible rail and expanded pill",
            inputs: [],
            rail: .visible,
            pill: .expanded
        ),
        // Scroll down
        MatrixCase(
            label: "7 pt of down-scroll keeps the rail",
            inputs: [down(7)],
            rail: .visible,
            pill: .expanded
        ),
        MatrixCase(
            label: "accumulated 8 pt hides the rail only",
            inputs: [down(4), down(4)],
            rail: .hidden,
            pill: .expanded
        ),
        MatrixCase(
            label: "rail hides before the 24 pt threshold",
            inputs: [down(23.9)],
            rail: .hidden,
            pill: .expanded
        ),
        MatrixCase(
            label: "exactly 24 pt minifies the pill",
            inputs: [down(24)],
            rail: .hidden,
            pill: .minified
        ),
        MatrixCase(
            label: "accumulator minifies across separate scrolls",
            inputs: [down(8), down(8), down(8)],
            rail: .hidden,
            pill: .minified
        ),
        // Scroll up
        MatrixCase(
            label: "small up-scroll below the reveal threshold keeps chrome away",
            inputs: [down(30), up(1)],
            rail: .hidden,
            pill: .minified
        ),
        MatrixCase(
            label: "up-scroll at the reveal threshold restores rail and pill",
            inputs: [down(30), up(32)],
            rail: .visible,
            pill: .expanded
        ),
        MatrixCase(
            label: "up-scroll reveal accumulates across separate scrolls",
            inputs: [down(30), up(16), up(16)],
            rail: .visible,
            pill: .expanded
        ),
        MatrixCase(
            label: "a down-scroll resets the reveal accumulator",
            inputs: [down(30), up(20), down(1), up(20)],
            rail: .hidden,
            pill: .minified
        ),
        // Drag start
        MatrixCase(
            label: "dragBegan at rest keeps visible chrome",
            inputs: [.dragBegan],
            rail: .visible,
            pill: .expanded
        ),
        MatrixCase(
            label: "dragBegan leaves a minified pill alone",
            inputs: [down(30), up(32), down(24), .dragBegan],
            rail: .hidden,
            pill: .minified
        ),
        MatrixCase(
            label: "dragBegan after reveal keeps the rail visible",
            inputs: [down(30), up(32), .dragBegan, up(10), .dragBegan],
            rail: .visible,
            pill: .expanded
        ),
        MatrixCase(
            label: "dragBegan while editing is a no-op",
            inputs: [.editBegan, .dragBegan],
            rail: .hidden,
            pill: .editing
        ),
        // Rail menu tapped
        MatrixCase(
            label: "railMenuTapped when minified restores rail and expands pill",
            inputs: [down(30), .railMenuTapped],
            rail: .visible,
            pill: .expanded
        ),
        MatrixCase(
            label: "railMenuTapped while expanded is idempotent",
            inputs: [.railMenuTapped],
            rail: .visible,
            pill: .expanded
        ),
        MatrixCase(
            label: "down-scroll after railMenuTapped hides rail and minifies pill again",
            inputs: [down(30), .railMenuTapped, down(24)],
            rail: .hidden,
            pill: .minified
        ),
        MatrixCase(
            label: "up-scroll at rest changes nothing",
            inputs: [up(3)],
            rail: .visible,
            pill: .expanded
        ),
        MatrixCase(
            label: "up-scroll resets the accumulator",
            inputs: [down(20), up(1), down(5)],
            rail: .hidden,
            pill: .expanded
        ),
        MatrixCase(
            label: "post-reset accumulation minifies again",
            inputs: [down(20), up(1), down(24)],
            rail: .hidden,
            pill: .minified
        ),
        // Editing
        MatrixCase(
            label: "editBegan hides rail and opens the editing pill",
            inputs: [.editBegan],
            rail: .hidden,
            pill: .editing
        ),
        MatrixCase(
            label: "editBegan resets the accumulator",
            inputs: [down(30), .editBegan, down(10)],
            rail: .hidden,
            pill: .editing
        ),
        MatrixCase(
            label: "cancelling the edit restores chrome",
            inputs: [.editBegan, .editEnded(submitted: false)],
            rail: .visible,
            pill: .expanded
        ),
        MatrixCase(
            label: "submitting the edit minifies the pill",
            inputs: [.editBegan, .editEnded(submitted: true)],
            rail: .visible,
            pill: .minified
        ),
        // Rail grabbing (pill unchanged)
        MatrixCase(
            label: "railGrabbed shows the rail without touching a minified pill",
            inputs: [down(30), .railGrabbed],
            rail: .visible,
            pill: .minified
        ),
        MatrixCase(
            label: "railGrabbed before the threshold keeps the pill expanded",
            inputs: [down(10), .railGrabbed],
            rail: .visible,
            pill: .expanded
        ),
        MatrixCase(
            label: "railGrabbed at rest is a no-op",
            inputs: [.railGrabbed],
            rail: .visible,
            pill: .expanded
        ),
        // Resuming browsing
        MatrixCase(
            label: "browsingResumed restores the chrome at rest",
            inputs: [down(30), .browsingResumed],
            rail: .visible,
            pill: .expanded
        ),
        MatrixCase(
            label: "browsingResumed resets the accumulator",
            inputs: [down(30), .browsingResumed, down(10)],
            rail: .hidden,
            pill: .expanded
        ),
        MatrixCase(
            label: "browsingResumed at rest is a no-op",
            inputs: [.browsingResumed],
            rail: .visible,
            pill: .expanded
        ),
        // Idempotence probes
        MatrixCase(
            label: "repeat same-direction scrolls after minify leave the state",
            inputs: [down(24), down(20), down(30)],
            rail: .hidden,
            pill: .minified
        ),
        MatrixCase(
            label: "repeat same-direction scrolls below the threshold keep the pill expanded",
            inputs: [down(3), down(3), down(3)],
            rail: .hidden,
            pill: .expanded
        ),
        MatrixCase(
            label: "repeat editBegan leaves the state",
            inputs: [.editBegan, .editBegan],
            rail: .hidden,
            pill: .editing
        ),
        MatrixCase(
            label: "repeat submitted editEnded leaves the state",
            inputs: [.editBegan, .editEnded(submitted: true), .editEnded(submitted: true)],
            rail: .visible,
            pill: .minified
        ),
        MatrixCase(
            label: "repeat cancelled editEnded leaves the state",
            inputs: [.editBegan, .editEnded(submitted: false), .editEnded(submitted: false)],
            rail: .visible,
            pill: .expanded
        ),
        MatrixCase(
            label: "repeat railGrabbed after minify leaves the pill minified",
            inputs: [down(30), .railGrabbed, .railGrabbed],
            rail: .visible,
            pill: .minified
        ),
        MatrixCase(
            label: "repeat browsingResumed leaves the state",
            inputs: [down(30), .browsingResumed, .browsingResumed],
            rail: .visible,
            pill: .expanded
        ),
        // Scrolling never exits editing; only editEnded may leave it.
        MatrixCase(
            label: "down-scroll while editing is a no-op",
            inputs: [.editBegan, down(24)],
            rail: .hidden,
            pill: .editing
        ),
        MatrixCase(
            label: "up-scroll while editing is a no-op",
            inputs: [.editBegan, up(5)],
            rail: .hidden,
            pill: .editing
        ),
        MatrixCase(
            label: "accumulated scroll while editing stays inert after edit ends",
            inputs: [.editBegan, down(24), .editEnded(submitted: false), down(10)],
            rail: .hidden,
            pill: .expanded
        )
    ]

    private func finalState(after inputs: [ChromeInput]) -> ChromeState {
        var controller = ChromeStateController()
        for input in inputs {
            _ = controller.handle(input)
        }
        return controller.state
    }

    private func finalCommands(after inputs: [ChromeInput]) -> ChromeCommands {
        var controller = ChromeStateController()
        var result = ChromeCommands.noChange
        for input in inputs {
            result = controller.handle(input)
        }
        return result
    }

    func testStateMatrixMatchesLockedRules() {
        for row in Self.matrix {
            XCTAssertEqual(
                finalState(after: row.inputs),
                ChromeState(rail: row.rail, pill: row.pill),
                row.label
            )
        }
    }

    func testCommandsCarryOnlyChangedFields() {
        XCTAssertEqual(finalCommands(after: [Self.down(7)]), .noChange)
        XCTAssertEqual(finalCommands(after: [Self.down(8)]), ChromeCommands(rail: .hidden, pill: nil))
        XCTAssertEqual(finalCommands(after: [Self.down(30)]), ChromeCommands(rail: .hidden, pill: .minified))
        XCTAssertEqual(finalCommands(after: [Self.down(30), Self.down(5)]), .noChange)

        XCTAssertEqual(
            finalCommands(after: [Self.down(24), Self.up(32)]),
            ChromeCommands(rail: .visible, pill: .expanded)
        )
        XCTAssertEqual(finalCommands(after: [Self.down(24), Self.up(31)]), .noChange)
        XCTAssertEqual(
            finalCommands(after: [Self.down(24), Self.up(31), Self.up(1)]),
            ChromeCommands(rail: .visible, pill: .expanded)
        )
        XCTAssertEqual(
            finalCommands(after: [Self.down(24), Self.up(32), Self.down(7)]),
            .noChange
        )
        XCTAssertEqual(
            finalCommands(after: [Self.down(24), Self.up(32), Self.down(8)]),
            ChromeCommands(rail: .hidden, pill: nil)
        )
        XCTAssertEqual(finalCommands(after: [Self.down(30), Self.up(32), Self.up(5)]), .noChange)
        XCTAssertEqual(finalCommands(after: [Self.down(30), Self.up(32), Self.up(16)]), .noChange)
        XCTAssertEqual(
            finalCommands(after: [Self.down(30), Self.up(32), Self.down(8)]),
            ChromeCommands(rail: .hidden, pill: nil)
        )
        XCTAssertEqual(
            finalCommands(after: [Self.down(30), Self.up(32), Self.down(8), Self.up(31)]),
            .noChange
        )
        XCTAssertEqual(
            finalState(after: [Self.down(30), Self.up(32), Self.down(8)]),
            ChromeState(rail: .hidden, pill: .expanded)
        )
        XCTAssertEqual(
            finalState(after: [Self.down(30), Self.up(32), Self.down(8), Self.up(31)]),
            ChromeState(rail: .hidden, pill: .expanded)
        )
        XCTAssertEqual(finalCommands(after: [Self.up(1)]), .noChange)
        XCTAssertEqual(finalCommands(after: [Self.up(40)]), .noChange)

        XCTAssertEqual(finalCommands(after: [.dragBegan]), .noChange)
        XCTAssertEqual(finalCommands(after: [.dragBegan, .dragBegan]), .noChange)
        XCTAssertEqual(finalCommands(after: [.editBegan, .dragBegan]), .noChange)
        XCTAssertEqual(finalCommands(after: [Self.down(30), Self.up(32), .dragBegan]), .noChange)
        XCTAssertEqual(
            finalCommands(after: [Self.down(30), .railMenuTapped]),
            ChromeCommands(rail: .visible, pill: .expanded)
        )

        XCTAssertEqual(finalCommands(after: [.editBegan]), ChromeCommands(rail: .hidden, pill: .editing))
        XCTAssertEqual(
            finalCommands(after: [Self.down(30), .editBegan]),
            ChromeCommands(rail: nil, pill: .editing)
        )
        XCTAssertEqual(finalCommands(after: [.editBegan, .editBegan]), .noChange)
        XCTAssertEqual(finalCommands(after: [.editBegan, Self.down(24)]), .noChange)
        XCTAssertEqual(finalCommands(after: [.editBegan, Self.up(5)]), .noChange)

        XCTAssertEqual(
            finalCommands(after: [.editBegan, .editEnded(submitted: true)]),
            ChromeCommands(rail: .visible, pill: .minified)
        )
        XCTAssertEqual(
            finalCommands(after: [.editBegan, .editEnded(submitted: true), .editEnded(submitted: true)]),
            .noChange
        )
        XCTAssertEqual(
            finalCommands(after: [.editBegan, .editEnded(submitted: false)]),
            ChromeCommands(rail: .visible, pill: .expanded)
        )

        XCTAssertEqual(finalCommands(after: [.railGrabbed]), .noChange)
        XCTAssertEqual(
            finalCommands(after: [Self.down(30), .railGrabbed]),
            ChromeCommands(rail: .visible, pill: nil)
        )
        XCTAssertEqual(
            finalCommands(after: [Self.down(30), .railGrabbed, .railGrabbed]),
            .noChange
        )

        XCTAssertEqual(
            finalCommands(after: [Self.down(30), .browsingResumed]),
            ChromeCommands(rail: .visible, pill: .expanded)
        )
        XCTAssertEqual(
            finalCommands(after: [Self.down(30), .browsingResumed, .browsingResumed]),
            .noChange
        )
    }

    func testCopyIsIndependentOfOriginal() {
        var controller = ChromeStateController()
        let copy = controller
        _ = controller.handle(Self.down(30))
        XCTAssertEqual(copy.state, ChromeState(rail: .visible, pill: .expanded))
        XCTAssertEqual(controller.state, ChromeState(rail: .hidden, pill: .minified))
    }
}
