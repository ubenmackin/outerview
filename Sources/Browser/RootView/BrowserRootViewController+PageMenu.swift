//
//  BrowserRootViewController+PageMenu.swift
//  OuterView
//

import os
import SwiftUI
import UIKit

extension BrowserRootViewController {
    // MARK: - Page menu

    func makePageMenuModel() -> PageMenuModel {
        let snapshot = activePage()?.snapshot
        let isFav = (snapshot?.url).map { bookmarkStore?.isFavorite(url: $0) ?? false } ?? false
        return PageMenuModel(
            url: snapshot?.url,
            canGoBack: snapshot?.canGoBack ?? false,
            canGoForward: snapshot?.canGoForward ?? false,
            isFavorite: isFav
        )
    }

    func makePageMenu() -> UIMenu {
        let model = makePageMenuModel()

        // 1. Palette row (Back, Forward, Reload, Share)
        let backAction = UIAction(
            title: "Back",
            image: UIImage(systemName: "chevron.left"),
            attributes: model.canGoBack ? [] : .disabled
        ) { [weak self] _ in
            self?.activePage()?.goBack()
        }

        let forwardAction = UIAction(
            title: "Forward",
            image: UIImage(systemName: "chevron.right"),
            attributes: model.canGoForward ? [] : .disabled
        ) { [weak self] _ in
            self?.activePage()?.goForward()
        }

        let reloadAction = UIAction(
            title: "Reload",
            image: UIImage(systemName: "arrow.clockwise"),
            attributes: model.canReload ? [] : .disabled
        ) { [weak self] _ in
            self?.activePage()?.reload()
        }

        let shareAction = UIAction(
            title: "Share",
            image: UIImage(systemName: "square.and.arrow.up"),
            attributes: model.canShare ? [] : .disabled
        ) { [weak self] _ in
            self?.shareActivePage()
        }

        let paletteMenu = UIMenu(options: [.displayInline, .displayAsPalette], children: [
            backAction,
            forwardAction,
            reloadAction,
            shareAction
        ])

        // 2. Save actions (Add Bookmark, Add/Remove from Favorites)
        let addBookmarkAction = UIAction(
            title: "Add Bookmark",
            image: UIImage(systemName: "book"),
            attributes: model.canSave ? [] : .disabled
        ) { [weak self] _ in
            self?.presentAddBookmarkSheet()
        }

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

        let saveMenu = UIMenu(options: .displayInline, children: [
            addBookmarkAction,
            favoriteAction
        ])

        // 3. Navigation actions (Start Page, Find, Settings)
        let startPageAction = UIAction(
            title: "Open Start Page",
            image: UIImage(systemName: "square.grid.2x2")
        ) { [weak self] _ in
            self?.openStartPageFromMenu()
        }

        let findAction = UIAction(
            title: "Find on Page",
            image: UIImage(systemName: "text.magnifyingglass"),
            attributes: model.canFind ? [] : .disabled
        ) { [weak self] _ in
            self?.findOnPageFromMenu()
        }

        let settingsAction = UIAction(
            title: "Settings…",
            image: UIImage(systemName: "gear")
        ) { [weak self] _ in
            self?.presentSettings()
        }

        let navMenu = UIMenu(options: .displayInline, children: [
            startPageAction,
            findAction,
            settingsAction
        ])

        return UIMenu(title: "", children: [paletteMenu, saveMenu, navMenu])
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
        guard let snapshot = activePage()?.snapshot, let url = snapshot.url else { return }
        var items: [Any] = [url]
        if let title = snapshot.title, !title.isEmpty {
            items.append(title)
        }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        presentPopover(activity)
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
        guard let settings = makeSettingsController() else { return }
        present(settings, animated: true)
    }

    func openStartPageFromMenu() {
        showStartPageForActiveTab()
        applyBrowsingResumed(animated: true)
    }

    func findOnPageFromMenu() {
        beginEditing()
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
