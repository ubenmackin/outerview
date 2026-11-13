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

/// Delegate handling UI-level WebKit interactions: multi-window popups,
/// programmatic window closing, and JavaScript alert/confirm/prompt panels.
@MainActor
protocol WebPageUIDelegateHandler: AnyObject {
    func webPageController(
        _ controller: WebPageController,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView?

    func webPageControllerDidClose(_ controller: WebPageController)

    func webPageController(
        _ controller: WebPageController,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async

    func webPageController(
        _ controller: WebPageController,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool

    func webPageController(
        _ controller: WebPageController,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String?
}

/// Wraps a single WKWebView with navigation actions, snapshot publication, and
/// pull-to-refresh. A lifecycle layer only: chrome logic lives in
/// BrowserRootViewController, which embeds `webView` full-bleed.
@MainActor
final class WebPageController: NSObject {
    let webView: WKWebView

    /// Delegate handling UI events (popups, dialogs, closing).
    weak var uiDelegateHandler: WebPageUIDelegateHandler?

    /// Whether desktop website mode is currently forced on this page.
    private(set) var isDesktopMode = false

    /// Whether the user has temporarily overridden desktop mode for this tab session.
    private(set) var hasPerTabDesktopOverride = false

    /// Effective state for menu labels; always mirrors the applied mode.
    var effectiveDesktopMode: Bool {
        isDesktopMode
    }

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

    /// Per-site website settings (desktop mode, automatic reader); nil in unwired tests.
    var websiteSettingsStore: WebsiteSettingsStore?

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
    /// Title of the current document, cleared on navigation so previous
    /// page titles never bleed into newly committed URLs.
    private var currentDocumentTitle: String?

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        // WebKit owns the interactive transition for back/forward edge swipes.
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        #if DEBUG
            webView.isInspectable = true
        #endif
        // Full-bleed content: no automatic insets; Mode 3 parks below
        // the cluster via manual safeAreaTop inset instead of shrinking
        // the web view.
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
        if let targetHost = url.host,
           targetHost != webView.url?.host
        {
            hasPerTabDesktopOverride = false
        }
        applyWebsiteSettings(for: url)
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
            let config = WKSnapshotConfiguration()
            let topInset = webView.scrollView.adjustedContentInset.top
            if topInset > 0, webView.bounds.width > 0, webView.bounds.height > topInset {
                config.rect = CGRect(
                    x: 0,
                    y: topInset,
                    width: webView.bounds.width,
                    height: webView.bounds.height - topInset
                )
            }
            return try await webView.takeSnapshot(configuration: config)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "WebPage")
                .error("takeSnapshot failed: \(error.localizedDescription, privacy: .public)")
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

    // swiftformat:disable:next opaqueGenericParameters
    private func makePublishingObservation<Value>(for keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
        webView.observe(keyPath) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshSnapshot() }
        }
    }

    private func observeWebView() {
        observations = [
            makePublishingObservation(for: \.estimatedProgress),
            webView.observe(\.title) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let title = self.webView.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                        self.currentDocumentTitle = title
                    }
                    self.refreshSnapshot()
                }
            },
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
            title: currentDocumentTitle,
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
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
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
        if let targetURL = navigationAction.request.url,
           let targetHost = targetURL.host,
           targetHost != webView.url?.host
        {
            hasPerTabDesktopOverride = false
            applyWebsiteSettings(for: targetURL)
        }
        // Remember the original request so the response path keeps method/body.
        pendingActionRequest = navigationAction.request
        pendingActionGeneration = documentGeneration + 1
        decisionHandler(.allow)
    }

    func webView(
        _: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
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
                    let isCurrent = pendingActionGeneration == documentGeneration || pendingActionGeneration == documentGeneration + 1
                    var resolved: URLRequest = if isCurrent, let pending = pendingActionRequest, pending.url == responseURL {
                        pending
                    } else {
                        URLRequest(url: responseURL)
                    }
                    if isCurrent, let pending = pendingActionRequest, pending.url != responseURL {
                        for field in ["Referer", "User-Agent"] {
                            if let value = pending.value(forHTTPHeaderField: field) {
                                resolved.setValue(value, forHTTPHeaderField: field)
                            }
                        }
                    }
                    clearPendingAction()
                    startStandardTransfer(
                        to: service,
                        request: resolved,
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

    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation?) {
        // A fresh navigation attempt supersedes any previous failure display.
        lastError = nil
        lastErrorCode = nil
        currentDocumentTitle = nil
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

    func webView(_: WKWebView, didCommit _: WKNavigation?) {
        applySiteZoom()
    }

    func webView(_: WKWebView, didFinish _: WKNavigation?) {
        lastError = nil
        lastErrorCode = nil
        if let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            currentDocumentTitle = title
        }
        finishRefreshing()
        applySiteZoom()
        refreshSnapshot()
        applyAutomaticReaderIfNeeded()
    }

    func webView(_: WKWebView, didFail _: WKNavigation?, withError error: Error) {
        // Failed method/body never bleeds into the next response.
        clearPendingAction()
        recordNavigationFailure(error)
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation?,
        withError error: Error
    ) {
        // Failed method/body never bleeds into the next response.
        clearPendingAction()
        recordNavigationFailure(error)
    }

    func webView(
        _: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
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
        let pageURL = webView.url
        Task { [weak self] in
            // Tests skip the store callback so the handoff never waits forever.
            let all: [HTTPCookie] =
                if AppEnvironment.isTestHost {
                    []
                } else {
                    await cookieStore.allCookies()
                }
            let request = Self.preparedDownloadRequest(
                base: base,
                customUserAgent: agent,
                pageURL: pageURL,
                cookies: all
            )
            guard service.start(request: request, suggestedName: fallback, reusing: rowID) != nil else {
                self?.failClosedStandardDownload(suggestedName: fallback, reusing: rowID)
                return
            }
        }
    }

    /// Attaches matching cookies, browser User-Agent, and downgrade-safe Referer for daemon transfers.
    nonisolated static func preparedDownloadRequest(
        base: URLRequest,
        customUserAgent: String?,
        pageURL: URL?,
        cookies: [HTTPCookie]
    ) -> URLRequest {
        DownloadsManager.preparedRequest(
            base: base, customUserAgent: customUserAgent, defaultUserAgent: mobileUserAgent, pageURL: pageURL, cookies: cookies
        )
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

// MARK: - Site Zoom

extension WebPageController {
    func currentTextZoom() -> Double {
        // Private tabs stay ephemeral so hosts never read persisted zooms.
        guard !isPrivateTab else { return Double(webView.pageZoom) }
        guard let store = siteZoomStore, let host = webView.url?.host else { return 1.0 }
        return store.zoom(forHost: host)
    }

    func setTextZoom(_ zoom: Double) {
        let clamped = SiteZoomStore.clamp(zoom)
        webView.pageZoom = CGFloat(clamped)
        // Private hosts never reach defaults; zoom applies to the live view only.
        guard !isPrivateTab, let host = webView.url?.host, !host.isEmpty else { return }
        siteZoomStore?.setZoom(clamped, forHost: host)
    }

    func applySiteZoom() {
        // New documents reset private zoom; standard tabs restore persisted zoom.
        if isPrivateTab {
            webView.pageZoom = CGFloat(SiteZoomStore.defaultZoom)
        } else {
            webView.pageZoom = CGFloat(currentTextZoom())
        }
    }
}

// MARK: - Desktop Mode & Website Settings

extension WebPageController {
    nonisolated static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    nonisolated static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    func toggleDesktopMode() {
        hasPerTabDesktopOverride = true
        isDesktopMode.toggle()
        if isDesktopMode {
            webView.customUserAgent = Self.desktopUserAgent
        } else {
            webView.customUserAgent = nil
        }
        reload()
    }

    func setDesktopMode(_ enabled: Bool) {
        hasPerTabDesktopOverride = false
        guard isDesktopMode != enabled else { return }
        isDesktopMode = enabled
        if isDesktopMode {
            webView.customUserAgent = Self.desktopUserAgent
        } else {
            webView.customUserAgent = nil
        }
        reload()
    }

    func applyWebsiteSettings(for url: URL) {
        guard let host = url.host, !host.isEmpty else { return }
        if !hasPerTabDesktopOverride {
            let desktopDefault = websiteSettingsStore?.settings(forHost: host, isPrivate: isPrivateTab).requestDesktopWebsite ?? false
            if isDesktopMode != desktopDefault {
                isDesktopMode = desktopDefault
                webView.customUserAgent = desktopDefault ? Self.desktopUserAgent : nil
            }
        }
    }

    func applyAutomaticReaderIfNeeded() {
        guard let host = webView.url?.host, !host.isEmpty,
              websiteSettingsStore?.settings(forHost: host, isPrivate: isPrivateTab).useReaderAutomatically == true,
              !isReaderActive,
              !isReaderUnavailable
        else { return }
        Task { [weak self] in
            await self?.enterReaderAutomaticallyIfNeeded()
        }
    }

    @discardableResult
    func enterReaderAutomaticallyIfNeeded() async -> Bool {
        guard !isReaderActive, !isReaderUnavailable else { return false }
        return await toggleReader()
    }
}
