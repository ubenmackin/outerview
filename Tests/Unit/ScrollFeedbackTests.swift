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

    func testTopBoundCalculation() {
        XCTAssertEqual(ChromeScrollProxy.topBound(adjustedTop: 128, chromeTop: 128), -128)
        XCTAssertEqual(ChromeScrollProxy.topBound(adjustedTop: 40, chromeTop: 128), -40)
        XCTAssertEqual(ChromeScrollProxy.topBound(adjustedTop: 128, chromeTop: 40), -40)
        XCTAssertEqual(ChromeScrollProxy.topBound(adjustedTop: 0, chromeTop: 0), 0)
    }

    func testRubberBandSettleEmitsNoPositiveDeltas() {
        let proxy = ChromeScrollProxy()
        let scrollView = StubScrollView()
        scrollView.contentInset = UIEdgeInsets(top: 40, left: 0, bottom: 0, right: 0)
        setOffsetY(-80, on: scrollView)
        proxy.attach(to: scrollView)
        proxy.topInsetProvider = { 128 }
        scrollView.stubDragging = true
        var deltas: [CGFloat] = []
        proxy.onScrollDelta = { deltas.append($0) }

        // Settle from -80 towards resting top (-40)
        setOffsetY(-60, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)
        setOffsetY(-40, on: scrollView)
        proxy.scrollViewDidScroll(scrollView)

        // All changes during rubber-band settle must be filtered out (no positive downward scroll deltas)
        XCTAssertTrue(deltas.filter { $0 > 0 }.isEmpty)
    }

    func testOnScrollSettledCallbacks() {
        let proxy = ChromeScrollProxy()
        let scrollView = StubScrollView()
        var settledCount = 0
        proxy.onScrollSettled = { settledCount += 1 }

        proxy.scrollViewDidEndDragging(scrollView, willDecelerate: true)
        XCTAssertEqual(settledCount, 0)

        proxy.scrollViewDidEndDragging(scrollView, willDecelerate: false)
        XCTAssertEqual(settledCount, 1)

        proxy.scrollViewDidEndDecelerating(scrollView)
        XCTAssertEqual(settledCount, 2)
    }
}
