//
//  ChromeScrollProxy.swift
//  OuterView
//

import UIKit

/// Per-page scroll delegate feeding the chrome state machine. Attaching keeps
/// any pre-existing delegate as a pass-through so hosted scroll behavior never
/// breaks; title and progress keep flowing through the page's snapshot
/// observations, not through this delegate.
@MainActor
final class ChromeScrollProxy: NSObject, UIScrollViewDelegate {
    /// Net offset change since the previous did-scroll call. Positive means
    /// the user scrolled down.
    nonisolated static func delta(previousY: CGFloat?, currentY: CGFloat) -> CGFloat {
        guard let previousY else { return 0 }
        return currentY - previousY
    }

    /// Only finger-driven movement (drag or its fling) may move chrome.
    /// Page-load anchoring, restored offsets, and layout jumps change
    /// `contentOffset` too and would otherwise hide chrome at launch.
    nonisolated static func isUserDriven(isDragging: Bool, isDecelerating: Bool) -> Bool {
        isDragging || isDecelerating
    }

    /// Resting top boundary: the less-negative of the scroll view's real
    /// inset and the chrome's computed inset, so a rubber-band settle toward
    /// either one is never treated as downward reading scroll.
    nonisolated static func topBound(adjustedTop: CGFloat, chromeTop: CGFloat) -> CGFloat {
        -min(adjustedTop, chromeTop)
    }

    /// Called once per user-driven `scrollViewDidScroll` with the net change.
    var onScrollDelta: ((CGFloat) -> Void)?

    /// Called when the user's finger starts dragging the page.
    var onDragBegan: (() -> Void)?

    /// Called when scrolling finishes settling (dragging ended without deceleration or deceleration finished).
    var onScrollSettled: (() -> Void)?

    /// Returns the active top chrome obstruction inset (e.g. 84 or 128 pt on
    /// regular width) so top-of-content boundary checks match resting scroll.
    var topInsetProvider: (() -> CGFloat)?

    /// Previous delegate kept for pass-through of the scroll callbacks.
    weak var forwardedDelegate: any UIScrollViewDelegate?

    /// While true, programmatic offset jumps resync the baseline and still
    /// reach the previous delegate without moving chrome.
    var suppressDeltas = false

    private var lastOffsetY: CGFloat?

    func attach(to scrollView: UIScrollView) {
        if scrollView.delegate !== self {
            forwardedDelegate = scrollView.delegate
            scrollView.delegate = self
        }
        lastOffsetY = scrollView.contentOffset.y
    }

    func detach(from scrollView: UIScrollView) {
        if scrollView.delegate === self {
            scrollView.delegate = forwardedDelegate
        }
        forwardedDelegate = nil
        lastOffsetY = nil
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        lastOffsetY = scrollView.contentOffset.y
        onDragBegan?()
        forwardedDelegate?.scrollViewWillBeginDragging?(scrollView)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let currentY = scrollView.contentOffset.y
        let change = Self.delta(previousY: lastOffsetY, currentY: currentY)
        lastOffsetY = currentY
        forwardedDelegate?.scrollViewDidScroll?(scrollView)
        guard !suppressDeltas else { return }
        if Self.isUserDriven(isDragging: scrollView.isDragging, isDecelerating: scrollView.isDecelerating) {
            let topBound = Self.topBound(
                adjustedTop: scrollView.adjustedContentInset.top,
                chromeTop: topInsetProvider?() ?? 0
            )
            if currentY <= topBound {
                // At the top of content (or during rubber-band overscroll), ensure chrome
                // expands and never treat the bounce-back toward resting top as downward scrolling.
                if change < 0 {
                    onScrollDelta?(change)
                } else if currentY == topBound, change == 0 {
                    onScrollDelta?(-ChromeStateController.revealThreshold)
                }
            } else {
                onScrollDelta?(change)
            }
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        forwardedDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        if !decelerate {
            onScrollSettled?()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        forwardedDelegate?.scrollViewDidEndDecelerating?(scrollView)
        onScrollSettled?()
    }
}
