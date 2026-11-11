// RootView — Left-edge child-tab close gesture owner.

import UIKit

/// Pure gate for the left-edge child-tab close. `parentResolved` requires the
/// selected record's `parentTabID` to be non-nil, not self, and present in the
/// live tab list; every other input is live browsing state at touch time.
enum EdgeClosePolicy: Sendable {
    nonisolated static func canBegin(
        canGoBack: Bool,
        parentResolved: Bool,
        isEditingAddress: Bool,
        isFindActive: Bool,
        isOverviewVisible: Bool,
        isStartPageShown: Bool,
        isErrorVisible: Bool,
        pillSessionActive: Bool
    ) -> Bool {
        !canGoBack
            && parentResolved
            && !isEditingAddress
            && !isFindActive
            && !isOverviewVisible
            && !isStartPageShown
            && !isErrorVisible
            && !pillSessionActive
    }
}

/// One left-edge close drag; mirrors `HorizontalSwitchSession` so
/// interruption, commit, and cancel behave the same way.
@MainActor
final class EdgeCloseSession {
    let originID: UUID
    let parentID: UUID
    let outgoingSnapshot: UIView
    var incomingView: UIView?
    var didResolveTarget = false
    /// Set once finish starts a commit animator; interruption then keeps selection.
    var didCommit = false

    init(originID: UUID, parentID: UUID, outgoingSnapshot: UIView) {
        self.originID = originID
        self.parentID = parentID
        self.outgoingSnapshot = outgoingSnapshot
    }
}

extension BrowserRootViewController {
    // MARK: - Edge close

    func installEdgeCloseGesture() {
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgeClosePan(_:)))
        gesture.edges = .left
        gesture.delegate = self
        contentContainer.addGestureRecognizer(gesture)
    }

    @objc private func handleEdgeClosePan(_ pan: UIScreenEdgePanGestureRecognizer) {
        switch pan.state {
        case .began:
            interruptEdgeCloseIfNeeded()
            beginEdgeClose()
        case .changed:
            updateEdgeClose(with: pan)
        case .ended:
            finishEdgeClose(with: pan, cancelled: false)
        case .cancelled, .failed:
            finishEdgeClose(with: pan, cancelled: true)
        default:
            break
        }
    }

    /// Parent id only when lineage is intact: non-nil, not self, and still
    /// present in `tabs`. A closed parent yields nil so the gesture stays inert.
    private func edgeCloseParentID(selectedID: UUID) -> UUID? {
        guard let record = tabs.first(where: { $0.id == selectedID }),
              let parentID = record.parentTabID,
              parentID != selectedID,
              tabs.contains(where: { $0.id == parentID })
        else { return nil }
        return parentID
    }

    /// Restart mid-gesture: silence the animator, drop the views, and restore
    /// the origin only when no commit had started.
    private func interruptEdgeCloseIfNeeded() {
        edgeCloseAnimator?.stopAnimation(true)
        edgeCloseAnimator = nil
        guard let existing = edgeCloseSession else { return }
        existing.outgoingSnapshot.removeFromSuperview()
        existing.incomingView?.transform = .identity
        if !existing.didCommit, selectedTabID != existing.originID {
            selectTab(id: existing.originID)
        }
        edgeCloseSession = nil
    }

    private func beginEdgeClose() {
        guard let selected = selectedTabID, let page = peekActivePage() else { return }
        let parentID = edgeCloseParentID(selectedID: selected)
        let snapshot = page.snapshot
        guard EdgeClosePolicy.canBegin(
            canGoBack: snapshot.canGoBack,
            parentResolved: parentID != nil,
            isEditingAddress: isEditingAddress,
            isFindActive: isFindActive,
            isOverviewVisible: isOverviewVisible,
            isStartPageShown: shouldShowStartPage(for: selected, snapshot: snapshot),
            isErrorVisible: !errorContainer.isHidden,
            pillSessionActive: horizontalSwitchSession != nil || edgeCloseSession != nil
        ), let parentID else { return }
        let width = contentContainer.bounds.width
        guard width > 0, let outgoing = contentContainer.snapshotView(afterScreenUpdates: false) else { return }
        outgoing.frame = contentContainer.bounds
        outgoing.transform = .identity
        contentContainer.addSubview(outgoing)
        edgeCloseSession = EdgeCloseSession(originID: selected, parentID: parentID, outgoingSnapshot: outgoing)
    }

    private func updateEdgeClose(with pan: UIScreenEdgePanGestureRecognizer) {
        guard let session = edgeCloseSession else { return }
        let width = contentContainer.bounds.width
        guard width > 0 else { return }
        let clamped = max(-width, min(width, pan.translation(in: contentContainer).x))
        if !session.didResolveTarget {
            guard clamped != 0 else { return }
            session.didResolveTarget = true
            // displaySelectedTab clears the snapshot; re-add it on top.
            selectTab(id: session.parentID)
            session.outgoingSnapshot.frame = contentContainer.bounds
            if session.outgoingSnapshot.superview !== contentContainer {
                contentContainer.addSubview(session.outgoingSnapshot)
            } else {
                contentContainer.bringSubviewToFront(session.outgoingSnapshot)
            }
            session.incomingView = currentHorizontalIncomingView()
        }
        // Target stays locked after first resolve; reversal only mirrors the
        // drag against the parent, never re-resolves.
        session.outgoingSnapshot.transform = CGAffineTransform(translationX: clamped, y: 0)
        session.incomingView?.transform = CGAffineTransform(translationX: clamped - width, y: 0)
    }

    private func finishEdgeClose(with pan: UIScreenEdgePanGestureRecognizer, cancelled: Bool) {
        guard let session = edgeCloseSession else { return }
        guard session.didResolveTarget else {
            // Drag never left the edge: no settle motion and no selection churn.
            session.outgoingSnapshot.transform = .identity
            session.incomingView?.transform = .identity
            session.outgoingSnapshot.removeFromSuperview()
            edgeCloseSession = nil
            return
        }
        let width = contentContainer.bounds.width
        let clamped = max(-width, min(width, pan.translation(in: contentContainer).x))
        let velocity = pan.velocity(in: contentContainer).x
        let commit = !cancelled && AddressBarView.shouldCommitHorizontal(
            translationX: clamped,
            width: width,
            velocityX: velocity,
            direction: .right
        )
        if commit {
            commitEdgeClose(session: session, width: width, clamped: clamped, velocity: velocity)
        } else {
            cancelEdgeClose(session: session, width: width, clamped: clamped, velocity: velocity)
        }
    }

    /// Parent is selected at resolve time, so closing never touches selection;
    /// the settle animator only finishes the visual slide off screen.
    private func commitEdgeClose(session: EdgeCloseSession, width: CGFloat, clamped: CGFloat, velocity: CGFloat) {
        session.didCommit = true
        closeTab(id: session.originID, replacementIfEmpty: nil)
        let outgoing = session.outgoingSnapshot
        let incoming = session.incomingView
        let duration = AddressBarView.settleDuration(remaining: abs(width - clamped), velocity: velocity)
        let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
            outgoing.transform = CGAffineTransform(translationX: width, y: 0)
            incoming?.transform = .identity
        }
        edgeCloseAnimator = animator
        animator.addCompletion { [weak self, weak animator] _ in
            outgoing.removeFromSuperview()
            incoming?.transform = .identity
            guard let self else { return }
            if self.edgeCloseSession === session {
                self.edgeCloseSession = nil
            }
            if self.edgeCloseAnimator === animator {
                self.edgeCloseAnimator = nil
            }
        }
        animator.startAnimation()
    }

    private func cancelEdgeClose(session: EdgeCloseSession, width: CGFloat, clamped: CGFloat, velocity: CGFloat) {
        let outgoing = session.outgoingSnapshot
        let incoming = session.incomingView
        let originID = session.originID
        let duration = AddressBarView.settleDuration(remaining: abs(clamped), velocity: velocity)
        let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
            outgoing.transform = .identity
            incoming?.transform = CGAffineTransform(translationX: -width, y: 0)
        }
        edgeCloseAnimator = animator
        animator.addCompletion { [weak self, weak animator] _ in
            outgoing.removeFromSuperview()
            incoming?.transform = .identity
            guard let self else { return }
            if self.edgeCloseSession === session {
                self.edgeCloseSession = nil
            }
            if self.edgeCloseAnimator === animator {
                self.edgeCloseAnimator = nil
            }
            if self.selectedTabID != originID {
                self.selectTab(id: originID)
            }
        }
        animator.startAnimation()
    }
}

extension BrowserRootViewController: UIGestureRecognizerDelegate {
    /// Touch-time gate re-evaluated from live state; any failed condition
    /// yields to WebKit's native edge swipe (or nothing) — never closes.
    func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        guard let selected = selectedTabID, let page = peekActivePage() else { return false }
        let snapshot = page.snapshot
        let parentResolved = edgeCloseParentID(selectedID: selected) != nil
        return EdgeClosePolicy.canBegin(
            canGoBack: snapshot.canGoBack,
            parentResolved: parentResolved,
            isEditingAddress: isEditingAddress,
            isFindActive: isFindActive,
            isOverviewVisible: isOverviewVisible,
            isStartPageShown: shouldShowStartPage(for: selected, snapshot: snapshot),
            isErrorVisible: !errorContainer.isHidden,
            pillSessionActive: horizontalSwitchSession != nil || edgeCloseSession != nil
        )
    }
}
