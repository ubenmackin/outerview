//
//  ScrollFeedbackTests.swift
//  OuterView
//

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class ScrollFeedbackTests: XCTestCase {
    @MainActor
    private final class StubScrollView: UIScrollView {
        var stubDragging = false
        var stubDecelerating = false

        override var isDragging: Bool {
            stubDragging
        }

        override var isDecelerating: Bool {
            stubDecelerating
        }
    }

    @MainActor
    private final class ForwardingSpy: NSObject, UIScrollViewDelegate {
        var didScrollCount = 0
        func scrollViewDidScroll(_: UIScrollView) {
            didScrollCount += 1
        }
    }

    private func setOffsetY(_ offsetY: CGFloat, on scrollView: StubScrollView) {
        let delegate = scrollView.delegate
        scrollView.delegate = nil
        scrollView.contentOffset = CGPoint(x: 0, y: offsetY)
        scrollView.delegate = delegate
    }

    func testSuppressDefaultsFalse() {
        let proxy = ChromeScrollProxy()
        XCTAssertFalse(proxy.suppressDeltas)
    }

    func testSuppressedJumpsResyncWithoutCallback() {
        let proxy = ChromeScrollProxy()
        let scrollView = StubScrollView()
        setOffsetY(0, on: scrollView)
        proxy.attach(to: scrollView)
        scrollView.stubDragging = true
        var deltas: [CGFloat] = []
        proxy.onScrollDelta = { deltas.append($0) }

        proxy.suppressDeltas = true
        setOffsetY(100, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        XCTAssertTrue(deltas.isEmpty)

        proxy.suppressDeltas = false
        setOffsetY(110, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        XCTAssertEqual(deltas, [10])
    }

    func testForwardedDelegateStillReceivesWhileSuppressed() {
        let proxy = ChromeScrollProxy()
        let scrollView = StubScrollView()
        scrollView.contentOffset = CGPoint(x: 0, y: 0)
        let spy = ForwardingSpy()
        scrollView.delegate = spy
        proxy.attach(to: scrollView)
        spy.didScrollCount = 0
        scrollView.stubDragging = true
        var deltas: [CGFloat] = []
        proxy.onScrollDelta = { deltas.append($0) }

        proxy.suppressDeltas = true
        setOffsetY(60, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        XCTAssertTrue(deltas.isEmpty)
        XCTAssertEqual(spy.didScrollCount, 1)

        proxy.suppressDeltas = false
        setOffsetY(70, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        XCTAssertEqual(deltas, [10])
        XCTAssertEqual(spy.didScrollCount, 2)
    }

    func testNormalDragDeltasFlow() {
        let proxy = ChromeScrollProxy()
        let scrollView = StubScrollView()
        setOffsetY(0, on: scrollView)
        proxy.attach(to: scrollView)
        scrollView.stubDragging = true
        var deltas: [CGFloat] = []
        proxy.onScrollDelta = { deltas.append($0) }

        setOffsetY(10, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        setOffsetY(20, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        setOffsetY(15, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        setOffsetY(20, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        XCTAssertEqual(deltas, [10, 10, -5, 5])

        scrollView.stubDragging = false
        scrollView.stubDecelerating = false
        setOffsetY(40, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        XCTAssertEqual(deltas, [10, 10, -5, 5])

        scrollView.stubDecelerating = true
        setOffsetY(50, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        XCTAssertEqual(deltas, [10, 10, -5, 5, 10])
    }

    func testTopBounceRuleIntact() {
        let proxy = ChromeScrollProxy()
        let scrollView = StubScrollView()
        setOffsetY(0, on: scrollView)
        proxy.attach(to: scrollView)
        scrollView.stubDragging = true
        var deltas: [CGFloat] = []
        proxy.onScrollDelta = { deltas.append($0) }

        setOffsetY(-20, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        XCTAssertEqual(deltas, [-20])

        setOffsetY(-10, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        XCTAssertEqual(deltas, [-20])

        setOffsetY(0, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        XCTAssertEqual(deltas, [-20])

        proxy.scrollViewDidScroll(scrollView)
        XCTAssertEqual(deltas, [-20, -ChromeStateController.revealThreshold])
    }

    func testAttachSeedsLastOffsetY() {
        let proxy = ChromeScrollProxy()
        let scrollView = StubScrollView()
        setOffsetY(50, on: scrollView)
        proxy.attach(to: scrollView)
        scrollView.stubDragging = true
        var deltas: [CGFloat] = []
        proxy.onScrollDelta = { deltas.append($0) }

        setOffsetY(60, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        XCTAssertEqual(deltas, [10])
    }
}
