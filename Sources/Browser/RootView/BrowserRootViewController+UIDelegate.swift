// RootView — Popup/tab plus JS-modal UIDelegate forwarding owner.

import UIKit
import WebKit

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
        let host = frame.securityOrigin.host
        let title = host.isEmpty ? "JavaScript" : host
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume()
            })
            presentTopmost(alert) {
                continuation.resume()
            }
        }
    }

    func webPageController(
        _: WebPageController,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        let host = frame.securityOrigin.host
        let title = host.isEmpty ? "JavaScript" : host
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume(returning: true)
            })
            presentTopmost(alert) {
                continuation.resume(returning: false)
            }
        }
    }

    func webPageController(
        _: WebPageController,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        let host = frame.securityOrigin.host
        let title = host.isEmpty ? "JavaScript" : host
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: prompt, preferredStyle: .alert)
            alert.addTextField { textField in
                textField.text = defaultText
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: nil)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume(returning: alert.textFields?.first?.text ?? "")
            })
            presentTopmost(alert) {
                continuation.resume(returning: nil)
            }
        }
    }

    private func presentTopmost(_ alert: UIAlertController, onDismiss: @escaping @MainActor () -> Void) {
        var top: UIViewController = self
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        guard top.view.window != nil else {
            onDismiss()
            return
        }
        top.present(alert, animated: true)
    }
}
