// Tests — Audit remediation coverage for dialog/download/private/preview safety.

import os
@testable import OuterView
import SwiftUI
import UIKit
import WebKit
import XCTest

@MainActor
final class AuditRemediationTests: XCTestCase {
    // MARK: - Helpers

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suite = "com.outerview.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }

    private func makeRoot(
        defaults: UserDefaults? = nil,
        biometrics: BiometricAuthenticating? = nil
    ) throws -> BrowserRootViewController {
        let database = try OuterViewDatabase(inMemory: true)
        let resolvedDefaults = try defaults ?? makeIsolatedDefaults()
        let root = BrowserRootViewController(database: database, defaults: resolvedDefaults)
        if let biometrics {
            root.biometricAuthService = biometrics
        }
        return root
    }

    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ov-audit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return dir
    }

    private func makeSolidImage(size: CGSize, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func menuAction(named title: String, in menu: UIMenu) -> UIAction? {
        for child in menu.children {
            if let action = child as? UIAction, action.title == title {
                return action
            }
            if let submenu = child as? UIMenu, let found = menuAction(named: title, in: submenu) {
                return found
            }
        }
        return nil
    }

    // MARK: - Critical #1: WebKit & UIKit Dialog Safety

    func testDismissAwareAlertControllerFiresFallbackWithoutActionAndDeallocates() async {
        let host = UIViewController()
        let window = TestWindow.attach(host)
        defer { withExtendedLifetime(window) {} }

        var fallbackFiredCount = 0
        weak var weakAlert: DismissAwareAlertController?

        do {
            let alert = DismissAwareAlertController(title: "Notice", message: "Body", preferredStyle: .alert)
            weakAlert = alert
            alert.onFinishWithoutAction = {
                fallbackFiredCount += 1
            }
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            host.present(alert, animated: false)
        }

        await waitUntil { host.presentedViewController != nil }
        XCTAssertNotNil(host.presentedViewController)

        await withCheckedContinuation { continuation in
            host.dismiss(animated: false) {
                continuation.resume()
            }
        }
        await waitUntil { weakAlert == nil && fallbackFiredCount == 1 }

        XCTAssertEqual(fallbackFiredCount, 1)
        XCTAssertNil(weakAlert)
    }

    func testJSDialogResumesFailClosedWhenDetachedOrPresenterIsDismissing() async throws {
        // Case A: Detached root controller (window == nil) must resume without hanging.
        let detachedRoot = try makeRoot()
        detachedRoot.loadViewIfNeeded()
        XCTAssertNil(detachedRoot.view.window)
        let detachedPage = try XCTUnwrap(detachedRoot.activePage())
        detachedPage.webView.loadHTMLString("<html><body></body></html>", baseURL: URL(string: "https://example.com"))
        await waitUntil { !detachedPage.snapshot.isLoading && detachedPage.webView.url != nil }

        let detachedResult = try await detachedPage.webView.evaluateJavaScript("confirm('detached?')")
        XCTAssertEqual(detachedResult as? Bool, false)

        // Case B: Presenter's top modal reports isBeingDismissed == true -> must fail closed immediately.
        let root = try makeRoot()
        let window = TestWindow.attach(root)
        defer { withExtendedLifetime(window) {} }
        let modal = AlwaysDismissingViewController()
        root.present(modal, animated: false)
        await waitUntil { root.presentedViewController === modal }

        let page = try XCTUnwrap(root.activePage())
        page.webView.loadHTMLString("<html><body></body></html>", baseURL: URL(string: "https://example.com"))
        await waitUntil { !page.snapshot.isLoading && page.webView.url != nil }

        XCTAssertTrue(modal.isBeingDismissed)
        let dismissingResult = try await page.webView.evaluateJavaScript("confirm('while dismissing?')")
        XCTAssertEqual(dismissingResult as? Bool, false)

        // Case C: Unpresented DismissAwareAlertController deallocating fires fallback cleanly.
        var unpresentedFired = false
        do {
            let unpresented = DismissAwareAlertController(title: "Dropped", message: nil, preferredStyle: .alert)
            unpresented.onFinishWithoutAction = {
                unpresentedFired = true
            }
        }
        await waitUntil { unpresentedFired }
        XCTAssertTrue(unpresentedFired)
    }

    // MARK: - Critical #2: Background Download Completion Ordering

    func testBackgroundSessionDidFinishEventsWaitsForInFlightFinalizeDownload() async throws {
        let directory = try makeDirectory()
        let manager = DownloadsManager(directoryURL: directory)
        let service = BackgroundDownloadService.shared

        let previousManager = service.manager
        let previousStore = service.launchHandlerStore
        defer {
            service.manager = previousManager
            service.launchHandlerStore = previousStore
        }

        var handlerInvoked = false
        var rowCountWhenHandlerRan = 0
        var rowStateWhenHandlerRan: DownloadState?

        let launchStore = SpyLaunchHandlerStore {
            handlerInvoked = true
            rowCountWhenHandlerRan = manager.rows.count
            rowStateWhenHandlerRan = manager.rows.first?.state
        }

        service.manager = manager
        service.launchHandlerStore = launchStore

        let sourceURL = directory.appendingPathComponent("staged-input.tmp")
        try Data("hello-download".utf8).write(to: sourceURL)

        let ephemeral = URLSession(configuration: .ephemeral)
        defer { ephemeral.invalidateAndCancel() }
        let downloadTask = try ephemeral.downloadTask(with: XCTUnwrap(URL(string: "https://example.com/report.pdf")))

        service.urlSession(ephemeral, downloadTask: downloadTask, didFinishDownloadingTo: sourceURL)
        await service.handleSessionDidFinishEvents(identifier: BackgroundDownloadService.sessionIdentifier)

        XCTAssertTrue(handlerInvoked)
        XCTAssertEqual(rowCountWhenHandlerRan, 1)
        XCTAssertEqual(rowStateWhenHandlerRan, .finished)
        let savedURL = try XCTUnwrap(manager.rows.first?.fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    // MARK: - Critical #3: Private Browsing Isolation & Ephemeral Store Rotation

    func testTabPoolResetPrivateSessionStoreRotatesToFreshNonPersistentStore() async throws {
        let defaults = try makeIsolatedDefaults()
        let pool = TabPool(defaults: defaults)

        let initialStore = pool.configuration(isPrivate: true).websiteDataStore
        XCTAssertFalse(initialStore.isPersistent)

        await pool.resetPrivateSessionStore()

        let rotatedStore = pool.configuration(isPrivate: true).websiteDataStore
        XCTAssertFalse(rotatedStore.isPersistent)
        XCTAssertFalse(initialStore === rotatedStore)
    }

    func testPrivateTabDownloadLinkedFileNeverEnqueuesBackgroundServiceAndLastCloseRotatesStore() async throws {
        let bgDir = try makeDirectory()
        let isolatedBgManager = DownloadsManager(directoryURL: bgDir)
        let root = try makeRoot()
        let window = TestWindow.attach(root)
        defer {
            withExtendedLifetime(window) {}
            root.downloadsManager.suspendForegroundDownloads()
            BackgroundDownloadService.shared.manager = nil
        }

        root.createNewTab(isPrivate: true)
        XCTAssertTrue(root.resolvedScopeIsPrivate())

        // Point BackgroundDownloadService at a separate spy manager after setup so any bypass shows up immediately.
        BackgroundDownloadService.shared.manager = isolatedBgManager

        let privateStoreBefore = root.tabPool.configuration(isPrivate: true).websiteDataStore
        try root.downloadLinkedFile(url: XCTUnwrap(URL(string: "https://example.invalid/secret.zip")))

        XCTAssertTrue(isolatedBgManager.rows.isEmpty)

        root.resetAllTabsToSingleEmptyTab()
        await waitUntil {
            root.tabPool.configuration(isPrivate: true).websiteDataStore !== privateStoreBefore
        }
        XCTAssertFalse(root.tabPool.configuration(isPrivate: true).websiteDataStore === privateStoreBefore)
    }

    // MARK: - High #4: WebContent Termination Recovery & Rapid-Repeat Loop Guard

    func testWebContentProcessDidTerminateReloadsOnceThenShowsErrorOnRapidRepeat() async throws {
        let page = WebPageController(configuration: WKWebViewConfiguration())
        let baseURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        page.webView.loadHTMLString("<html><body>Content</body></html>", baseURL: baseURL)
        await waitUntil { !page.snapshot.isLoading && page.webView.url != nil }

        page.webViewWebContentProcessDidTerminate(page.webView)
        XCTAssertNil(page.snapshot.lastError)

        page.webViewWebContentProcessDidTerminate(page.webView)
        XCTAssertEqual(page.snapshot.lastError, "The webpage encountered an unexpected error and had to stop.")
    }

    // MARK: - High #5: Subresource TLS Isolation & Subframe Scheme Scoping

    func testThirdPartySubresourceTLSChallengeDoesNotDowngradeCommittedPage() async throws {
        let page = WebPageController(configuration: WKWebViewConfiguration())
        let mainURL = try XCTUnwrap(URL(string: "https://example.com/secure"))
        let iframeHTML = "<html><body><iframe src=\"outerview-unsupported://evil\"></iframe></body></html>"
        page.webView.loadHTMLString(iframeHTML, baseURL: mainURL)
        await waitUntil { !page.snapshot.isLoading && page.webView.url?.host == "example.com" }

        // Unsupported subframe scheme should be cancelled without showing a top-level error screen.
        XCTAssertNil(page.snapshot.lastError)

        // Third-party host TLS failure cancels auth challenge but keeps top-level HTTPS state intact.
        let thirdPartySpace = try StubServerTrustProtectionSpace(
            host: "tracker.invalid",
            trust: makeUntrustedTrust(host: "tracker.invalid")
        )
        let thirdPartyChallenge = URLAuthenticationChallenge(
            protectionSpace: thirdPartySpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: DummyAuthChallengeSender()
        )

        var thirdPartyDisposition: URLSession.AuthChallengeDisposition?
        page.webView(page.webView, didReceive: thirdPartyChallenge) { disposition, _ in
            thirdPartyDisposition = disposition
        }
        XCTAssertEqual(thirdPartyDisposition, .cancelAuthenticationChallenge)
        XCTAssertFalse(page.snapshot.hasFailedServerTrustChallenge)
        XCTAssertNil(page.snapshot.lastError)

        // Matching main-document host TLS failure rejects challenge and marks the page insecure.
        let mainHostSpace = try StubServerTrustProtectionSpace(
            host: "example.com",
            trust: makeUntrustedTrust(host: "example.com")
        )
        let mainHostChallenge = URLAuthenticationChallenge(
            protectionSpace: mainHostSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: DummyAuthChallengeSender()
        )

        var mainDisposition: URLSession.AuthChallengeDisposition?
        page.webView(page.webView, didReceive: mainHostChallenge) { disposition, _ in
            mainDisposition = disposition
        }
        XCTAssertEqual(mainDisposition, .cancelAuthenticationChallenge)
        XCTAssertTrue(page.snapshot.hasFailedServerTrustChallenge)
    }

    private static let untrustedCertBase64 =
        "MIIBbTCCARKgAwIBAgIULKex0aBHlUXqETACmun0JR3XxVEwCgYIKoZIzj0EAwIw"
            + "HDEaMBgGA1UEAwwRdW50cnVzdGVkLmludmFsaWQwHhcNMjYxMTEzMTcxNzA3WhcN"
            + "MjYxMTE0MTcxNzA3WjAcMRowGAYDVQQDDBF1bnRydXN0ZWQuaW52YWxpZDBZMBMG"
            + "ByqGSM49AgEGCCqGSM49AwEHA0IABOv1LASvSbEai10G/3ukAZzudEJegY1Yx0T0"
            + "MyxpOgAKAqZyBqR8ema6sIposYPouZjJex3v1HW1Y6ZdH+1FSYijMjAwMB0GA1Ud"
            + "DgQWBBSWDdXBUdAgfHiT2J8Js5pOf3ZW3DAPBgNVHRMBAf8EBTADAQH/MAoGCCqG"
            + "SM49BAMCA0kAMEYCIQDjhRAAGIM6A8s76LVRaQ5Y0YG4hcZ4DH4hxCZYQ0lPKgIh"
            + "AO/ImNzY2xqpPWrgIFCEqGtcDrV350DT7OCZFdv+ckeg"

    private func makeUntrustedTrust(host: String) throws -> SecTrust {
        let certData = try XCTUnwrap(Data(base64Encoded: Self.untrustedCertBase64))
        let cert = try XCTUnwrap(SecCertificateCreateWithData(nil, certData as CFData))
        let policy = SecPolicyCreateSSL(true, host as CFString)
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates([cert] as CFArray, policy, &trust)
        XCTAssertEqual(status, errSecSuccess)
        return try XCTUnwrap(trust)
    }

    // MARK: - High #6: DownloadsManager Tracking Cleanup & Late Error Guard

    func testDownloadsManagerCancelAndFinishClearTrackingAndPreserveCancelledState() throws {
        let directory = try makeDirectory()
        let manager = DownloadsManager(directoryURL: directory)
        defer { manager.suspendForegroundDownloads() }

        // Hollow doubles: real WebKit download internals are unreachable from unit tests,
        // so every WebKit-facing member is stubbed and the double is pinned — hollow
        // deallocation traps in WebKit's -[WKDownload dealloc].
        let cancelledDownload = StubDownload()
        _ = manager.begin(download: cancelledDownload, suggestedName: "cancelled.zip")
        XCTAssertEqual(manager.trackedDownloadCount, 1)

        let cancelledRowID = try XCTUnwrap(manager.rows.first?.id)
        manager.cancel(id: cancelledRowID)
        XCTAssertEqual(manager.trackedDownloadCount, 0)
        XCTAssertEqual(manager.rows.first?.state, .failed("Cancelled"))

        // Late delegate failure must not overwrite "Cancelled" or leak tracking entries.
        manager.download(cancelledDownload, didFailWithError: URLError(.timedOut), resumeData: nil)
        XCTAssertEqual(manager.rows.first?.state, .failed("Cancelled"))
        XCTAssertEqual(manager.trackedDownloadCount, 0)

        let finishedDownload = StubDownload()
        _ = manager.begin(download: finishedDownload, suggestedName: "done.pdf")
        XCTAssertEqual(manager.trackedDownloadCount, 1)

        manager.downloadDidFinish(finishedDownload)
        XCTAssertEqual(manager.trackedDownloadCount, 0)
        XCTAssertEqual(manager.rows.last?.state, .finished)
    }

    // MARK: - High #7: ContentBlockerService Serialized Registration

    func testContentBlockerRegisterAndSyncSerializesAfterDisableToggle() async {
        let service = ContentBlockerService.shared
        defer {
            Task { await service.setEnabled(true) }
        }

        let controller = WKUserContentController()
        let order = LockedEvents()

        let registerTask = Task { @MainActor in
            await service.registerAndSyncController(controller) {
                order.append("evaluate-register")
                return true
            }
            order.append("finish-register")
        }

        // Wait for register evaluation so disable enqueues after its chain link;
        // both operations still overlap while the rule compile stays in flight.
        await waitUntil { order.snapshot().contains("evaluate-register") }

        let disableTask = Task { @MainActor in
            await service.setEnabled(false, controllers: [controller])
            order.append("finish-disable")
        }

        await registerTask.value
        await disableTask.value

        let recorded = order.snapshot()
        let registerFinishIndex = recorded.firstIndex(of: "finish-register")
        let disableFinishIndex = recorded.firstIndex(of: "finish-disable")
        XCTAssertNotNil(registerFinishIndex)
        XCTAssertNotNil(disableFinishIndex)
        if let regIdx = registerFinishIndex, let disIdx = disableFinishIndex {
            XCTAssertLessThan(regIdx, disIdx)
        }
    }

    // MARK: - High #8: Biometric Privacy Shield, External URL Routing, & Deep-Link Dedup

    func testPrivacyShieldVisibilityAndExternalURLRoutingAndDeepLinkDeduplication() async throws {
        let biometrics = PendingBiometricAuthService()
        let root = try makeRoot(biometrics: biometrics)
        let window = TestWindow.attach(root)
        defer { withExtendedLifetime(window) {} }

        let standardTabID = try XCTUnwrap(root.selectedTabID)
        root.createNewTab(isPrivate: true)
        XCTAssertTrue(root.resolvedScopeIsPrivate())
        XCTAssertTrue(root.privacyShieldView.isHidden)

        // App Switcher transition (.inactive) immediately covers Private Browsing above all chrome.
        root.handleScenePhase(.inactive)
        XCTAssertFalse(root.privacyShieldView.isHidden)
        XCTAssertTrue(root.view.subviews.last === root.privacyShieldView)

        root.handleScenePhase(.background)
        XCTAssertFalse(root.privacyShieldView.isHidden)
        XCTAssertTrue(root.isPrivateSessionLocked)

        // Foregrounding while Face ID prompt is awaiting must keep shield visible until authenticated.
        root.handleScenePhase(.active)
        await waitUntil { biometrics.hasPendingPrompt }
        XCTAssertFalse(root.privacyShieldView.isHidden)

        biometrics.resolve(true)
        await waitUntil { !root.isPrivateSessionLocked }
        XCTAssertTrue(root.privacyShieldView.isHidden)

        // External deep link while locked/private must switch back to Standard and clear lock.
        root.isPrivateSessionLocked = true
        root.updatePrivacyShieldVisibility()
        XCTAssertFalse(root.privacyShieldView.isHidden)

        let deepLink = try XCTUnwrap(URL(string: "https://example.com/shared-article"))
        root.openExternalURL(deepLink)
        XCTAssertEqual(root.selectedTabID, standardTabID)
        XCTAssertFalse(root.resolvedScopeIsPrivate())
        XCTAssertFalse(root.isPrivateSessionLocked)
        XCTAssertTrue(root.privacyShieldView.isHidden)

        // Duplicate SwiftUI updateUIViewController invocations for the same URL fire only once until cleared.
        let coordinator = BrowserContainerView.Coordinator(scenePhase: .active)
        coordinator.controller = root
        let initialCount = root.tabs.count
        var clearCount = 0
        let newTabURL = try XCTUnwrap(URL(string: "outerview://newtab"))

        coordinator.dispatchPendingURL(newTabURL, into: root) { _ in clearCount += 1 }
        coordinator.dispatchPendingURL(newTabURL, into: root) { _ in clearCount += 1 }
        XCTAssertEqual(root.tabs.count, initialCount + 1)

        await waitUntil { clearCount == 1 }
        coordinator.dispatchPendingURL(newTabURL, into: root) { _ in clearCount += 1 }
        XCTAssertEqual(root.tabs.count, initialCount + 2)
    }

    // MARK: - Private Entry Gate Coverage

    /// Every private-entry path runs the authenticated gate; the tab menu item
    /// must authenticate exactly once and re-assert the shield after creating.
    func testTabMenuNewPrivateTabRunsAuthenticatedGateAndReassertsShield() async throws {
        let biometrics = CountingBiometricAuthService()
        let root = try makeRoot(biometrics: biometrics)
        let window = TestWindow.attach(root)
        defer { withExtendedLifetime(window) {} }

        root.createNewTab(isPrivate: true)
        root.switchToStandardMode()
        XCTAssertFalse(root.resolvedScopeIsPrivate())
        XCTAssertTrue(root.shouldRequireBiometricsForPrivateMode)

        let menu = root.makeTabGroupMenu()
        let newPrivateAction = try XCTUnwrap(menuAction(named: "New Private Tab", in: menu))
        XCTAssertFalse(newPrivateAction.attributes.contains(.disabled))

        // Backgrounded private scope with a stale shield: ungated creation would
        // expose the new private tab without re-evaluating shield visibility.
        root.updatePrivacyShieldVisibility()
        XCTAssertTrue(root.privacyShieldView.isHidden)
        root.isPrivacyBackgrounded = true
        XCTAssertTrue(root.privacyShieldView.isHidden)

        root.requestNewPrivateTab()
        await waitUntil { biometrics.authenticateCallCount == 1 && root.resolvedScopeIsPrivate() }

        XCTAssertEqual(biometrics.authenticateCallCount, 1)
        XCTAssertTrue(root.resolvedScopeIsPrivate())
        XCTAssertEqual(root.tabs.filter(\.isPrivate).count, 2)
        XCTAssertFalse(root.privacyShieldView.isHidden)
    }

    // MARK: - High #9: TabCardCell Reuse Mid-Close-Animation Race

    func testTabCardCellReuseMidCloseAnimationDoesNotTriggerReboundOnClose() async {
        let cell = TabCardCell(frame: CGRect(x: 0, y: 0, width: 180, height: 240))
        // Anchoring to a window lets the close animation actually install and run.
        let window = TestWindow.attach(cell)
        defer { withExtendedLifetime(window) {} }
        let itemA = TabOverviewItem(title: "Tab A", host: "a.com", url: URL(string: "https://a.com"), isPrivate: false)
        let itemB = TabOverviewItem(title: "Tab B", host: "b.com", url: URL(string: "https://b.com"), isPrivate: false)

        var closedA = false
        var closedB = false

        cell.configure(with: itemA, preview: nil, isSelected: false)
        cell.onClose = { closedA = true }
        cell.handleCloseTap()

        // Let the close animation run so it is genuinely in flight when the cell is reused.
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(cell.isCloseButtonAnimating)

        // Simulate UICollectionView dequeuing and rebinding the same cell immediately for Tab B.
        cell.prepareForReuse()
        XCTAssertFalse(cell.isCloseButtonAnimating)
        XCTAssertTrue(cell.isUserInteractionEnabled)
        cell.configure(with: itemB, preview: nil, isSelected: false)
        cell.onClose = { closedB = true }

        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(closedA)
        XCTAssertFalse(closedB)
    }

    // MARK: - High #10: TabOverview Preview Downsampling & Purge

    func testTabOverviewPreviewCacheDownsamplesTrimsAndClearsOnMemoryWarning() {
        let overview = TabOverviewViewController()
        overview.loadViewIfNeeded()

        let tabA = TabOverviewItem(title: "A", host: "a.com", url: URL(string: "https://a.com"), isPrivate: false)
        let tabB = TabOverviewItem(title: "B", host: "b.com", url: URL(string: "https://b.com"), isPrivate: false)
        overview.configure(tabs: [tabA, tabB], selectedID: tabA.id, mode: .standard)

        let oversized = makeSolidImage(size: CGSize(width: 1200, height: 1600), scale: 1)
        overview.setPreview(oversized, for: tabA.id)
        overview.setPreview(oversized, for: tabB.id)

        let cachedA = overview.previewImage(for: tabA.id)
        XCTAssertNotNil(cachedA)
        if let cachedA {
            XCTAssertLessThan(cachedA.size.width * cachedA.scale, 1200)
            XCTAssertLessThan(cachedA.size.height * cachedA.scale, 1600)
        }

        overview.configure(tabs: [tabA], selectedID: tabA.id, mode: .standard)
        overview.trimHiddenPreviews()
        XCTAssertNil(overview.previewImage(for: tabB.id))
        XCTAssertNotNil(overview.previewImage(for: tabA.id))

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNil(overview.previewImage(for: tabA.id))
    }

    // MARK: - Medium #11: Dynamic ElementContextActions Tab Groups

    func testElementContextMenuReflectsTabGroupCreatedAfterActionsCreation() throws {
        let root = try makeRoot()
        let actions = root.makeElementContextActions()
        let linkURL = try XCTUnwrap(URL(string: "https://example.com/doc"))

        let createdGroup = try root.tabStore?.createGroup(name: "Research")
        XCTAssertNotNil(createdGroup)

        let menu = ElementContextMenu.menu(for: .link(url: linkURL), actions: actions)
        let groupSubmenu = menu.children
            .compactMap { $0 as? UIMenu }
            .first(where: { $0.title == "Open in Tab Group" })

        XCTAssertNotNil(groupSubmenu)
        let actionTitles = groupSubmenu?.children.compactMap { ($0 as? UIAction)?.title } ?? []
        XCTAssertTrue(actionTitles.contains("Research"))
    }

    // MARK: - Medium #12: Standard Transfer Handoff Orphan Row Guard

    func testStartStandardTransferFailsPreRegisteredRowWhenPageDeallocatesAndServiceUnwired() async throws {
        let directory = try makeDirectory()
        let manager = DownloadsManager(directoryURL: directory)
        let service = BackgroundDownloadService.shared
        let previousManager = service.manager
        defer { service.manager = previousManager }
        service.manager = nil

        weak var weakPage: WebPageController?
        do {
            let page = WebPageController(configuration: WKWebViewConfiguration())
            weakPage = page
            page.downloadsManager = manager
            let request = try URLRequest(url: XCTUnwrap(URL(string: "https://example.com/archive.zip")))
            page.startStandardTransfer(to: service, request: request, suggestedName: "archive.zip")
        }

        await waitUntil { weakPage == nil && manager.rows.first?.state != .inProgress }

        XCTAssertNil(weakPage)
        XCTAssertEqual(manager.rows.count, 1)
        XCTAssertEqual(manager.rows.first?.state, .failed("Download service unavailable"))
    }

    // MARK: - Private-Scope Save Gate & PDF Export Ephemerality

    func testPrivateTabNeverCreatesReadingListItemOrBookmarkRow() async throws {
        let root = try makeRoot()
        let window = TestWindow.attach(root)
        defer { withExtendedLifetime(window) {} }
        let readingList = try XCTUnwrap(root.readingListStore)
        let bookmarks = try XCTUnwrap(root.bookmarkStore)
        let privateURL = try XCTUnwrap(URL(string: "https://private.example/one-time-link"))
        // Start clean so a leftover export from another suite cannot fail the check.
        try? FileManager.default.removeItem(at: BrowserRootViewController.pdfExportDirectory)

        root.createNewTab(isPrivate: true)
        let page = try XCTUnwrap(root.activePage())
        page.webView.loadHTMLString("<html><body>secret</body></html>", baseURL: privateURL)
        await waitUntil { page.snapshot.url == privateURL }

        XCTAssertTrue(page.isPrivateTab)
        XCTAssertTrue(root.resolvedScopeIsPrivate())

        let model = root.makePageMenuModel()
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.canAddToReadingList)
        XCTAssertFalse(model.canSavePDF)
        // Printing never writes a file, so the print row stays available.
        XCTAssertTrue(model.canPrint)

        let menu = root.makePageMenu(model: model)
        for title in ["Add Bookmark", "Add to Favorites", "Add to Reading List", "Save as PDF"] {
            let action = try XCTUnwrap(menuAction(named: title, in: menu), title)
            XCTAssertTrue(action.attributes.contains(.disabled), title)
        }

        root.addActivePageToReadingList()
        root.addActivePageToFavorites()
        root.presentAddBookmarkSheet()
        root.saveActivePageAsPDF()

        // Direct editor saves for the private URL are dropped too.
        root.activeBookmarkEditorModel = BookmarkEditorModel(
            target: .addBookmark(title: "Secret", url: privateURL)
        )
        root.saveBookmarkEditor()

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertTrue(readingList.fetchAll().isEmpty)
        XCTAssertTrue(bookmarks.fetchAll().isEmpty)
        XCTAssertFalse(root.isBookmarkEditorVisible)
        let exports = (try? FileManager.default.contentsOfDirectory(
            at: BrowserRootViewController.pdfExportDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(exports.isEmpty)
    }

    func testPrivateScopeBulkBookmarkSaveNeverReachesStore() async throws {
        let root = try makeRoot()
        let window = TestWindow.attach(root)
        defer { withExtendedLifetime(window) {} }
        let bookmarks = try XCTUnwrap(root.bookmarkStore)
        let firstURL = try XCTUnwrap(URL(string: "https://private.example/one-time-a"))
        let secondURL = try XCTUnwrap(URL(string: "https://private.example/one-time-b"))

        root.setOverviewMode(.privateMode)
        root.createNewTab(isPrivate: true)
        let firstPage = try XCTUnwrap(root.activePage())
        firstPage.webView.loadHTMLString("<html><body>a</body></html>", baseURL: firstURL)
        await waitUntil { firstPage.snapshot.url == firstURL }

        root.createNewTab(isPrivate: true)
        let secondPage = try XCTUnwrap(root.activePage())
        secondPage.webView.loadHTMLString("<html><body>b</body></html>", baseURL: secondURL)
        await waitUntil { secondPage.snapshot.url == secondURL }
        await waitUntil {
            let privateRecords = root.tabs.filter(\.isPrivate)
            return privateRecords.count == 2 && privateRecords.allSatisfy { $0.url != nil }
        }

        XCTAssertTrue(root.resolvedScopeIsPrivate())
        let menu = root.makeBookmarksButtonMenu()
        XCTAssertNil(menuAction(named: "Add Bookmarks for 2 Tabs", in: menu))
        for title in ["Add to Reading List", "Add Bookmark", "Add to Favorites"] {
            let action = try XCTUnwrap(menuAction(named: title, in: menu), title)
            XCTAssertTrue(action.attributes.contains(.disabled), title)
        }

        // Direct bulk presentation fails closed, and a bypassed editor save is
        // dropped by the target gate as well.
        root.presentAddBookmarksForTabsSheet(tabs: [
            (title: "One", url: firstURL),
            (title: "Two", url: secondURL)
        ])
        XCTAssertNil(root.activeBookmarkEditorModel)

        root.activeBookmarkEditorModel = BookmarkEditorModel(
            target: .addFolderForTabs(
                defaultTitle: "Saved Tabs",
                tabs: [(title: "One", url: firstURL), (title: "Two", url: secondURL)]
            )
        )
        root.saveBookmarkEditor()

        XCTAssertTrue(bookmarks.fetchAll().isEmpty)
        XCTAssertTrue(bookmarks.fetchAllFolders().isEmpty)
        XCTAssertFalse(root.isBookmarkEditorVisible)
    }

    func testPrivateScopeCannotRemovePersistedFavoriteOrReadingListItem() async throws {
        let root = try makeRoot()
        let window = TestWindow.attach(root)
        defer { withExtendedLifetime(window) {} }
        let bookmarks = try XCTUnwrap(root.bookmarkStore)
        let readingList = try XCTUnwrap(root.readingListStore)
        let storedURL = try XCTUnwrap(URL(string: "https://standard.example/stored"))

        try bookmarks.upsertFavorite(url: storedURL, title: "Favorite")
        try readingList.add(title: "Saved", url: storedURL)

        root.createNewTab(isPrivate: true)
        let page = try XCTUnwrap(root.activePage())
        page.webView.loadHTMLString("<html><body>private</body></html>", baseURL: storedURL)
        await waitUntil { page.snapshot.url == storedURL }

        // Both removals would clear persisted, CloudKit-synced rows.
        root.removeActivePageFromFavorites()
        root.removeActivePageFromReadingList()

        XCTAssertTrue(bookmarks.isFavorite(url: storedURL))
        XCTAssertTrue(readingList.fetchAll().contains { $0.url == storedURL })
    }

    func testStandardScopeBulkBookmarkSavePersistsFolderAndEveryTab() throws {
        let root = try makeRoot()
        root.loadViewIfNeeded()
        let bookmarks = try XCTUnwrap(root.bookmarkStore)
        let firstURL = try XCTUnwrap(URL(string: "https://standard.example/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://standard.example/two"))

        root.presentAddBookmarksForTabsSheet(tabs: [
            (title: "One", url: firstURL),
            (title: "Two", url: secondURL)
        ])
        let model = try XCTUnwrap(root.activeBookmarkEditorModel)
        XCTAssertTrue(model.isValid)
        root.saveBookmarkEditor()

        XCTAssertTrue(bookmarks.fetchAll().contains { $0.url == firstURL })
        XCTAssertTrue(bookmarks.fetchAll().contains { $0.url == secondURL })
        XCTAssertEqual(bookmarks.fetchAllFolders().count, 1)
        XCTAssertFalse(root.isBookmarkEditorVisible)
    }

    func testStandardScopeKeepsSaveRowsEnabled() async throws {
        let root = try makeRoot()
        let window = TestWindow.attach(root)
        defer { withExtendedLifetime(window) {} }
        let standardURL = try XCTUnwrap(URL(string: "https://standard.example/page"))

        let page = try XCTUnwrap(root.activePage())
        page.webView.loadHTMLString("<html><body>public</body></html>", baseURL: standardURL)
        await waitUntil { page.snapshot.url == standardURL }

        let model = root.makePageMenuModel()
        XCTAssertFalse(page.isPrivateTab)
        XCTAssertTrue(model.canSave)
        XCTAssertTrue(model.canAddToReadingList)
        XCTAssertTrue(model.canSavePDF)
    }

    func testBackgroundTransitionPurgesRenderedPDFExports() throws {
        let root = try makeRoot()
        root.loadViewIfNeeded()
        let directory = BrowserRootViewController.pdfExportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let export = directory.appendingPathComponent("rendered-page.pdf")
        try Data("page-content".utf8).write(to: export)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        root.handleScenePhase(.background)

        // Suspended apps cannot finish a share cleanup, so no PDF survives.
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.path))
    }
}

// MARK: - Test Support Doubles

@MainActor
private final class SpyLaunchHandlerStore: BackgroundLaunchHandlerStore {
    private var handler: (() -> Void)?

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func popLaunchHandler(for _: String) -> (() -> Void)? {
        let current = handler
        handler = nil
        return current
    }
}

/// Hollow WKDownload identity double for DownloadsManager tracking tests.
/// Directly constructed downloads have no WebKit internals, so every WebKit-facing
/// member is stubbed, and the double is pinned: hollow deallocation traps in WebKit.
@MainActor
private final class StubDownload: WKDownload {
    /// Strong registry keeping doubles alive so WebKit's dealloc never runs on them.
    private static let pinned: NSMutableArray = []

    override init() {
        super.init()
        Self.pinned.add(self)
    }

    override var delegate: WKDownloadDelegate? {
        get { nil }
        set {}
    }

    override var progress: Progress {
        Progress()
    }

    override func cancel(_ completionHandler: (@MainActor (Data?) -> Void)?) {
        completionHandler?(nil)
    }
}

private final class StubServerTrustProtectionSpace: URLProtectionSpace, @unchecked Sendable {
    private let stubTrust: SecTrust

    init(host: String, trust: SecTrust) {
        self.stubTrust = trust
        super.init(
            host: host,
            port: 443,
            protocol: NSURLProtectionSpaceHTTPS,
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var serverTrust: SecTrust? {
        stubTrust
    }
}

private final class AlwaysDismissingViewController: UIViewController {
    override var isBeingDismissed: Bool {
        true
    }
}

private final class DummyAuthChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_: URLCredential, for _: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for _: URLAuthenticationChallenge) {}
    func cancel(_: URLAuthenticationChallenge) {}
}

private final class LockedEvents: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [String]())

    func append(_ value: String) {
        state.withLock { $0.append(value) }
    }

    func snapshot() -> [String] {
        state.withLock { $0 }
    }
}

@MainActor
private final class CountingBiometricAuthService: BiometricAuthenticating {
    let isAvailable = true
    private(set) var authenticateCallCount = 0

    func authenticate(reason _: String) async -> Bool {
        authenticateCallCount += 1
        return true
    }
}

@MainActor
private final class PendingBiometricAuthService: BiometricAuthenticating, @unchecked Sendable {
    let isAvailable = true
    private let lock = OSAllocatedUnfairLock<CheckedContinuation<Bool, Never>?>(initialState: nil)

    var hasPendingPrompt: Bool {
        lock.withLock { $0 != nil }
    }

    func authenticate(reason _: String) async -> Bool {
        await withCheckedContinuation { continuation in
            lock.withLock { existing in
                existing = continuation
            }
        }
    }

    func resolve(_ granted: Bool) {
        let continuation = lock.withLock { slot -> CheckedContinuation<Bool, Never>? in
            let current = slot
            slot = nil
            return current
        }
        continuation?.resume(returning: granted)
    }
}
