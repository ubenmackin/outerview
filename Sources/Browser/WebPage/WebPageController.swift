//
//  WebPageController.swift
//  OuterView
//

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

    /// Context-menu action set handed to WKUIDelegate; nil in disconnected
    /// pages and unit tests, which turns the custom menu off (WebKit's
    /// default menu applies).
    var contextActions: ElementContextActions?

    /// Per-site text zoom; nil in unit tests without a store reads as 1.0.
    var siteZoomStore: SiteZoomStore?

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
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
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
        if DownloadsManager.shouldDownload(navigationResponse: navigationResponse) {
            decisionHandler(.download)
            return
        }
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
}

// MARK: - Find in Page

struct FindResponse: Decodable, Sendable {
    var total: Int
    var index: Int
}

extension WebPageController {
    static let findHighlighterScript = """
    (function() {
      if (window.__outerviewFindInstalled) return;
      window.__outerviewFindInstalled = true;
      window.__outerviewFindMatches = 0;
      window.__outerviewFindIndex = 0;
      function clearMarks() {
        var prev = document.querySelectorAll('.outerview-find-highlight');
        for (var p = 0; p < prev.length; p++) {
          var el = prev[p];
          var parent = el.parentNode;
          if (!parent) { continue; }
          parent.replaceChild(document.createTextNode(el.textContent), el);
          parent.normalize();
        }
        window.__outerviewFindMatches = 0;
        window.__outerviewFindIndex = 0;
      }
      function paintCurrent() {
        var marks = document.querySelectorAll('.outerview-find-highlight');
        for (var i = 0; i < marks.length; i++) {
          var m = marks[i];
          if (i === window.__outerviewFindIndex - 1) {
            m.style.backgroundColor = '#FF9800';
            m.style.color = '#000';
            if (m.scrollIntoView) { m.scrollIntoView({block:'center'}); }
          } else {
            m.style.backgroundColor = '#FFEB3B';
            m.style.color = '#000';
          }
        }
      }
      window.__outerviewFind = function(query) {
        clearMarks();
        var q = String(query || '');
        if (!q) { return JSON.stringify({total:0,index:0}); }
        var lower = q.toLowerCase();
        if (!lower || !document.body) { return JSON.stringify({total:0,index:0}); }
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
        var nodes = [];
        while (walker.nextNode()) { nodes.push(walker.currentNode); }
        var count = 0;
        for (var i = 0; i < nodes.length; i++) {
          var node = nodes[i];
          var text = node.nodeValue;
          if (!text) { continue; }
          var tag = node.parentNode && node.parentNode.tagName;
          if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') { continue; }
          if (text.toLowerCase().indexOf(lower) === -1) { continue; }
          var frag = document.createDocumentFragment();
          var remaining = text;
          var lowerRemaining = remaining.toLowerCase();
          var matched = false;
          while (true) {
            var j = lowerRemaining.indexOf(lower);
            if (j === -1) {
              frag.appendChild(document.createTextNode(remaining));
              break;
            }
            matched = true;
            frag.appendChild(document.createTextNode(remaining.slice(0, j)));
            var mark = document.createElement('mark');
            mark.className = 'outerview-find-highlight';
            mark.style.backgroundColor = '#FFEB3B';
            mark.style.color = '#000';
            mark.textContent = remaining.substr(j, q.length);
            frag.appendChild(mark);
            count++;
            remaining = remaining.slice(j + q.length);
            lowerRemaining = remaining.toLowerCase();
            if (!remaining) { break; }
          }
          if (matched) { node.parentNode.replaceChild(frag, node); }
        }
        window.__outerviewFindMatches = count;
        window.__outerviewFindIndex = count > 0 ? 1 : 0;
        paintCurrent();
        return JSON.stringify({total:count,index:window.__outerviewFindIndex});
      };
      window.__outerviewStep = function(delta) {
        var total = window.__outerviewFindMatches || 0;
        if (total === 0) { return JSON.stringify({total:0,index:0}); }
        var d = Number(delta) || 0;
        var idx = window.__outerviewFindIndex || 1;
        idx = ((idx - 1 + d) % total + total) % total + 1;
        window.__outerviewFindIndex = idx;
        paintCurrent();
        return JSON.stringify({total:total,index:idx});
      };
      window.__outerviewClear = function() { clearMarks(); };
    })();
    """

    nonisolated static func parsedFindCounts(from jsonString: String?) -> (total: Int, index: Int) {
        guard let jsonString,
              let data = jsonString.data(using: .utf8)
        else {
            return (0, 0)
        }
        let decoded: FindResponse
        do {
            decoded = try JSONDecoder().decode(FindResponse.self, from: data)
        } catch {
            return (0, 0)
        }
        return (max(0, decoded.total), max(0, decoded.index))
    }

    nonisolated static func parsedFindTotal(from jsonString: String?) -> Int {
        parsedFindCounts(from: jsonString).total
    }

    nonisolated static func parsedFindIndex(from jsonString: String?) -> Int {
        parsedFindCounts(from: jsonString).index
    }

    nonisolated static func escapedFindQuery(_ query: String) -> String {
        query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    func findText(_ query: String) async -> Int {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await clearFind()
            return 0
        }
        let escaped = Self.escapedFindQuery(trimmed)
        do {
            let result = try await webView.evaluateJavaScript("window.__outerviewFind('\(escaped)')")
            guard let json = result as? String else { return 0 }
            return Self.parsedFindTotal(from: json)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "WebPage")
                .error("findText failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    func findStep(_ delta: Int) async -> Int {
        do {
            let result = try await webView.evaluateJavaScript("window.__outerviewStep(\(delta))")
            if let json = result as? String {
                return Self.parsedFindIndex(from: json)
            }
            if let number = result as? Int {
                return max(0, number)
            }
            if let number = result as? Double {
                return max(0, Int(number))
            }
            return 0
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "WebPage")
                .error("findStep failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    func clearFind() async {
        do {
            _ = try await webView.evaluateJavaScript("window.__outerviewClear && window.__outerviewClear()")
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "WebPage")
                .error("clearFind failed: \(error.localizedDescription, privacy: .public)")
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
