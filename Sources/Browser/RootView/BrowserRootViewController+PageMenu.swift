// RootView — Page-menu composition plus print and PDF actions.

import os
import SwiftUI
import UIKit

extension BrowserRootViewController {
    // MARK: - Page menu

    func makePageMenuModel() -> PageMenuModel {
        let page = activePage()
        let snapshot = page?.snapshot
        let url = snapshot?.url
        let hasPage = url.map(URLNormalizer.isLoadable) ?? false
        let isFav = url.map { bookmarkStore?.isFavorite(url: $0) ?? false } ?? false
        let isInList: Bool = if let url, let readingListStore {
            readingListStore.fetchAll().contains(where: { $0.url == url })
        } else {
            false
        }
        let readerActive = page?.isReaderActive ?? false
        let readerBlocked = page?.isReaderUnavailable ?? false
        let isDesktop = page?.effectiveDesktopMode ?? false
        return PageMenuModel(
            url: url,
            canGoBack: snapshot?.canGoBack ?? false,
            canGoForward: snapshot?.canGoForward ?? false,
            isFavorite: isFav,
            canAddToReadingList: hasPage,
            isInReadingList: isInList,
            isReaderActive: readerActive,
            isReaderAvailable: readerActive || (hasPage && !readerBlocked),
            textZoom: page?.currentTextZoom() ?? SiteZoomStore.defaultZoom,
            canOpenDownloads: true,
            isDesktopMode: isDesktop,
            canToggleDesktopMode: hasPage,
            canPrint: hasPage,
            canEditWebsiteSettings: hasPage
        )
    }

    func makePageMenu() -> UIMenu {
        makePageMenu(model: makePageMenuModel())
    }

    /// Builds the menu from an explicit model so ordering and labels stay
    /// testable without driving a live web page.
    func makePageMenu(model: PageMenuModel) -> UIMenu {
        UIMenu(title: "", children: [
            makePaletteMenu(model: model),
            makeAppMenu(model: model),
            makeToolMenu(model: model),
            makeSaveMenu(model: model)
        ])
    }

    private func makePaletteMenu(model: PageMenuModel) -> UIMenu {
        let backAction = UIAction(
            title: "Back",
            image: UIImage(systemName: "chevron.left"),
            attributes: model.canGoBack ? [] : .disabled
        ) { [weak self] _ in
            self?.activePage()?.goBack()
        }
        backAction.accessibilityLabel = "Back"
        let forwardAction = UIAction(
            title: "Forward",
            image: UIImage(systemName: "chevron.right"),
            attributes: model.canGoForward ? [] : .disabled
        ) { [weak self] _ in
            self?.activePage()?.goForward()
        }
        forwardAction.accessibilityLabel = "Forward"
        let reloadAction = UIAction(
            title: "Reload",
            image: UIImage(systemName: "arrow.clockwise"),
            attributes: model.canReload ? [] : .disabled
        ) { [weak self] _ in
            self?.activePage()?.reload()
        }
        reloadAction.accessibilityLabel = "Reload"
        let shareAction = UIAction(
            title: "Share",
            image: UIImage(systemName: "square.and.arrow.up"),
            attributes: model.canShare ? [] : .disabled
        ) { [weak self] _ in
            self?.shareActivePage()
        }
        shareAction.accessibilityLabel = "Share"
        return UIMenu(options: [.displayInline, .displayAsPalette], children: [
            backAction,
            forwardAction,
            reloadAction,
            shareAction
        ])
    }

    private func makeAppMenu(model: PageMenuModel) -> UIMenu {
        let websiteSettingsAction = UIAction(
            title: "Website Settings…",
            image: UIImage(systemName: "gearshape"),
            attributes: model.canEditWebsiteSettings ? [] : .disabled
        ) { [weak self] _ in
            self?.presentWebsiteSettings()
        }
        websiteSettingsAction.accessibilityLabel = "Website Settings"
        let settingsAction = UIAction(
            title: "Settings…",
            image: UIImage(systemName: "gear")
        ) { [weak self] _ in
            self?.presentSettings()
        }
        settingsAction.accessibilityLabel = "Settings"
        return UIMenu(options: .displayInline, children: [
            websiteSettingsAction,
            settingsAction
        ])
    }

    private func makeSaveMenu(model: PageMenuModel) -> UIMenu {
        var saveChildren: [UIMenuElement] = []
        if model.showsReaderItem {
            let readerAction = UIAction(
                title: model.readerTitle,
                image: UIImage(systemName: "book.pages"),
                attributes: model.canFind ? [] : .disabled
            ) { [weak self] _ in
                self?.toggleReaderFromMenu()
            }
            readerAction.accessibilityLabel = model.readerTitle
            saveChildren.append(readerAction)
        }
        let readingListAction = if model.isInReadingList {
            UIAction(
                title: model.readingListTitle,
                image: UIImage(systemName: "eyeglasses"),
                attributes: model.canAddToReadingList ? [] : .disabled
            ) { [weak self] _ in
                self?.removeActivePageFromReadingList()
            }
        } else {
            UIAction(
                title: model.readingListTitle,
                image: UIImage(systemName: "eyeglasses"),
                attributes: model.canAddToReadingList ? [] : .disabled
            ) { [weak self] _ in
                self?.addActivePageToReadingList()
            }
        }
        readingListAction.accessibilityLabel = model.readingListTitle
        saveChildren.append(readingListAction)
        saveChildren.append(makeSaveSubmenu(model: model))
        saveChildren.append(makePrintSubmenu(model: model))
        return UIMenu(options: .displayInline, children: saveChildren)
    }

    private func makeSaveSubmenu(model: PageMenuModel) -> UIMenu {
        let addBookmarkAction = UIAction(
            title: "Add Bookmark",
            image: UIImage(systemName: "book"),
            attributes: model.canSave ? [] : .disabled
        ) { [weak self] _ in
            self?.presentAddBookmarkSheet()
        }
        addBookmarkAction.accessibilityLabel = "Add Bookmark"
        let favoriteAction = if model.isFavorite {
            UIAction(
                title: "Remove from Favorites",
                image: UIImage(systemName: "star.slash"),
                attributes: model.canSave ? [] : .disabled
            ) { [weak self] _ in
                self?.removeActivePageFromFavorites()
            }
        } else {
            UIAction(
                title: "Add to Favorites",
                image: UIImage(systemName: "star"),
                attributes: model.canSave ? [] : .disabled
            ) { [weak self] _ in
                self?.addActivePageToFavorites()
            }
        }
        favoriteAction.accessibilityLabel = favoriteAction.title
        let submenu = UIMenu(
            title: "Save",
            image: UIImage(systemName: "bookmark"),
            children: [addBookmarkAction, favoriteAction]
        )
        submenu.accessibilityLabel = "Save"
        return submenu
    }

    private func makePrintSubmenu(model: PageMenuModel) -> UIMenu {
        let printAction = UIAction(
            title: "Print",
            image: UIImage(systemName: "printer"),
            attributes: model.canPrint ? [] : .disabled
        ) { [weak self] _ in
            self?.printActivePage()
        }
        printAction.accessibilityLabel = "Print"
        let pdfAction = UIAction(
            title: "Save as PDF",
            image: UIImage(systemName: "doc.richtext"),
            attributes: model.canPrint ? [] : .disabled
        ) { [weak self] _ in
            self?.saveActivePageAsPDF()
        }
        pdfAction.accessibilityLabel = "Save as PDF"
        let submenu = UIMenu(
            title: "Print and PDF",
            image: UIImage(systemName: "printer"),
            children: [printAction, pdfAction]
        )
        submenu.accessibilityLabel = "Print and PDF"
        return submenu
    }

    private func makeToolMenu(model: PageMenuModel) -> UIMenu {
        let downloadsAction = UIAction(
            title: "Downloads",
            image: UIImage(systemName: "arrow.down.circle"),
            attributes: model.canOpenDownloads ? [] : .disabled
        ) { [weak self] _ in
            self?.presentDownloadsFromMenu()
        }
        downloadsAction.accessibilityLabel = "Downloads"
        let desktopAction = UIAction(
            title: model.desktopModeTitle,
            image: UIImage(systemName: model.isDesktopMode ? "iphone" : "desktopcomputer"),
            attributes: model.canToggleDesktopMode ? [] : .disabled
        ) { [weak self] _ in
            self?.toggleDesktopModeFromMenu()
        }
        desktopAction.accessibilityLabel = model.desktopModeTitle
        let zoomAttributes: UIMenuElement.Attributes = model.canFind ? [] : .disabled
        let zoomInAction = UIAction(
            title: "Zoom In",
            image: UIImage(systemName: "plus.magnifyingglass"),
            attributes: zoomAttributes
        ) { [weak self] _ in
            self?.adjustTextZoom(by: 0.1)
        }
        zoomInAction.accessibilityLabel = "Zoom In"
        let zoomOutAction = UIAction(
            title: "Zoom Out",
            image: UIImage(systemName: "minus.magnifyingglass"),
            attributes: zoomAttributes
        ) { [weak self] _ in
            self?.adjustTextZoom(by: -0.1)
        }
        zoomOutAction.accessibilityLabel = "Zoom Out"
        let resetZoomAction = UIAction(
            title: "Reset",
            image: UIImage(systemName: "arrow.counterclockwise"),
            attributes: zoomAttributes
        ) { [weak self] _ in
            self?.resetTextZoom()
        }
        resetZoomAction.accessibilityLabel = "Reset text zoom"
        let zoomMenu = UIMenu(
            title: "Text Zoom",
            image: UIImage(systemName: "textformat.size"),
            children: [zoomInAction, zoomOutAction, resetZoomAction]
        )
        zoomMenu.accessibilityLabel = "Text Zoom"
        let findAction = UIAction(
            title: "Find on Page",
            image: UIImage(systemName: "text.magnifyingglass"),
            attributes: model.canFind ? [] : .disabled
        ) { [weak self] _ in
            self?.findOnPageFromMenu()
        }
        findAction.accessibilityLabel = "Find on Page"
        return UIMenu(options: .displayInline, children: [
            downloadsAction,
            desktopAction,
            zoomMenu,
            findAction
        ])
    }

    func toggleDesktopModeFromMenu() {
        activePage()?.toggleDesktopMode()
    }

    func presentWebsiteSettings() {
        guard let url = activePage()?.snapshot.url, let host = url.host, !host.isEmpty else { return }
        let store = websiteSettingsStore
        let page = activePage()
        let isPrivate = page?.isPrivateTab ?? true
        let settingsView = WebsiteSettingsView(
            host: host,
            store: store,
            isPrivate: isPrivate,
            onSettingsChanged: { [weak page] newSettings in
                guard let page else { return }
                if page.isDesktopMode != newSettings.requestDesktopWebsite {
                    page.setDesktopMode(newSettings.requestDesktopWebsite)
                }
                if newSettings.useReaderAutomatically, !page.isReaderActive {
                    Task { @MainActor in
                        await page.enterReaderAutomaticallyIfNeeded()
                    }
                }
            },
            onDone: { [weak self] in
                self?.dismiss(animated: true)
            }
        )
        let hosting = UIHostingController(rootView: settingsView)
        hosting.modalPresentationStyle = .pageSheet
        if let sheet = hosting.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
        present(hosting, animated: shouldAnimateModalSheets)
    }

    func showPageMenu() {
        // Fallback for programmatic invocation
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Settings…", style: .default) { [weak self] _ in
            self?.presentSettings()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentPopover(alert)
    }

    func presentAddBookmarkSheet() {
        guard let snapshot = activePage()?.snapshot,
              let url = snapshot.url,
              URLNormalizer.isLoadable(url) else { return }

        let title = HostFormatter.displayTitle(url: url, title: snapshot.title)
        presentBookmarkEditor(for: .addBookmark(title: title, url: url))
    }

    func shareActivePage() {
        guard let page = activePage(), let url = page.snapshot.url else { return }
        let title = page.snapshot.title
        var items: [Any] = [url]
        if let title, !title.isEmpty {
            items.append(title)
        }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        presentPopover(activity)
    }

    func printActivePage() {
        guard let page = activePage(), let url = page.snapshot.url, URLNormalizer.isLoadable(url) else { return }
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = page.snapshot.title ?? url.host ?? "Web Document"
        printController.printInfo = printInfo
        printController.printFormatter = page.webView.viewPrintFormatter()
        if UIDevice.current.userInterfaceIdiom == .pad {
            printController.present(from: pillView.bounds, in: pillView, animated: true)
        } else {
            printController.present(animated: true)
        }
    }

    func saveActivePageAsPDF() {
        guard let page = activePage(), let url = page.snapshot.url, URLNormalizer.isLoadable(url) else { return }
        Task { @MainActor [weak self] in
            do {
                let pdfData: Data = try await withCheckedThrowingContinuation { continuation in
                    page.webView.createPDF { result in
                        continuation.resume(with: result)
                    }
                }
                let titlePrefix = page.snapshot.title.map { String($0.prefix(50)) }
                let rawBase = titlePrefix ?? url.host ?? "Page"
                // Percent-encode to strip separators and controls; truncate to keep filenames bounded.
                let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
                let sanitized = rawBase.addingPercentEncoding(withAllowedCharacters: allowed) ?? "Page"
                let truncated = String(sanitized.prefix(48))
                let baseName = truncated.isEmpty ? "Page" : truncated
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(baseName + "-" + UUID().uuidString + ".pdf")
                try pdfData.write(to: tempURL, options: .atomic)
                let activity = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                // Temp PDF holds page content; remove after the share dismisses.
                activity.completionWithItemsHandler = { _, _, _, _ in
                    do {
                        try FileManager.default.removeItem(at: tempURL)
                    } catch {
                        Logger(subsystem: "com.volcrypt.OuterView", category: "PageMenu")
                            .debug("Removing temp PDF failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                self?.presentPopover(activity)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "PageMenu")
                    .error("createPDF failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func addActivePageToFavorites() {
        guard let snapshot = activePage()?.snapshot, let url = snapshot.url, URLNormalizer.isLoadable(url) else { return }
        let title = HostFormatter.displayTitle(url: url, title: snapshot.title)
        saveFavorite(url: url, title: title)
        updateStartPageContent()
        bookmarksLibraryView.reload()
    }

    func removeActivePageFromFavorites() {
        guard let snapshot = activePage()?.snapshot, let url = snapshot.url, let bookmarkStore else { return }
        do {
            try bookmarkStore.removeFavorite(url: url)
            updateStartPageContent()
            bookmarksLibraryView.reload()
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("removeFavorite failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func presentSettings() {
        presentSettingsSheet()
    }

    func findOnPageFromMenu() {
        beginFind()
    }

    func addActivePageToReadingList() {
        guard let page = activePage(), let url = page.snapshot.url, URLNormalizer.isLoadable(url) else { return }
        let snapshot = page.snapshot
        let title = HostFormatter.displayTitle(url: url, title: snapshot.title)
        do {
            try readingListStore?.add(title: title, url: url)
            bookmarksLibraryView.reload()
        } catch {
            logPersistenceError(error, operation: "addToReadingList")
        }
        Task { @MainActor [weak self, weak page] in
            guard let self, let page else { return }
            let snippet = await page.extractPreviewSnippet()
            if let snippet, !snippet.isEmpty {
                do {
                    try self.readingListStore?.add(title: title, url: url, previewText: snippet)
                    self.bookmarksLibraryView.reload()
                } catch {
                    self.logPersistenceError(error, operation: "updateReadingListSnippet")
                }
            }
            if let item = self.readingListStore?.fetchAll().first(where: { $0.url == url }) {
                // Private pages never persist archive data to disk.
                guard !page.isPrivateTab, !self.overviewMode.isPrivate else { return }
                do {
                    let archiveData: Data = try await withCheckedThrowingContinuation { continuation in
                        page.webView.createWebArchiveData { result in
                            continuation.resume(with: result)
                        }
                    }
                    ReadingListArchiveManager.shared.saveArchive(data: archiveData, for: item.id)
                } catch {
                    Logger(subsystem: "com.volcrypt.OuterView", category: "ReadingList")
                        .error("createWebArchiveData failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func removeActivePageFromReadingList() {
        guard let snapshot = activePage()?.snapshot,
              let url = snapshot.url,
              let id = readingListStore?.fetchAll().first(where: { $0.url == url })?.id
        else { return }
        do {
            try readingListStore?.delete(id: id)
            bookmarksLibraryView.reload()
        } catch {
            logPersistenceError(error, operation: "removeFromReadingList")
        }
    }

    func toggleReaderFromMenu() {
        guard let page = activePage() else { return }
        let url = page.snapshot.url
        Task { @MainActor [weak self, weak page] in
            guard let page else { return }
            let entered = await page.toggleReader()
            guard !Task.isCancelled else { return }
            if !entered, !page.isReaderActive, page.snapshot.url == url {
                self?.presentReaderUnavailable()
            }
        }
    }

    func presentReaderUnavailable() {
        let alert = UIAlertController(
            title: "Reader Not Available",
            message: "This page isn't readable in Reader.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func adjustTextZoom(by delta: Double) {
        guard let page = activePage() else { return }
        page.setTextZoom(page.currentTextZoom() + delta)
    }

    func resetTextZoom() {
        activePage()?.setTextZoom(SiteZoomStore.defaultZoom)
    }

    func setupFind() {
        findView.translatesAutoresizingMaskIntoConstraints = false
        findView.isHidden = true
        view.addSubview(findView)
        let findBottom = findView.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor,
            constant: -Self.pillBottomOffset(for: .expanded, systemBottomInset: view.safeAreaInsets.bottom)
        )
        findBottomConstraint = findBottom
        NSLayoutConstraint.activate([
            findView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            findView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            findView.heightAnchor.constraint(equalToConstant: FindInPageView.barHeight),
            findBottom
        ])
        findView.onTextChanged = { [weak self] text in self?.handleFindQueryChanged(text) }
        findView.onPrevious = { [weak self] in self?.handleFindStep(-1) }
        findView.onNext = { [weak self] in self?.handleFindStep(1) }
        findView.onDone = { [weak self] in self?.endFind() }
    }

    func updateFindBottomOffset() {
        guard let findBottomConstraint else { return }
        let offset = Self.pillBottomOffset(for: .expanded, systemBottomInset: view.safeAreaInsets.bottom)
        if findBottomConstraint.constant != -offset {
            findBottomConstraint.constant = -offset
        }
    }

    func beginFind(initialQuery: String? = nil) {
        if isFindActive {
            if let query = initialQuery {
                findView.setQuery(query)
                handleFindQueryChanged(query)
            }
            return
        }
        isFindActive = true
        pillView.isHidden = true
        findView.isHidden = false
        if let query = initialQuery {
            findView.setQuery(query)
        }
        bringChromeToFront()
        findView.focusSearch()
        if let query = initialQuery {
            handleFindQueryChanged(query)
        }
    }

    func endFind() {
        guard isFindActive else { return }
        isFindActive = false
        findQueryTask?.cancel()
        findStepTask?.cancel()
        findView.resignSearch()
        findView.isHidden = true
        if let page = peekActivePage() {
            Task { [weak page] in await page?.clearFind() }
        }
        applyPillViews(animated: true)
        bringChromeToFront()
    }

    func handleFindQueryChanged(_ text: String) {
        guard let page = peekActivePage() else {
            findView.setMatchCount(total: 0, index: 0)
            return
        }
        findQueryTask?.cancel()
        findQueryTask = Task { @MainActor [weak self, weak page] in
            guard let self, let page else { return }
            let total = await page.findText(text)
            guard !Task.isCancelled, self.isFindActive, self.findView.fieldText == text else { return }
            self.findView.setMatchCount(total: total, index: total > 0 ? 1 : 0)
        }
    }

    func handleFindStep(_ delta: Int) {
        guard let page = peekActivePage() else { return }
        let query = findView.fieldText
        findStepTask?.cancel()
        findStepTask = Task { @MainActor [weak self, weak page] in
            guard let self, let page else { return }
            let index = await page.findStep(delta)
            guard !Task.isCancelled, self.isFindActive, self.findView.fieldText == query else { return }
            self.findView.setMatchIndex(index)
        }
    }

    func setupErrorOverlay() {
        errorContainer.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.backgroundColor = .systemBackground
        errorContainer.isHidden = true
        view.addSubview(errorContainer)
        NSLayoutConstraint.activate([
            errorContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorContainer.topAnchor.constraint(equalTo: view.topAnchor),
            errorContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        errorIconView.contentMode = .scaleAspectFit
        errorIconView.tintColor = .secondaryLabel
        errorIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44)
        errorIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            errorIconView.widthAnchor.constraint(equalToConstant: 48),
            errorIconView.heightAnchor.constraint(equalToConstant: 48)
        ])
        errorTitleLabel.numberOfLines = 0
        errorTitleLabel.textAlignment = .center
        errorTitleLabel.font = .preferredFont(forTextStyle: .headline)
        errorTitleLabel.adjustsFontForContentSizeCategory = true
        errorHostLabel.numberOfLines = 1
        errorHostLabel.textAlignment = .center
        errorHostLabel.font = .preferredFont(forTextStyle: .subheadline)
        errorHostLabel.textColor = .secondaryLabel
        errorHostLabel.adjustsFontForContentSizeCategory = true
        errorDetailLabel.numberOfLines = 0
        errorDetailLabel.textAlignment = .center
        errorDetailLabel.font = .preferredFont(forTextStyle: .body)
        errorDetailLabel.adjustsFontForContentSizeCategory = true
        errorHintLabel.numberOfLines = 0
        errorHintLabel.textAlignment = .center
        errorHintLabel.font = .preferredFont(forTextStyle: .footnote)
        errorHintLabel.textColor = .secondaryLabel
        errorHintLabel.adjustsFontForContentSizeCategory = true
        var retryConfig = UIButton.Configuration.filled()
        retryConfig.title = "Retry"
        retryButton.configuration = retryConfig
        retryButton.accessibilityLabel = "Retry"
        retryButton.addAction(UIAction { [weak self] _ in self?.activePage()?.reload() }, for: .touchUpInside)
        var copyConfig = UIButton.Configuration.plain()
        copyConfig.title = "Copy Error Details"
        copyErrorButton.configuration = copyConfig
        copyErrorButton.accessibilityLabel = "Copy Error Details"
        copyErrorButton.addAction(UIAction { [weak self] _ in self?.copyCurrentErrorDetails() }, for: .touchUpInside)
        errorButtonStack.axis = .vertical
        errorButtonStack.alignment = .center
        errorButtonStack.spacing = 8
        errorButtonStack.addArrangedSubview(retryButton)
        errorButtonStack.addArrangedSubview(copyErrorButton)
        errorStackView.axis = .vertical
        errorStackView.alignment = .center
        errorStackView.spacing = 8
        errorStackView.translatesAutoresizingMaskIntoConstraints = false
        errorStackView.addArrangedSubview(errorIconView)
        errorStackView.addArrangedSubview(errorTitleLabel)
        errorStackView.addArrangedSubview(errorHostLabel)
        errorStackView.addArrangedSubview(errorDetailLabel)
        errorStackView.addArrangedSubview(errorHintLabel)
        errorStackView.addArrangedSubview(errorButtonStack)
        errorStackView.setCustomSpacing(16, after: errorHintLabel)
        errorContainer.addSubview(errorStackView)
        NSLayoutConstraint.activate([
            errorStackView.centerXAnchor.constraint(equalTo: errorContainer.safeAreaLayoutGuide.centerXAnchor),
            errorStackView.centerYAnchor.constraint(equalTo: errorContainer.centerYAnchor),
            errorStackView.leadingAnchor.constraint(greaterThanOrEqualTo: errorContainer.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            errorStackView.trailingAnchor.constraint(lessThanOrEqualTo: errorContainer.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            errorStackView.widthAnchor.constraint(lessThanOrEqualToConstant: 480)
        ])
    }

    func copyCurrentErrorDetails() {
        guard !errorCopyText.isEmpty else { return }
        UIPasteboard.general.string = errorCopyText
    }

    func updateErrorOverlay(for snapshot: WebPageSnapshot) {
        guard let message = snapshot.lastError else {
            errorContainer.isHidden = true
            return
        }
        let error = WebPageError.make(
            code: snapshot.lastErrorCode,
            hasFailedServerTrustChallenge: snapshot.hasFailedServerTrustChallenge,
            detail: message,
            url: snapshot.url
        )
        errorContainer.isHidden = false
        errorIconView.image = UIImage(systemName: error.kind.systemImageName)
        errorIconView.accessibilityLabel = error.title
        errorTitleLabel.text = error.title
        let host = HostFormatter.host(of: snapshot.url)
        errorHostLabel.text = host
        errorHostLabel.isHidden = host.isEmpty
        errorDetailLabel.text = error.detail
        if let hint = error.hint {
            errorHintLabel.text = hint
            errorHintLabel.isHidden = false
        } else {
            errorHintLabel.isHidden = true
        }
        errorCopyText = error.copySummary
        bringChromeToFront()
        UIAccessibility.post(notification: .screenChanged, argument: errorContainer)
    }
}

extension BrowserRootViewController: StartPageViewDelegate {
    func startPage(_: StartPageView, didOpenURL url: URL) {
        if isEditingAddress {
            endEditing(submitted: true)
        }
        clearForcedStartPageForSelectedTab()
        activePage()?.load(url)
        applyBrowsingResumed(animated: true)
    }
}
