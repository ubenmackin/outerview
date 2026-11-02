// RootView — Deterministic screenshot seed for Store screenshots.

import Foundation
import os
import UIKit
import WebKit

extension BrowserRootViewController {
    /// Launch argument presence is read once at process start; entering or
    /// exiting screenshot mode requires a relaunch with no live reload.
    nonisolated static var isScreenshotRun: Bool {
        CommandLine.arguments.contains("-OuterViewScreenshots")
    }

    /// Applies the fixed screenshot fixtures when armed, otherwise returns
    /// without touching stores, tabs, or chrome.
    func applyScreenshotSeedIfNeeded() {
        guard Self.isScreenshotRun else { return }
        do {
            try applyScreenshotSeed()
        } catch {
            // Fail-closed: a partial seed must never masquerade as ready.
            preconditionFailure("Screenshot seed failed: \(error)")
        }
    }

    private func applyScreenshotSeed() throws {
        // Animations off keeps seed layout pixel-stable; restored right
        // after so snapshot waits see the normal animation state.
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        dismissScreenshotOverlays()
        try clearScreenshotEphemera()
        try seedScreenshotStores()
        try seedScreenshotTabs()
        updateStartPageContent()
    }

    /// Closes overview and sheets so screenshots start from browsing chrome.
    private func dismissScreenshotOverlays() {
        if isFindActive {
            endFind()
        }
        if isEditingAddress {
            endEditing(submitted: false)
            clearForcedStartPageForSelectedTab()
        }
        if isOverviewVisible {
            setOverviewVisible(false)
        }
        if isLibraryVisible {
            closeBookmarksLibrary()
        }
        if isSettingsVisible {
            dismissSettingsSheet()
        }
        if isDownloadsVisible {
            dismissDownloadsSheet()
        }
        if isBookmarkEditorVisible {
            dismissBookmarkEditor()
        }
    }

    /// History plus recent searches always reset to empty for screenshots.
    private func clearScreenshotEphemera() throws {
        guard historyStore != nil, recentSearchStore != nil else {
            preconditionFailure("Screenshot seed requires history and search stores")
        }
        try historyStore?.clear()
        try recentSearchStore?.clear()
    }

    private func seedScreenshotStores() throws {
        guard let bookmarkStore, let readingListStore else {
            preconditionFailure("Screenshot seed requires bookmark and reading list stores")
        }
        let existing = bookmarkStore.fetchAll()
        if !existing.isEmpty {
            try bookmarkStore.delete(ids: Set(existing.map(\.id)))
        }
        for (index, fixture) in Self.screenshotFavorites.enumerated() {
            guard let url = fixture.url else { continue }
            _ = try bookmarkStore.add(
                title: fixture.title,
                url: url,
                isFavorite: true,
                sortOrder: index
            )
        }
        for (index, fixture) in Self.screenshotBookmarks.enumerated() {
            guard let url = fixture.url else { continue }
            _ = try bookmarkStore.add(
                title: fixture.title,
                url: url,
                isFavorite: false,
                sortOrder: index
            )
        }
        try readingListStore.clear()
        for fixture in Self.screenshotReadingList {
            guard let url = fixture.url else { continue }
            _ = try readingListStore.add(title: fixture.title, url: url)
        }
    }

    /// Rebuilds exactly two standard tabs: empty Start Page selected plus
    /// a local HTML fixture. The fixture uses inline markup only, so no
    /// network request ever leaves the device during seeding.
    private func seedScreenshotTabs() throws {
        for id in tabs.map(\.id) {
            prunePerTabState(id: id)
            tabPool.delete(id: id)
        }
        tabs.removeAll()
        forcedStartPageTabs.removeAll()
        let first = TabRecord(url: nil, title: nil, isPrivate: false)
        let second = TabRecord(url: nil, title: Self.screenshotFixtureTitle, isPrivate: false)
        tabs = Array([first, second].prefix(Self.maxSeededTabs))
        for record in tabs {
            tabPool.create(record)
        }
        guard let tabStore else {
            preconditionFailure("Screenshot seed requires a tab store")
        }
        try tabStore.saveSession(tabs: tabs, selected: tabs.first?.id)
        guard let selected = tabs.first?.id else {
            preconditionFailure("Screenshot seed requires a selected tab")
        }
        selectedTabID = selected
        displaySelectedTab()
        if tabs.count > 1, let fixtureID = tabs.dropFirst().first?.id {
            tabPool.pages.first(where: { $0.id == fixtureID })?.page?.webView.loadHTMLString(
                Self.screenshotFixtureHTML,
                baseURL: nil
            )
        }
        updateTabStrip()
    }

    private struct ScreenshotFixture: Sendable {
        let title: String
        let urlString: String

        var url: URL? {
            URL(string: urlString)
        }
    }

    /// Fail-closed caps keep screenshots bounded even if fixtures grow.
    private nonisolated static var maxSeededTabs: Int {
        2
    }

    private nonisolated static var maxSeedTitleLength: Int {
        64
    }

    private static var screenshotFixtureTitle: String {
        String("OuterView Fixture".prefix(maxSeedTitleLength))
    }

    private static var screenshotFixtureHTML: String {
        """
        <!DOCTYPE html><html><head><meta name="viewport" \
        content="width=device-width,initial-scale=1">\
        <title>OuterView Fixture</title></head>\
        <body><h1>OuterView Fixture</h1>\
        <p>Deterministic fixture content for screenshots.</p></body></html>
        """
    }

    private static var screenshotFavorites: [ScreenshotFixture] {
        [
            ScreenshotFixture(title: clampedTitle("Apple"), urlString: "https://www.apple.com"),
            ScreenshotFixture(title: clampedTitle("GitHub"), urlString: "https://github.com"),
            ScreenshotFixture(title: clampedTitle("Wikipedia"), urlString: "https://www.wikipedia.org")
        ].prefix(3).map(\.self)
    }

    private static var screenshotBookmarks: [ScreenshotFixture] {
        [
            ScreenshotFixture(title: clampedTitle("Swift Forums"), urlString: "https://forums.swift.org"),
            ScreenshotFixture(title: clampedTitle("OuterView Docs"), urlString: "https://example.com/docs")
        ].prefix(2).map(\.self)
    }

    private static var screenshotReadingList: [ScreenshotFixture] {
        [
            ScreenshotFixture(
                title: clampedTitle("OuterView Fixture"),
                urlString: "https://example.com/fixture"
            )
        ].prefix(1).map(\.self)
    }

    private nonisolated static func clampedTitle(_ title: String) -> String {
        String(title.prefix(maxSeedTitleLength))
    }
}
