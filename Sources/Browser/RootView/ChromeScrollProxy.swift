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

    /// Called once per user-driven `scrollViewDidScroll` with the net change.
    var onScrollDelta: ((CGFloat) -> Void)?

    /// Called when the user's finger starts dragging the page.
    var onDragBegan: (() -> Void)?

    /// Previous delegate kept for pass-through of the scroll callbacks.
    weak var forwardedDelegate: any UIScrollViewDelegate?

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
        if Self.isUserDriven(isDragging: scrollView.isDragging, isDecelerating: scrollView.isDecelerating) {
            if currentY <= 0 {
                // At the top of content (or during rubber-band overscroll), ensure chrome
                // expands and never treat the bounce-back toward 0 as downward scrolling.
                if change < 0 {
                    onScrollDelta?(change)
                } else if currentY == 0, change == 0 {
                    onScrollDelta?(-ChromeStateController.revealThreshold)
                }
            } else {
                onScrollDelta?(change)
            }
        }
        forwardedDelegate?.scrollViewDidScroll?(scrollView)
    }
}
