// WebPage — WKWebView wrapper with navigation policy and snapshots.

import os
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
    var lastErrorCode: Int?
    var hasFailedServerTrustChallenge: Bool = false

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
        hasFailedServerTrustChallenge: Bool,
        lastErrorCode: Int? = nil
    ) -> WebPageSnapshot {
        WebPageSnapshot(
            url: url,
            title: title,
            progress: progress,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            isSecure: isSecure(url: url, hasFailedServerTrustChallenge: hasFailedServerTrustChallenge),
            lastError: lastError,
            lastErrorCode: lastErrorCode,
            hasFailedServerTrustChallenge: hasFailedServerTrustChallenge
        )
    }
}

/// Wraps a single WKWebView with navigation actions, snapshot publication, and
/// pull-to-refresh. A lifecycle layer only: chrome logic lives in
/// BrowserRootViewController, which embeds `webView` full-bleed.
@MainActor
final class WebPageController: NSObject {
    let webView: WKWebView

    /// Shared download pipeline; nil in unit tests without a pipeline.
    weak var downloadsManager: DownloadsManager?

    /// Sole transfer owner for standard-tab downloads, wired by the root;
    /// nil only in unit tests without a pipeline, which fail closed.
    weak var backgroundService: BackgroundDownloadService?

    #if DEBUG
        /// Test-only foreground fallback for unwired standard tabs; production fails closed.
        var allowsForegroundFallbackForTests = false
    #endif

    /// Privacy scope of the owning tab: private tabs never schedule
    /// background transfers (their data store is ephemeral). Fail-closed.
    var isPrivateTab = true

    /// Context-menu action set handed to WKUIDelegate; nil in disconnected
    /// pages and unit tests, which turns the custom menu off (WebKit's
    /// default menu applies).
    var contextActions: ElementContextActions?

    /// Per-site text zoom; nil in unit tests without a store reads as 1.0.
    var siteZoomStore: SiteZoomStore?

    /// Clears the carried method/body so a stale POST never bleeds forward.
    private func clearPendingAction() {
        pendingActionRequest = nil
        pendingActionGeneration = 0
    }

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
    private var lastErrorCode: Int?
    /// A denied server-trust challenge keeps the page untrusted for the whole
    /// web view session, even if a later navigation succeeds on https.
    private var hasFailedServerTrustChallenge = false

    private(set) var isReaderActive = false
    /// True after extraction proved the current document non-readerable.
    /// Cleared on navigation or a successful entry; gates the page menu.
    private(set) var isReaderUnavailable = false
    /// Bumped on every provisional navigation so in-flight reader work can
    /// tell a stale document from the live one.
    private var documentGeneration = 0
    private var readerTheme: ReaderTheme = ReaderMode.storedTheme()
    private var readerFontSize: Int = ReaderMode.storedFontSize()
    /// Last navigation request so the response path preserves method/body.
    /// Scoped by generation so a failed POST never bleeds into later responses.
    private var pendingActionRequest: URLRequest?
    private var pendingActionGeneration = 0

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        // Full-bleed content: no automatic safe-area or readables-content
        // insets; chrome floats above the web view instead of shrinking it.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.uiDelegate = self
        injectContextMenuTracker()
        injectFindHighlighter()

        refreshControl.addAction(
            UIAction { [weak self] _ in self?.reload() },
            for: .valueChanged
        )
        webView.scrollView.refreshControl = refreshControl
        observeWebView()
    }

    func load(_ url: URL) {
        // Screenshot mode allows only inline content; network loads cancel.
        if BrowserRootViewController.isScreenshotRun {
            if url.absoluteString.lowercased().contains("wikipedia.org") {
                webView.loadHTMLString(
                    BrowserRootViewController.screenshotFixtureHTML,
                    baseURL: url
                )
                return
            }
            guard url.absoluteString.lowercased() == "about:blank" else { return }
        }
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

    var backList: [WKBackForwardListItem] {
        webView.backForwardList.backList
    }

    func navigate(to item: WKBackForwardListItem) {
        webView.go(to: item)
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        // The reader transform lives in the live document, so restoring the
        // original page is a plain reload.
        isReaderActive = false
        isReaderUnavailable = false
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
        Task { [weak self] in
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

    /// JS tracker for long-press targets. WKContextMenuElementInfo only hands
    /// `linkURL` to the delegate, so image targets are read back from this
    /// DOM capture, where the chosen `src`/`srcset` candidate surfaces as an
    /// absolute URL string.
    private static let contextMenuTrackerScript = """
    (function() {
      if (window.__outerviewContextMenuInstalled) return;
      window.__outerviewContextMenuInstalled = true;
      document.addEventListener('contextmenu', function(event) {
        var payload = {};
        var target = event.target;
        if (target instanceof Element && target.closest) {
          var anchor = target.closest('a[href]');
          if (anchor && anchor.href) payload.link = anchor.href;
          var image = target instanceof HTMLImageElement ? target : target.closest('img');
          if (image) {
            var source = image.currentSrc || image.src || '';
            if (source) payload.image = source;
          }
        }
        window.__outerviewContextMenuPayload = payload;
      }, true);
    })();
    """

    private func injectContextMenuTracker() {
        // TabPool shares one configuration per browsing mode; installing the
        // same script again would pile up identical listeners.
        let controller = webView.configuration.userContentController
        guard !controller.userScripts.contains(where: { $0.source == Self.contextMenuTrackerScript }) else { return }
        controller.addUserScript(
            WKUserScript(
                source: Self.contextMenuTrackerScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
    }

    private func injectFindHighlighter() {
        let controller = webView.configuration.userContentController
        guard !controller.userScripts.contains(where: { $0.source == Self.findHighlighterScript }) else { return }
        controller.addUserScript(
            WKUserScript(
                source: Self.findHighlighterScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
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
            hasFailedServerTrustChallenge: hasFailedServerTrustChallenge,
            lastErrorCode: lastErrorCode
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
        // Screenshot mode keeps inline fixture only; every network
        // navigation cancels before the web view commits.
        if BrowserRootViewController.isScreenshotRun {
            let target = navigationAction.request.url?.absoluteString.lowercased()
            let isAllowed = target == nil || target == "about:blank" || (target?.contains("wikipedia.org") == true)
            if !isAllowed {
                clearPendingAction()
                decisionHandler(.cancel)
                return
            }
        }
        if navigationAction.shouldPerformDownload {
            // Same privacy split as the response decision. Fail-closed:
            // only a proven standard tab with a wired service schedules.
            if !isPrivateTab {
                if let service = backgroundService,
                   let url = navigationAction.request.url, URLNormalizer.isLoadable(url)
                {
                    clearPendingAction()
                    startStandardTransfer(to: service, request: navigationAction.request, suggestedName: url.lastPathComponent)
                    decisionHandler(.cancel)
                } else {
                    #if DEBUG
                        if allowsForegroundFallbackForTests {
                            clearPendingAction()
                            decisionHandler(.download)
                            return
                        }
                    #endif
                    clearPendingAction()
                    failClosedStandardDownload(suggestedName: navigationAction.request.url?.lastPathComponent ?? "download")
                    decisionHandler(.cancel)
                }
            } else {
                clearPendingAction()
                decisionHandler(.download)
            }
            return
        }
        // In-page navigations (links, redirects, window.location,
        // meta-refresh) bypass the address-bar normalizer, so every action
        // re-checks the allowlist before the web view commits.
        guard URLNormalizer.isLoadable(navigationAction.request.url) else {
            clearPendingAction()
            rejectUnsupportedScheme(navigationAction.request.url)
            decisionHandler(.cancel)
            return
        }
        // Remember the original request so the response path keeps method/body.
        pendingActionRequest = navigationAction.request
        pendingActionGeneration = documentGeneration + 1
        decisionHandler(.allow)
    }

    func webView(
        _: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        // Screenshot mode keeps inline fixture only; every network
        // response cancels before commit.
        if BrowserRootViewController.isScreenshotRun {
            let target = navigationResponse.response.url?.absoluteString.lowercased()
            let isAllowed = target == nil || target == "about:blank" || (target?.contains("wikipedia.org") == true)
            if !isAllowed {
                clearPendingAction()
                decisionHandler(.cancel)
                return
            }
        }
        guard let responseURL = navigationResponse.response.url, URLNormalizer.isLoadable(responseURL) else {
            clearPendingAction()
            rejectUnsupportedScheme(navigationResponse.response.url)
            decisionHandler(.cancel)
            return
        }
        if DownloadsManager.shouldDownload(navigationResponse: navigationResponse) {
            // Standard tabs cancel the web view load (WebKit 102 handover)
            // and start a daemon task; private tabs never touch the session.
            if !isPrivateTab {
                if let service = backgroundService {
                    let response = navigationResponse.response
                    let isCurrent = pendingActionGeneration == documentGeneration
                    let original = isCurrent && pendingActionRequest?.url == responseURL ? pendingActionRequest : nil
                    clearPendingAction()
                    startStandardTransfer(
                        to: service,
                        request: original ?? URLRequest(url: responseURL),
                        suggestedName: response.suggestedFilename ?? responseURL.lastPathComponent
                    )
                    decisionHandler(.cancel)
                } else {
                    #if DEBUG
                        if allowsForegroundFallbackForTests {
                            clearPendingAction()
                            decisionHandler(.download)
                            return
                        }
                    #endif
                    let response = navigationResponse.response
                    clearPendingAction()
                    failClosedStandardDownload(suggestedName: response.suggestedFilename ?? responseURL.lastPathComponent)
                    decisionHandler(.cancel)
                }
            } else {
                clearPendingAction()
                decisionHandler(.download)
            }
            return
        }
        clearPendingAction()
        decisionHandler(.allow)
    }

    func webView(
        _: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        let fallback = navigationAction.request.url?.lastPathComponent ?? "download"
        _ = downloadsManager?.begin(download: download, suggestedName: fallback)
    }

    func webView(
        _: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        let response = navigationResponse.response
        let fallback = response.suggestedFilename ?? response.url?.lastPathComponent ?? "download"
        _ = downloadsManager?.begin(download: download, suggestedName: fallback)
    }

    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        // A fresh navigation attempt supersedes any previous failure display.
        lastError = nil
        lastErrorCode = nil
        // A new document discards the reader transform applied to the old one.
        isReaderActive = false
        isReaderUnavailable = false
        documentGeneration += 1
        // Stale method/body never bleeds: only the current generation survives.
        if pendingActionGeneration != documentGeneration {
            clearPendingAction()
        }
        hasFailedServerTrustChallenge = false
        refreshSnapshot()
    }

    func webView(_: WKWebView, didCommit _: WKNavigation!) {
        applySiteZoom()
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        lastError = nil
        lastErrorCode = nil
        finishRefreshing()
        applySiteZoom()
        refreshSnapshot()
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        // Failed method/body never bleeds into the next response.
        clearPendingAction()
        recordNavigationFailure(error)
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation!,
        withError error: Error
    ) {
        // Failed method/body never bleeds into the next response.
        clearPendingAction()
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
            let nsFallback = NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorServerCertificateUntrusted
            )
            lastErrorCode = (error as Error? as NSError?)?.code ?? nsFallback.code
            lastError = (error as Error?)?.localizedDescription ?? nsFallback.localizedDescription
            finishRefreshing()
            refreshSnapshot()
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func recordNavigationFailure(_ error: Error) {
        // Failure drops any pending method/body even for suppressed errors.
        clearPendingAction()
        let nsError = error as NSError
        // Interruptions of an in-flight load (navigating away, stop) surface as
        // cancellations, not page failures worth displaying.
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else {
            finishRefreshing()
            return
        }
        // Download handovers interrupt the provisional load with WebKit error
        // 102; the transfer continues in the downloads pipeline.
        guard !(nsError.domain == "WebKitErrorDomain" && nsError.code == 102) else {
            finishRefreshing()
            return
        }
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorServerCertificateUntrusted {
            hasFailedServerTrustChallenge = true
        }
        lastErrorCode = nsError.code
        lastError = error.localizedDescription
        finishRefreshing()
        refreshSnapshot()
    }

    private func rejectUnsupportedScheme(_ url: URL?) {
        let scheme = url?.scheme?.lowercased() ?? "unknown"
        // Surfaces as a navigation error so chrome shows the error overlay
        // instead of silently keeping the previous page.
        lastError = URLNormalizer.unsupportedSchemeMessage(scheme)
        lastErrorCode = nil
        finishRefreshing()
        refreshSnapshot()
    }

    /// Hands a standard-tab transfer to the service: method/body/headers
    /// survive from the navigation request; cookies ride from the web view store.
    private func startStandardTransfer(
        to service: BackgroundDownloadService,
        request base: URLRequest,
        suggestedName: String?
    ) {
        let fallback = suggestedName ?? base.url?.lastPathComponent ?? "download"
        // Row registers synchronously so suspend during fetch still leaves a row.
        guard let manager = downloadsManager else {
            failClosedStandardDownload(suggestedName: fallback)
            return
        }
        let rowID = manager.registerRow(
            name: DownloadsManager.sanitizedFileName(fallback),
            fileURL: nil
        )
        // Captured upfront so deallocation during fetch still surfaces a row.
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let agent = webView.customUserAgent
        Task { @MainActor [weak self] in
            // Tests skip the store callback so the handoff never waits forever.
            let all: [HTTPCookie] =
                if AppEnvironment.isTestHost {
                    []
                } else {
                    await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie], Never>) in
                        cookieStore.getAllCookies { continuation.resume(returning: $0) }
                    }
                }
            var request = base
            if let url = base.url {
                let matching = Self.matchingCookies(all, for: url)
                let header = HTTPCookie.requestHeaderFields(with: matching)
                for (field, value) in header {
                    request.setValue(value, forHTTPHeaderField: field)
                }
            }
            if let agent {
                request.setValue(agent, forHTTPHeaderField: "User-Agent")
            }
            guard service.start(request: request, suggestedName: fallback, reusing: rowID) != nil else {
                self?.failClosedStandardDownload(suggestedName: fallback, reusing: rowID)
                return
            }
        }
    }

    /// Fail-closed surface for unwired standard downloads: never foreground.
    /// Records a failed row when the pipeline exists, else an error overlay.
    private func failClosedStandardDownload(suggestedName: String, reusing rowID: UUID? = nil) {
        assertionFailure("Standard download without service")
        let clean = DownloadsManager.sanitizedFileName(suggestedName)
        if let manager = downloadsManager {
            // Reuse the pre-registered row so the early window never leaks rows.
            if let rowID, manager.rows.contains(where: { $0.id == rowID }) {
                manager.failDownload(id: rowID, reason: "Download service unavailable")
            } else {
                let id = manager.registerRow(name: clean, fileURL: nil)
                manager.failDownload(id: id, reason: "Download service unavailable")
            }
        } else {
            lastError = "Download failed: service unavailable"
            lastErrorCode = nil
            finishRefreshing()
            refreshSnapshot()
        }
    }

    /// Cookies matching host plus path plus secure, for the daemon request.
    nonisolated static func matchingCookies(_ all: [HTTPCookie], for url: URL) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else {
            return []
        }
        let path = url.path.isEmpty ? "/" : url.path
        let isSecure = url.scheme?.lowercased() == "https"
        return all.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: .init(charactersIn: "."))
            guard host == domain || host.hasSuffix("." + domain) else {
                return false
            }
            if cookie.isSecure, !isSecure {
                return false
            }
            let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
            if path == cookiePath {
                return true
            }
            // Boundary check so /private never matches /private-evil per RFC6265.
            let prefix = cookiePath.hasSuffix("/") ? cookiePath : cookiePath + "/"
            return path.hasPrefix(prefix)
        }
    }
}

// MARK: - Reader Mode

extension WebPageController {
    /// Runs extraction and swaps in the themed article. A missing or short
    /// payload leaves reader off and the page untouched.
    func toggleReader() async -> Bool {
        if isReaderActive {
            reload()
            return false
        }
        let generation = documentGeneration
        do {
            let result = try await webView.evaluateJavaScript(ReaderMode.extractionScript())
            guard !Task.isCancelled, generation == documentGeneration else { return false }
            guard let json = result as? String,
                  ReaderMode.parsedArticle(from: json) != nil
            else {
                isReaderUnavailable = true
                return false
            }
            _ = try await webView.evaluateJavaScript(
                ReaderMode.replaceBodyScript(theme: readerTheme, fontSize: readerFontSize)
            )
            guard !Task.isCancelled, generation == documentGeneration else { return false }
            isReaderActive = true
            isReaderUnavailable = false
            return true
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "WebPage")
                .error("toggleReader failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func setReaderTheme(_ theme: ReaderTheme) async {
        readerTheme = theme
        ReaderMode.persist(theme: theme)
        guard isReaderActive else { return }
        do {
            _ = try await webView.evaluateJavaScript(
                ReaderMode.replaceBodyScript(theme: readerTheme, fontSize: readerFontSize)
            )
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "WebPage")
                .error("setReaderTheme failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sizes outside 14–28 pt clamp to the nearest bound before persisting.
    func setReaderFontSize(_ size: Int) async {
        readerFontSize = ReaderMode.clampedFontSize(size)
        ReaderMode.persist(fontSize: readerFontSize)
        guard isReaderActive else { return }
        do {
            _ = try await webView.evaluateJavaScript(
                ReaderMode.replaceBodyScript(theme: readerTheme, fontSize: readerFontSize)
            )
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "WebPage")
                .error("setReaderFontSize failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Site Zoom

extension WebPageController {
    func currentTextZoom() -> Double {
        guard let store = siteZoomStore, let host = webView.url?.host else { return 1.0 }
        return store.zoom(forHost: host)
    }

    func setTextZoom(_ zoom: Double) {
        let clamped = SiteZoomStore.clamp(zoom)
        webView.pageZoom = CGFloat(clamped)
        guard let host = webView.url?.host, !host.isEmpty else { return }
        siteZoomStore?.setZoom(clamped, forHost: host)
    }

    func applySiteZoom() {
        webView.pageZoom = CGFloat(currentTextZoom())
    }
}

// MARK: - WKUIDelegate

extension WebPageController: WKUIDelegate {
    func webView(
        _: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping @MainActor @Sendable (UIContextMenuConfiguration?) -> Void
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
            completionHandler(
                UIContextMenuConfiguration(
                    identifier: nil,
                    previewProvider: nil,
                    actionProvider: { _ in menu }
                )
            )
        }
    }

    /// Extracts the first 1-2 sentences of body text from the web page for Reading List preview.
    func extractPreviewSnippet() async -> String? {
        let generation = documentGeneration
        do {
            let result = try await webView.evaluateJavaScript(ReaderMode.extractionScript())
            guard !Task.isCancelled, generation == documentGeneration,
                  let json = result as? String,
                  let snippet = ReaderMode.previewSnippet(from: json)
            else { return nil }
            return snippet
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "WebPage")
                .error("extractPreviewSnippet failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
