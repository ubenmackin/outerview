// RootView — Scene phase handling, biometrics gate, content blocking, and fold transitions.

import OSLog
import SwiftUI
import UIKit

extension BrowserRootViewController {
    // MARK: - App lifecycle

    /// Single gate for private entry; failure restores standard chrome.
    func requestPrivateMode(authenticatedApply: @escaping @MainActor () -> Void) {
        guard shouldRequireBiometricsForPrivateMode else {
            authenticatedApply()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            if await self.biometricAuthService.authenticate(reason: "Unlock Private Browsing") {
                authenticatedApply()
            } else {
                self.overviewController.applySelectionBatched(mode: .standard, groupID: nil, notify: false)
                self.switchToStandardMode()
            }
        }
    }

    /// Scene changes forwarded from the app entry. Persistence is owned by the
    /// restore coordinator; background fails foreground transfers, active only
    /// refreshes pool recency. Chrome state is intentionally untouched.
    func handleScenePhase(_ phase: ScenePhase) {
        restoreCoordinator?.handleScenePhase(phase)
        if phase == .background {
            // Suspend fail-closed: private work fails, daemon tasks survive.
            downloadsManager.suspendForegroundDownloads()
            // Any private tab locks, even when standard is frontmost.
            if isBiometricAuthEnabled, tabs.contains(where: \.isPrivate) {
                isPrivateSessionLocked = true
            }
        }
        if phase == .active {
            let selectedIsPrivate = tabs.first(where: { $0.id == selectedTabID })?.isPrivate ?? false
            let isPrivateVisible = overviewMode.isPrivate || selectedIsPrivate
            if isPrivateSessionLocked, isPrivateVisible, shouldRequireBiometricsForPrivateMode {
                Task { [weak self] in
                    guard let self else { return }
                    let authenticated = await self.biometricAuthService.authenticate(reason: "Unlock Private Browsing")
                    if authenticated {
                        self.isPrivateSessionLocked = false
                        self.markActivePageActivated()
                    } else {
                        // Fail-closed to standard; clear lock so standard never re-prompts.
                        self.isPrivateSessionLocked = false
                        self.switchToStandardMode()
                    }
                }
                return
            }
            // Standard browsing never re-prompts: stale lock clears outside private.
            if !isPrivateVisible || !shouldRequireBiometricsForPrivateMode {
                isPrivateSessionLocked = false
            }
            markActivePageActivated()
        }
    }

    func logPersistenceError(_ error: Error, operation: String) {
        Logger(subsystem: "com.volcrypt.OuterView", category: "BrowserRoot")
            .error("\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Single live owner for the tracker toggle: shared configs cover future
    /// tabs while live web views update in place with no restart.
    func applyContentBlockerEnabled(_ enabled: Bool) {
        Task { [weak self] in
            guard let self else { return }
            let controllers = [self.tabPool.configuration(isPrivate: false).userContentController,
                               self.tabPool.configuration(isPrivate: true).userContentController]
                + self.tabPool.pages.compactMap { $0.page?.webView.configuration.userContentController }
            await ContentBlockerService.shared.setEnabled(enabled, controllers: controllers)
        }
    }

    func observeContentBlockerChanges() {
        guard !hasContentBlockerObserver() else { return }
        let observer = NotificationCenter.default.addObserver(forName: .outerViewContentBlockerChanged, object: nil, queue: .main) { [weak self] note in
            let posted = note.userInfo?["enabled"] as? Bool
            Task { [weak self, posted] in
                await self?.applyPostedContentBlockerChange(posted)
            }
        }
        storeContentBlockerObserver(observer)
    }

    private func applyPostedContentBlockerChange(_ posted: Bool?) {
        let enabled = posted ?? (selectionDefaults.object(forKey: SettingsViewModel.blockTrackersDefaultsKey) as? Bool ?? true)
        applyContentBlockerEnabled(enabled)
    }

    // MARK: - Fold handling

    func scheduleStructuralUpdate() {
        cancelStructuralTask()
        storeStructuralTask(Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.structuralDebounceInterval * 1_000_000_000))
            } catch is CancellationError {
                return
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "BrowserRoot")
                    .error("structural update sleep failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard !Task.isCancelled else { return }
            self?.applyStructuralLayout()
        })
    }

    func applyStructuralLayout() {
        let placement = chromePlacement
        if syncVerticalBarPlacement(to: placement) {
            verticalBarConfigurationUpdateCount += 1
            setNeedsUpdateOfVerticalBarConfiguration()
        }
        applyChromePlacement(for: placement)
        editorView.chromePlacement = placement
        overviewController.isRegular = (placement == .regular)
        overviewController.showsInlineCommands = (interfaceMode == .nonDuoPhone || interfaceMode == .duoInnerOrPadPortrait)
        bookmarksLibraryView.isNonDuoPhone = (interfaceMode == .nonDuoPhone || interfaceMode == .duoInnerOrPadPortrait)
        bookmarksLibraryView.isMode4 = (interfaceMode == .duoInnerOrPadPortrait)
        for overlay in [libraryOverlay, settingsOverlay, downloadsOverlay, bookmarkEditorOverlay]
            where overlay.isHidden
        {
            overlay.applyPlacement(for: placement)
        }
        if !isLibraryVisible {
            bookmarksLibraryView.applyPlacement(for: placement)
        } else if placement == .compact, let sheet = librarySheetController {
            sheet.onDidDismiss = nil
            sheet.dismiss(animated: false)
            sheet.detachLibraryView()
            librarySheetController = nil
            if bookmarksLibraryView.superview !== view {
                view.addSubview(bookmarksLibraryView)
                NSLayoutConstraint.activate(libraryCompactConstraints)
            }
            bookmarksLibraryView.applyPlacement(for: .compact)
            bookmarksLibraryView.isHidden = false
        }
        if isEditingAddress, let id = selectedTabID, peekActivePage()?.snapshot.url != nil {
            if placement == .regular {
                forcedStartPageTabs.remove(id)
            } else {
                forcedStartPageTabs.insert(id)
            }
        }
        updateTabStrip()
        updateTopBarPinning(for: placement)
        updateHeaderBackgrounds()
        updateStartPageTop()
        refreshForActiveSnapshot()
        applyChromeViews(animated: false)
        applyContentInsets()
        view.setNeedsLayout()
    }
}
