// WebPage --- WKUIDelegate dialogs plus link preview menus for web pages.

import Foundation
import os
import UIKit
import WebKit

// MARK: - WKUIDelegate

extension WebPageController: WKUIDelegate {
    func webView(
        _: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        uiDelegateHandler?.webPageController(
            self,
            createWebViewWith: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures
        )
    }

    func webViewDidClose(_: WKWebView) {
        uiDelegateHandler?.webPageControllerDidClose(self)
    }

    func webView(
        _: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor () -> Void
    ) {
        guard let handler = uiDelegateHandler else {
            completionHandler()
            return
        }
        Task {
            await handler.webPageController(self, runJavaScriptAlertPanelWithMessage: message, initiatedByFrame: frame)
            completionHandler()
        }
    }

    func webView(
        _: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        guard let handler = uiDelegateHandler else {
            completionHandler(false)
            return
        }
        Task {
            let result = await handler.webPageController(self, runJavaScriptConfirmPanelWithMessage: message, initiatedByFrame: frame)
            completionHandler(result)
        }
    }

    func webView(
        _: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (String?) -> Void
    ) {
        guard let handler = uiDelegateHandler else {
            completionHandler(nil)
            return
        }
        Task {
            let result = await handler.webPageController(self, runJavaScriptTextInputPanelWithPrompt: prompt, defaultText: defaultText, initiatedByFrame: frame)
            completionHandler(result)
        }
    }

    func webView(
        _: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping @MainActor (UIContextMenuConfiguration?) -> Void
    ) {
        guard contextActions != nil else {
            completionHandler(nil)
            return
        }
        // Resolving the JS payload happens asynchronously while the menu is
        // being assembled; an unknown element leaves WebKit's default menu up.
        Task { [weak self] in
            guard let self,
                  let actions = self.contextActions,
                  let kind = await self.contextElementKind(for: elementInfo)
            else {
                completionHandler(nil)
                return
            }
            let menu = ElementContextMenu.menu(for: kind, actions: actions)
            let previewProvider: UIContextMenuContentPreviewProvider? = switch kind {
            case let .link(url):
                { [weak self] in
                    guard let self else { return nil }
                    return LinkPreviewViewController(
                        url: url,
                        configuration: self.webView.configuration,
                        onOpen: { [weak self] targetURL in
                            self?.load(targetURL)
                        }
                    )
                }
            case .image:
                nil
            }
            completionHandler(
                UIContextMenuConfiguration(
                    identifier: nil,
                    previewProvider: previewProvider,
                    actionProvider: { _ in menu }
                )
            )
        }
    }

    func webView(
        _: WKWebView,
        contextMenuForElement elementInfo: WKContextMenuElementInfo,
        willCommitWithAnimator animator: UIContextMenuInteractionCommitAnimating
    ) {
        if let linkURL = elementInfo.linkURL {
            animator.addCompletion { [weak self] in
                self?.load(linkURL)
            }
        }
    }

    /// Resolves the long-pressed element to a context kind. Links are taken
    /// straight from the delegate's element info; anything else consults the
    /// DOM tracker, and an unknown target yields no menu (WebKit default).
    private func contextElementKind(for elementInfo: WKContextMenuElementInfo) async -> ElementContextKind? {
        if let linkURL = elementInfo.linkURL {
            return .link(url: linkURL)
        }
        guard let payload = await contextMenuPayload() else { return nil }
        let linkSource = payload["link"].flatMap {
            ElementContextMenu.absoluteURL(for: $0, baseURL: webView.url)
        }
        return ElementContextMenu.kind(
            linkURL: linkSource,
            imageURLString: payload["image"],
            baseURL: webView.url
        )
    }

    private func contextMenuPayload() async -> [String: String]? {
        do {
            let result = try await webView.evaluateJavaScript("window.__outerviewContextMenuPayload || null")
            return result as? [String: String]
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "WebPage")
                .error("contextMenuPayload failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
