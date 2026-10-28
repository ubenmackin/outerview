//
//  WebPageController.swift
//  OuterView
//

import UIKit
import WebKit

/// Externally visible state of one web page, published on every change.
/// `isSecure` requires an https scheme and no denied server-trust challenge
/// in the page's session.
struct WebPageSnapshot: Sendable, Equatable {
    var url: URL?
    var title: String?
    var progress: Double
    var canGoBack: Bool
    var canGoForward: Bool
    var isSecure: Bool
    var lastError: String?

    var isLoading: Bool {
        url != nil && progress < 1 && lastError == nil
    }

    static func isSecure(url: URL?, hasFailedServerTrustChallenge: Bool) -> Bool {
        guard !hasFailedServerTrustChallenge else { return false }
        return url?.scheme?.lowercased() == "https"
    }

    static func make(
        url: URL?,
        title: String?,
        progress: Double,
        canGoBack: Bool,
        canGoForward: Bool,
        lastError: String?,
        hasFailedServerTrustChallenge: Bool
    ) -> WebPageSnapshot {
        WebPageSnapshot(
            url: url,
            title: title,
            progress: progress,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            isSecure: isSecure(url: url, hasFailedServerTrustChallenge: hasFailedServerTrustChallenge),
            lastError: lastError
        )
    }
}

/// Wraps a single WKWebView with navigation actions, snapshot publication, and
/// pull-to-refresh. A lifecycle layer only: chrome logic lives in
/// BrowserRootViewController, which embeds `webView` full-bleed.
@MainActor
final class WebPageController: NSObject {
    let webView: WKWebView

    private(set) var snapshot = WebPageSnapshot.make(
        url: nil,
        title: nil,
        progress: 0,
        canGoBack: false,
        canGoForward: false,
        lastError: nil,
        hasFailedServerTrustChallenge: false
    )

    private var listeners: [UUID: @MainActor (WebPageSnapshot) -> Void] = [:]
    private var observations: [NSKeyValueObservation] = []
    private let refreshControl = UIRefreshControl()
    private var lastError: String?
    /// A denied server-trust challenge keeps the page untrusted for the whole
    /// web view session, even if a later navigation succeeds on https.
    private var hasFailedServerTrustChallenge = false

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        // Full-bleed content: no automatic safe-area or readables-content
        // insets; chrome floats above the web view instead of shrinking it.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self

        refreshControl.addAction(
            UIAction { [weak self] _ in self?.reload() },
            for: .valueChanged
        )
        webView.scrollView.refreshControl = refreshControl
        observeWebView()
    }

    func load(_ url: URL) {
        // Central allowlist: rejected schemes surface a navigation error
        // instead of reaching the web view.
        guard URLNormalizer.isLoadable(url) else {
            rejectUnsupportedScheme(url)
            return
        }
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func stop() {
        webView.stopLoading()
    }

    func takeSnapshot() async -> UIImage? {
        do {
            return try await webView.takeSnapshot(configuration: nil)
        } catch {
            return nil
        }
    }

    func takeSnapshot(completion: @escaping @MainActor (UIImage?) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            let image = await self.takeSnapshot()
            completion(image)
        }
    }

    @discardableResult
    func addSnapshotListener(_ handler: @escaping @MainActor (WebPageSnapshot) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = handler
        return id
    }

    func removeSnapshotListener(_ id: UUID) {
        listeners[id] = nil
    }

    // MARK: - Private

    private func makePublishingObservation(for keyPath: KeyPath<WKWebView, some Any>) -> NSKeyValueObservation {
        webView.observe(keyPath) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshSnapshot() }
        }
    }

    private func observeWebView() {
        observations = [
            makePublishingObservation(for: \.estimatedProgress),
            makePublishingObservation(for: \.title),
            makePublishingObservation(for: \.url),
            makePublishingObservation(for: \.canGoBack),
            makePublishingObservation(for: \.canGoForward),
            // The scroll view delegate belongs to the chrome scroll proxy, so
            // pull-to-refresh visibility is driven by offset observation
            // instead of scrollViewDidScroll.
            webView.scrollView.observe(\.contentOffset) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateRefreshControlVisibility() }
            }
        ]
    }

    private func refreshSnapshot() {
        let candidate = WebPageSnapshot.make(
            url: webView.url,
            title: webView.title,
            progress: webView.estimatedProgress,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward,
            lastError: lastError,
            hasFailedServerTrustChallenge: hasFailedServerTrustChallenge
        )
        guard candidate != snapshot else { return }
        snapshot = candidate
        for listener in listeners.values {
            listener(candidate)
        }
    }

    private func updateRefreshControlVisibility() {
        // Keep the spinner visible while refreshing even if the offset briefly
        // crosses zero during the settle bounce.
        guard !refreshControl.isRefreshing else { return }
        refreshControl.isHidden = webView.scrollView.contentOffset.y > 0
    }

    private func finishRefreshing() {
        refreshControl.endRefreshing()
        updateRefreshControlVisibility()
    }
}

// MARK: - WKNavigationDelegate

extension WebPageController: WKNavigationDelegate {
    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        // In-page navigations (links, redirects, window.location,
        // meta-refresh) bypass the address-bar normalizer, so every action
        // re-checks the allowlist before the web view commits.
        guard URLNormalizer.isLoadable(navigationAction.request.url) else {
            rejectUnsupportedScheme(navigationAction.request.url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        guard URLNormalizer.isLoadable(navigationResponse.response.url) else {
            rejectUnsupportedScheme(navigationResponse.response.url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        // A fresh navigation attempt supersedes any previous failure display.
        lastError = nil
        hasFailedServerTrustChallenge = false
        refreshSnapshot()
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        lastError = nil
        finishRefreshing()
        refreshSnapshot()
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        recordNavigationFailure(error)
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation!,
        withError error: Error
    ) {
        recordNavigationFailure(error)
    }

    func webView(
        _: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Verify server certificate against the system trust store. Never
        // bypass or accept invalid certificates.
        var error: CFError?
        let isTrusted = SecTrustEvaluateWithError(serverTrust, &error)
        if isTrusted {
            completionHandler(.performDefaultHandling, nil)
        } else {
            hasFailedServerTrustChallenge = true
            lastError = (error as Error?)?.localizedDescription ?? NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorServerCertificateUntrusted
            ).localizedDescription
            finishRefreshing()
            refreshSnapshot()
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func recordNavigationFailure(_ error: Error) {
        let nsError = error as NSError
        // Interruptions of an in-flight load (navigating away, stop) surface as
        // cancellations, not page failures worth displaying.
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else {
            finishRefreshing()
            return
        }
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorServerCertificateUntrusted {
            hasFailedServerTrustChallenge = true
        }
        lastError = error.localizedDescription
        finishRefreshing()
        refreshSnapshot()
    }

    private func rejectUnsupportedScheme(_ url: URL?) {
        let scheme = url?.scheme?.lowercased() ?? "unknown"
        // Surfaces as a navigation error so chrome shows the error overlay
        // instead of silently keeping the previous page.
        lastError = URLNormalizer.unsupportedSchemeMessage(scheme)
        finishRefreshing()
        refreshSnapshot()
    }
}
