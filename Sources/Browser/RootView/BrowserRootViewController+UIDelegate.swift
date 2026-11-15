// RootView — Popup/tab plus JS-modal UIDelegate forwarding owner.

import UIKit
import WebKit

/// Lock-guarded single-take fallback; deinit and dismissal race, last take wins.
private final class DialogFallback: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@MainActor @Sendable () -> Void)?

    func set(_ handler: (@MainActor @Sendable () -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }

    func peek() -> (@MainActor @Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }

    func take() -> (@MainActor @Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        let next = handler
        handler = nil
        return next
    }
}

/// Alert controller that notifies when dismissed or torn down without an action tap,
/// guaranteeing `withCheckedContinuation` and WebKit completion handlers always resume.
@MainActor
final class DismissAwareAlertController: UIAlertController {
    /// Single-take fallback shared by dismissal and teardown; lock keeps takes exclusive.
    private nonisolated let fallback = DialogFallback()

    nonisolated var onFinishWithoutAction: (@MainActor @Sendable () -> Void)? {
        get { fallback.peek() }
        set { fallback.set(newValue) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            fireFallbackIfNeeded()
        }
    }

    func fireFallbackIfNeeded() {
        guard let handler = fallback.take() else { return }
        handler()
    }

    deinit {
        guard let handler = fallback.take() else { return }
        Task { @MainActor in
            handler()
        }
    }
}

@MainActor
private final class ContinuationGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }
}

extension BrowserRootViewController: WebPageUIDelegateHandler {
    func webPageController(
        _ controller: WebPageController,
        createWebViewWith configuration: WKWebViewConfiguration,
        for _: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        let isPrivate = controller.isPrivateTab
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        let record = TabRecord(isPrivate: isPrivate, groupId: isPrivate ? nil : overviewController.selectedGroupID, parentTabID: selectedTabID)
        let newPage = WebPageController(configuration: configuration)
        tabPool.create(id: record.id, isPrivate: isPrivate, page: newPage)

        let insertIndex: Int =
            if let selected = selectedTabID, let index = tabs.firstIndex(where: { $0.id == selected }) {
                index + 1
            } else {
                tabs.count
            }
        tabs.insert(record, at: insertIndex)

        do {
            try tabStore?.saveSession(tabs: tabs, selected: record.id)
        } catch {
            logPersistenceError(error, operation: "saveSession")
        }

        wirePage(newPage, for: record.id)
        selectTab(id: record.id)
        applyBrowsingResumed(animated: true)

        return newPage.webView
    }

    func webPageControllerDidClose(_ controller: WebPageController) {
        if let tab = tabs.first(where: { tab in tabPool.pages.first(where: { $0.id == tab.id })?.page === controller }) {
            closeTab(id: tab.id, replacementIfEmpty: nil)
        }
    }

    func webPageController(
        _: WebPageController,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async {
        await presentJSDialog(for: frame, defaultValue: ()) { alert, complete in
            alert.message = message
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                alert?.onFinishWithoutAction = nil
                complete(())
            })
        }
    }

    func webPageController(
        _: WebPageController,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        await presentJSDialog(for: frame, defaultValue: false) { alert, complete in
            alert.message = message
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak alert] _ in
                alert?.onFinishWithoutAction = nil
                complete(false)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                alert?.onFinishWithoutAction = nil
                complete(true)
            })
        }
    }

    func webPageController(
        _: WebPageController,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        await presentJSDialog(for: frame, defaultValue: nil as String?) { alert, complete in
            alert.message = prompt
            alert.addTextField { textField in
                textField.text = defaultText
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak alert] _ in
                alert?.onFinishWithoutAction = nil
                complete(nil)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                alert?.onFinishWithoutAction = nil
                complete(alert?.textFields?.first?.text ?? "")
            })
        }
    }

    private func presentJSDialog<Result: Sendable>(
        for frame: WKFrameInfo,
        defaultValue: Result,
        configure: (DismissAwareAlertController, @escaping @MainActor @Sendable (Result) -> Void) -> Void
    ) async -> Result {
        let host = frame.securityOrigin.host
        let title = host.isEmpty ? "JavaScript" : host
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result, Never>) in
            let gate = ContinuationGate<Result>(continuation)
            let resumeOnce: @MainActor @Sendable (Result) -> Void = { value in
                gate.resume(returning: value)
            }
            let alert = DismissAwareAlertController(title: title, message: nil, preferredStyle: .alert)
            configure(alert, resumeOnce)
            presentTopmost(alert) {
                resumeOnce(defaultValue)
            }
        }
    }

    private func presentTopmost(_ alert: DismissAwareAlertController, onDismiss: @escaping @MainActor @Sendable () -> Void) {
        var top: UIViewController = self
        while let presented = top.presentedViewController {
            // Do not attempt to present over a controller mid-transition; UIKit would drop
            // the alert silently and stall the JS continuation.
            if presented.isBeingDismissed || presented.isBeingPresented {
                onDismiss()
                return
            }
            top = presented
        }
        guard top.view.window != nil,
              !top.isBeingDismissed,
              !top.isBeingPresented,
              top.transitionCoordinator == nil,
              top.presentedViewController == nil
        else {
            onDismiss()
            return
        }
        alert.onFinishWithoutAction = onDismiss
        top.present(alert, animated: true)
        if alert.presentingViewController == nil {
            alert.fireFallbackIfNeeded()
        }
    }
}
