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

    /// History plus recent searches reset before populating deterministic items.
    private func clearScreenshotEphemera() throws {
        guard historyStore != nil, recentSearchStore != nil else {
            preconditionFailure("Screenshot seed requires history and search stores")
        }
        try historyStore?.clear()
        try recentSearchStore?.clear()
    }

    private struct ScreenshotBookmarkSeed {
        let title: String
        let urlString: String
    }

    private struct ScreenshotRecentVisitSeed {
        let title: String
        let urlString: String
        let hoursAgo: Double
    }

    private func seedFoldersAndCategorizedBookmarks(into bookmarkStore: BookmarkStore) throws {
        let devFolder = try bookmarkStore.createFolder(title: "Developer")
        let newsFolder = try bookmarkStore.createFolder(title: "Tech & News")
        let refFolder = try bookmarkStore.createFolder(title: "Reference")

        let devBookmarks = [
            ScreenshotBookmarkSeed(title: "Swift.org", urlString: "https://www.swift.org"),
            ScreenshotBookmarkSeed(title: "GitHub", urlString: "https://github.com"),
            ScreenshotBookmarkSeed(title: "Apple Developer", urlString: "https://developer.apple.com"),
            ScreenshotBookmarkSeed(title: "MDN Web Docs", urlString: "https://developer.mozilla.org")
        ]
        for (index, bookmark) in devBookmarks.enumerated() {
            guard let url = URL(string: bookmark.urlString) else { continue }
            try bookmarkStore.add(title: bookmark.title, url: url, isFavorite: false, folderId: devFolder.id, sortOrder: index)
        }

        let newsBookmarks = [
            ScreenshotBookmarkSeed(title: "Hacker News", urlString: "https://news.ycombinator.com"),
            ScreenshotBookmarkSeed(title: "Ars Technica", urlString: "https://arstechnica.com"),
            ScreenshotBookmarkSeed(title: "The Verge", urlString: "https://www.theverge.com")
        ]
        for (index, bookmark) in newsBookmarks.enumerated() {
            guard let url = URL(string: bookmark.urlString) else { continue }
            try bookmarkStore.add(title: bookmark.title, url: url, isFavorite: false, folderId: newsFolder.id, sortOrder: index)
        }

        let refBookmarks = [
            ScreenshotBookmarkSeed(title: "Wikipedia", urlString: "https://www.wikipedia.org"),
            ScreenshotBookmarkSeed(title: "W3C Standards", urlString: "https://www.w3.org")
        ]
        for (index, bookmark) in refBookmarks.enumerated() {
            guard let url = URL(string: bookmark.urlString) else { continue }
            try bookmarkStore.add(title: bookmark.title, url: url, isFavorite: false, folderId: refFolder.id, sortOrder: index)
        }
    }

    private func seedRecentVisits() throws {
        let recentVisits = [
            ScreenshotRecentVisitSeed(title: "Swift.org - A Swift Tour", urlString: "https://www.swift.org/tour/", hoursAgo: 1),
            ScreenshotRecentVisitSeed(title: "GitHub: Where the world builds software", urlString: "https://github.com", hoursAgo: 3),
            ScreenshotRecentVisitSeed(title: "WebKit Features & Standards", urlString: "https://webkit.org/status/", hoursAgo: 6),
            ScreenshotRecentVisitSeed(title: "Hacker News", urlString: "https://news.ycombinator.com", hoursAgo: 12),
            ScreenshotRecentVisitSeed(title: "Ars Technica", urlString: "https://arstechnica.com", hoursAgo: 24),
            ScreenshotRecentVisitSeed(title: "MDN Web Docs", urlString: "https://developer.mozilla.org", hoursAgo: 48)
        ]
        for item in recentVisits {
            guard let url = URL(string: item.urlString) else { continue }
            let visit = PageVisit(
                url: url,
                title: item.title,
                visitedAt: Date().addingTimeInterval(-item.hoursAgo * 3600)
            )
            try historyStore?.record(visit: visit)
        }
    }

    private func seedScreenshotStores() throws {
        guard let bookmarkStore, let readingListStore else {
            preconditionFailure("Screenshot seed requires bookmark and reading list stores")
        }
        let existing = bookmarkStore.fetchAll()
        if !existing.isEmpty {
            try bookmarkStore.delete(ids: Set(existing.map(\.id)))
        }
        for folder in bookmarkStore.fetchFolders(parentId: nil) {
            try bookmarkStore.deleteFolder(id: folder.id)
        }

        try seedFoldersAndCategorizedBookmarks(into: bookmarkStore)

        // Root bookmarks
        for (index, fixture) in Self.screenshotBookmarks.enumerated() {
            guard let url = fixture.url else { continue }
            _ = try bookmarkStore.add(
                title: fixture.title,
                url: url,
                isFavorite: false,
                sortOrder: index
            )
        }

        // Favorites
        for (index, fixture) in Self.screenshotFavorites.enumerated() {
            guard let url = fixture.url else { continue }
            _ = try bookmarkStore.add(
                title: fixture.title,
                url: url,
                isFavorite: true,
                sortOrder: index
            )
        }

        try readingListStore.clear()
        for fixture in Self.screenshotReadingList {
            guard let url = fixture.url else { continue }
            _ = try readingListStore.add(title: fixture.title, url: url)
        }

        try seedRecentVisits()
    }

    /// Rebuilds tabs for overview and browsing capture: Start Page selected plus
    /// realistic background tabs with high-fidelity preview snapshots.
    private func seedScreenshotTabs() throws {
        for id in tabs.map(\.id) {
            prunePerTabState(id: id)
            tabPool.delete(id: id)
        }
        tabs.removeAll()
        forcedStartPageTabs.removeAll()
        screenshotTabPreviews.removeAll()

        let first = TabRecord(url: nil, title: "New Tab", isPrivate: false)
        let second = TabRecord(
            url: Self.screenshotFixtureURL,
            title: Self.screenshotFixtureTitle,
            isPrivate: false
        )
        let third = TabRecord(
            url: URL(string: "https://www.apple.com"),
            title: "Apple",
            isPrivate: false
        )
        let fourth = TabRecord(
            url: URL(string: "https://github.com"),
            title: "GitHub: Let's build from here",
            isPrivate: false
        )
        let fifth = TabRecord(
            url: URL(string: "https://news.ycombinator.com"),
            title: "Hacker News",
            isPrivate: false
        )

        tabs = [first, second, third, fourth, fifth]
        for record in tabs {
            tabPool.create(record)
        }

        // Generate rich previews for each tab so TabOverview renders authentic website snapshots
        for record in tabs {
            screenshotTabPreviews[record.id] = Self.generateTabPreview(for: record.url, title: record.title)
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

        // Load the rich Wikipedia article into Tab 2's webView
        if tabs.count > 1, let fixtureID = tabs.dropFirst().first?.id,
           let fixtureURL = Self.screenshotFixtureURL
        {
            tabPool.pages.first(where: { $0.id == fixtureID })?.page?.load(fixtureURL)
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

    private nonisolated static var maxSeedTitleLength: Int {
        64
    }

    private static let screenshotFixtureURL = URL(string: "https://en.wikipedia.org/wiki/Swift_(programming_language)")

    private static var screenshotFixtureTitle: String {
        String("Swift (programming language)".prefix(maxSeedTitleLength))
    }

    static var screenshotFixtureHTML: String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
        <title>Swift (programming language)</title>
        <style>
          :root { color-scheme: light dark; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            margin: 0; padding: 20px 16px;
            background-color: #ffffff; color: #202122;
            line-height: 1.6; font-size: 16px;
          }
          @media (prefers-color-scheme: dark) {
            body { background-color: #1a1a1a; color: #eaecf0; }
            .infobox { background-color: #242424 !important; border-color: #3c4043 !important; }
            .wiki-header { border-bottom-color: #3c4043 !important; }
            .code-box { background-color: #242424 !important; border-color: #3c4043 !important; color: #eaecf0 !important; }
          }
          .wiki-header {
            display: flex; align-items: center; justify-content: space-between;
            padding-bottom: 12px; margin-bottom: 16px;
            border-bottom: 1px solid #eaecf0;
          }
          .wiki-logo { font-size: 20px; font-weight: 700; font-family: Georgia, serif; letter-spacing: 1px; }
          .wiki-actions { font-size: 14px; color: #3366cc; }
          h1 { font-family: Georgia, serif; font-size: 28px; margin: 0 0 4px 0; font-weight: 400; line-height: 1.25; }
          .tagline { font-size: 13px; color: #72777d; margin-bottom: 16px; }
          .infobox {
            background: #f8f9fa; border: 1px solid #c8ccd1; border-radius: 8px;
            padding: 14px; margin: 16px 0; font-size: 14px;
          }
          .infobox-title { font-weight: 700; font-size: 15px; margin-bottom: 8px; text-align: center; }
          .infobox-row { display: flex; justify-content: space-between; padding: 5px 0; border-bottom: 1px solid #eaecf0; }
          .infobox-label { color: #54595d; font-weight: 600; }
          .infobox-value { font-weight: 500; text-align: right; }
          p { margin: 0 0 16px 0; }
          a { color: #3366cc; text-decoration: none; }
          .code-box {
            background: #f8f9fa; border: 1px solid #eaecf0; border-radius: 6px;
            padding: 12px; font-family: ui-monospace, monospace; font-size: 13px; margin: 16px 0;
          }
        </style>
        </head>
        <body>
          <span style="opacity: 0.01; font-size: 1px; position: absolute;">OuterView Fixture</span>
          <div class="wiki-header">
            <span class="wiki-logo">WIKIPEDIA</span>
            <span class="wiki-actions">English &bull; Search</span>
          </div>
          <h1>Swift (programming language)</h1>
          <div class="tagline">From Wikipedia, the free encyclopedia</div>
          <p><b>Swift</b> is a high-level, general-purpose, multi-paradigm, compiled programming language developed by <a href="#">Apple Inc.</a> and the open-source community.</p>
          <div class="infobox">
            <div class="infobox-title">Swift Language</div>
            <div class="infobox-row"><span class="infobox-label">Designed by</span><span class="infobox-value">Apple Inc.</span></div>
            <div class="infobox-row"><span class="infobox-label">First appeared</span><span class="infobox-value">June 2, 2014</span></div>
            <div class="infobox-row"><span class="infobox-label">Type system</span><span class="infobox-value">Static, strong, inferred</span></div>
            <div class="infobox-row"><span class="infobox-label">Platform</span><span class="infobox-value">Apple OS, Linux, Windows</span></div>
            <div class="infobox-row"><span class="infobox-label">License</span><span class="infobox-value">Apache 2.0 with Exception</span></div>
          </div>
          <p>Swift was introduced at Apple's 2014 Worldwide Developers Conference (WWDC). It was designed to replace Apple's earlier Objective-C programming language.</p>
          <div class="code-box">
            <span style="color:#007aff">import</span> SwiftUI<br><br>
            <span style="color:#a53bba">struct</span> HelloWorld: <span style="color:#2a7578">View</span> {<br>
            &nbsp;&nbsp;<span style="color:#a53bba">var</span> body: <span style="color:#a53bba">some</span> <span style="color:#2a7578">View</span> {<br>
            &nbsp;&nbsp;&nbsp;&nbsp;<span style="color:#2a7578">Text</span>(<span style="color:#d12f1b">"Hello, World!"</span>)<br>
            &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;.padding()<br>
            &nbsp;&nbsp;}<br>
            }
          </div>
          <p>During its introduction, it was described simply as "Objective-C without the bag of C". It is built with the LLVM compiler framework.</p>
        </body>
        </html>
        """
    }

    private static var screenshotFavorites: [ScreenshotFixture] {
        [
            ScreenshotFixture(title: clampedTitle("Apple"), urlString: "https://www.apple.com"),
            ScreenshotFixture(title: clampedTitle("Wikipedia"), urlString: "https://www.wikipedia.org"),
            ScreenshotFixture(title: clampedTitle("GitHub"), urlString: "https://github.com"),
            ScreenshotFixture(title: clampedTitle("Swift"), urlString: "https://www.swift.org"),
            ScreenshotFixture(title: clampedTitle("DuckDuckGo"), urlString: "https://duckduckgo.com"),
            ScreenshotFixture(title: clampedTitle("MDN"), urlString: "https://developer.mozilla.org")
        ]
    }

    private static var screenshotBookmarks: [ScreenshotFixture] {
        [
            ScreenshotFixture(title: clampedTitle("Swift Documentation"), urlString: "https://docs.swift.org"),
            ScreenshotFixture(title: clampedTitle("Apple Developer"), urlString: "https://developer.apple.com"),
            ScreenshotFixture(title: clampedTitle("WebKit Open Source"), urlString: "https://webkit.org"),
            ScreenshotFixture(title: clampedTitle("Rust Programming"), urlString: "https://www.rust-lang.org"),
            ScreenshotFixture(title: clampedTitle("DuckDuckGo"), urlString: "https://duckduckgo.com")
        ]
    }

    private static var screenshotReadingList: [ScreenshotFixture] {
        [
            ScreenshotFixture(
                title: clampedTitle("Swift Language Tour"),
                urlString: "https://www.swift.org/tour/"
            )
        ]
    }

    private nonisolated static func clampedTitle(_ title: String) -> String {
        String(title.prefix(maxSeedTitleLength))
    }

    // MARK: - Tab Preview Snapshot Generator

    /// Generates high-fidelity preview snapshots for seeded tabs, avoiding white-on-white card previews.
    private static func generateTabPreview(for url: URL?, title _: String?) -> UIImage {
        let size = CGSize(width: 320, height: 440)
        let renderer = UIGraphicsImageRenderer(size: size)
        let host = url.flatMap { HostFormatter.host(of: $0) }?.lowercased() ?? ""

        return renderer.image { _ in
            if host.contains("wikipedia.org") {
                drawWikipediaPreview(size: size)
            } else if host.contains("apple.com") {
                drawApplePreview(size: size)
            } else if host.contains("github.com") {
                drawGitHubPreview(size: size)
            } else if host.contains("ycombinator.com") {
                drawHackerNewsPreview(size: size)
            } else {
                drawStartPagePreview(size: size)
            }
        }
    }

    private static func drawWikipediaPreview(size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        UIColor.white.setFill()
        UIRectFill(rect)

        let headerRect = CGRect(x: 0, y: 0, width: size.width, height: 36)
        UIColor(white: 0.96, alpha: 1.0).setFill()
        UIRectFill(headerRect)

        let logoFont = UIFont(name: "Georgia-Bold", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .bold)
        let logoAttr: [NSAttributedString.Key: Any] = [.font: logoFont, .foregroundColor: UIColor(white: 0.2, alpha: 1.0)]
        "WIKIPEDIA".draw(at: CGPoint(x: 16, y: 10), withAttributes: logoAttr)

        let titleFont = UIFont(name: "Georgia-Bold", size: 18) ?? UIFont.systemFont(ofSize: 18, weight: .bold)
        let titleAttr: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor(white: 0.1, alpha: 1.0)]
        "Swift".draw(at: CGPoint(x: 16, y: 50), withAttributes: titleAttr)
        let subTitleFont = UIFont(name: "Georgia", size: 13) ?? UIFont.systemFont(ofSize: 13)
        "(programming language)".draw(at: CGPoint(x: 16, y: 74), withAttributes: [.font: subTitleFont, .foregroundColor: UIColor(white: 0.25, alpha: 1.0)])

        let subAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor(white: 0.5, alpha: 1.0)]
        "From Wikipedia, the free encyclopedia".draw(at: CGPoint(x: 16, y: 96), withAttributes: subAttr)

        let infoRect = CGRect(x: 16, y: 114, width: size.width - 32, height: 110)
        let infoPath = UIBezierPath(roundedRect: infoRect, cornerRadius: 6)
        UIColor(white: 0.96, alpha: 1.0).setFill()
        infoPath.fill()
        UIColor(white: 0.85, alpha: 1.0).setStroke()
        infoPath.lineWidth = 0.5
        infoPath.stroke()

        let boxHeaderAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: UIColor(white: 0.15, alpha: 1.0)]
        "Swift Specifications".draw(at: CGPoint(x: 26, y: 122), withAttributes: boxHeaderAttr)

        let labelAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: UIColor(white: 0.45, alpha: 1.0)]
        let valAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor(white: 0.15, alpha: 1.0)]

        "Designed by:".draw(at: CGPoint(x: 26, y: 144), withAttributes: labelAttr)
        "Apple Inc.".draw(at: CGPoint(x: 110, y: 144), withAttributes: valAttr)

        "First appeared:".draw(at: CGPoint(x: 26, y: 164), withAttributes: labelAttr)
        "2014; 12 years ago".draw(at: CGPoint(x: 110, y: 164), withAttributes: valAttr)

        "Type system:".draw(at: CGPoint(x: 26, y: 184), withAttributes: labelAttr)
        "Inferred, static, strong".draw(at: CGPoint(x: 110, y: 184), withAttributes: valAttr)

        "Platform:".draw(at: CGPoint(x: 26, y: 204), withAttributes: labelAttr)
        "Apple platforms, Linux".draw(at: CGPoint(x: 110, y: 204), withAttributes: valAttr)

        UIColor(white: 0.88, alpha: 1.0).setFill()
        let lineYPositions: [CGFloat] = [238, 252, 266, 280, 300, 314, 328, 342, 356, 376, 390, 404]
        for yOffset in lineYPositions {
            let lineWidth = (yOffset == 280 || yOffset == 356 || yOffset == 404) ? (size.width - 120) : (size.width - 32)
            UIRectFill(CGRect(x: 16, y: yOffset, width: lineWidth, height: 6))
        }
    }

    private static func drawApplePreview(size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0).setFill()
        UIRectFill(rect)

        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let apple = UIImage(systemName: "apple.logo", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            apple.draw(at: CGPoint(x: (size.width - apple.size.width) / 2, y: 16))
        }

        let headFont = UIFont.systemFont(ofSize: 22, weight: .bold)
        let headAttr: [NSAttributedString.Key: Any] = [.font: headFont, .foregroundColor: UIColor.white]
        let headStr = "iPhone 17 Pro" as NSString
        let headSize = headStr.size(withAttributes: headAttr)
        headStr.draw(at: CGPoint(x: (size.width - headSize.width) / 2, y: 56), withAttributes: headAttr)

        let subFont = UIFont.systemFont(ofSize: 13, weight: .medium)
        let subAttr: [NSAttributedString.Key: Any] = [.font: subFont, .foregroundColor: UIColor(white: 0.75, alpha: 1.0)]
        let subStr = "All in. All Pro." as NSString
        let subSize = subStr.size(withAttributes: subAttr)
        subStr.draw(at: CGPoint(x: (size.width - subSize.width) / 2, y: 84), withAttributes: subAttr)

        let phoneRect = CGRect(x: 60, y: 120, width: size.width - 120, height: 240)
        let phonePath = UIBezierPath(roundedRect: phoneRect, cornerRadius: 28)
        UIColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1.0).setFill()
        phonePath.fill()
        UIColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1.0).setStroke()
        phonePath.lineWidth = 1.5
        phonePath.stroke()

        let screenRect = phoneRect.insetBy(dx: 6, dy: 6)
        let screenPath = UIBezierPath(roundedRect: screenRect, cornerRadius: 22)
        UIColor(red: 0.02, green: 0.06, blue: 0.14, alpha: 1.0).setFill()
        screenPath.fill()

        let glowRect = CGRect(x: screenRect.midX - 35, y: screenRect.midY - 35, width: 70, height: 70)
        let glowPath = UIBezierPath(ovalIn: glowRect)
        UIColor(red: 0.2, green: 0.5, blue: 0.95, alpha: 0.6).setFill()
        glowPath.fill()

        let btnRect = CGRect(x: (size.width - 100) / 2, y: 380, width: 100, height: 28)
        let btnPath = UIBezierPath(roundedRect: btnRect, cornerRadius: 14)
        UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0).setFill()
        btnPath.fill()
        let btnAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: UIColor.white]
        let btnStr = "Learn more" as NSString
        let btnSize = btnStr.size(withAttributes: btnAttr)
        btnStr.draw(at: CGPoint(x: (size.width - btnSize.width) / 2, y: 386), withAttributes: btnAttr)
    }

    private static func drawGitHubPreview(size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0).setFill()
        UIRectFill(rect)

        let topBar = CGRect(x: 0, y: 0, width: size.width, height: 40)
        UIColor(red: 0.09, green: 0.11, blue: 0.14, alpha: 1.0).setFill()
        UIRectFill(topBar)

        let ghAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .heavy), .foregroundColor: UIColor.white]
        "GH".draw(at: CGPoint(x: 16, y: 12), withAttributes: ghAttr)

        let searchRect = CGRect(x: 50, y: 8, width: size.width - 66, height: 24)
        let searchPath = UIBezierPath(roundedRect: searchRect, cornerRadius: 6)
        UIColor(red: 0.13, green: 0.15, blue: 0.18, alpha: 1.0).setFill()
        searchPath.fill()

        let repoFont = UIFont.systemFont(ofSize: 15, weight: .bold)
        let repoAttr: [NSAttributedString.Key: Any] = [.font: repoFont, .foregroundColor: UIColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1.0)]
        "apple / swift".draw(at: CGPoint(x: 16, y: 54), withAttributes: repoAttr)

        let pubRect = CGRect(x: 16, y: 76, width: 48, height: 18)
        let pubPath = UIBezierPath(roundedRect: pubRect, cornerRadius: 9)
        UIColor(red: 0.13, green: 0.15, blue: 0.18, alpha: 1.0).setFill()
        pubPath.fill()
        let pubAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: UIColor(white: 0.7, alpha: 1.0)]
        "Public".draw(at: CGPoint(x: 24, y: 79), withAttributes: pubAttr)

        let fileBox = CGRect(x: 16, y: 104, width: size.width - 32, height: 160)
        let filePath = UIBezierPath(roundedRect: fileBox, cornerRadius: 6)
        UIColor(red: 0.09, green: 0.11, blue: 0.14, alpha: 1.0).setFill()
        filePath.fill()
        UIColor(red: 0.2, green: 0.22, blue: 0.26, alpha: 1.0).setStroke()
        filePath.lineWidth = 0.5
        filePath.stroke()

        let fileRows = ["📁 Sources", "📁 Tests", "📁 docs", "📄 Package.swift", "📄 README.md"]
        let fileFont = UIFont.systemFont(ofSize: 11, weight: .regular)
        let fileAttr: [NSAttributedString.Key: Any] = [.font: fileFont, .foregroundColor: UIColor(white: 0.85, alpha: 1.0)]
        for (rowIndex, rowText) in fileRows.enumerated() {
            let rowYOffset = 114 + CGFloat(rowIndex * 28)
            rowText.draw(at: CGPoint(x: 28, y: rowYOffset), withAttributes: fileAttr)
            if rowIndex < fileRows.count - 1 {
                UIColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1.0).setFill()
                UIRectFill(CGRect(x: 16, y: rowYOffset + 22, width: size.width - 32, height: 0.5))
            }
        }

        let readmeRect = CGRect(x: 16, y: 276, width: size.width - 32, height: 140)
        let readmePath = UIBezierPath(roundedRect: readmeRect, cornerRadius: 6)
        UIColor(red: 0.09, green: 0.11, blue: 0.14, alpha: 1.0).setFill()
        readmePath.fill()
        UIColor(red: 0.2, green: 0.22, blue: 0.26, alpha: 1.0).setStroke()
        readmePath.lineWidth = 0.5
        readmePath.stroke()

        let rmHeaderAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: UIColor.white]
        "The Swift Programming Language".draw(at: CGPoint(x: 26, y: 288), withAttributes: rmHeaderAttr)
        UIColor(red: 0.2, green: 0.22, blue: 0.26, alpha: 1.0).setFill()
        UIRectFill(CGRect(x: 26, y: 316, width: size.width - 52, height: 6))
        UIRectFill(CGRect(x: 26, y: 330, width: size.width - 72, height: 6))
        UIRectFill(CGRect(x: 26, y: 344, width: size.width - 52, height: 6))
    }

    private static func drawHackerNewsPreview(size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        UIColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1.0).setFill()
        UIRectFill(rect)

        let barRect = CGRect(x: 0, y: 0, width: size.width, height: 32)
        UIColor(red: 1.0, green: 0.40, blue: 0.0, alpha: 1.0).setFill()
        UIRectFill(barRect)

        let hnLogoAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13, weight: .black), .foregroundColor: UIColor.white]
        "Y".draw(at: CGPoint(x: 12, y: 7), withAttributes: hnLogoAttr)

        let hnTitleAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: UIColor.black]
        "Hacker News".draw(at: CGPoint(x: 30, y: 8), withAttributes: hnTitleAttr)

        let hnLinksAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.black]
        "new | past | comments | ask".draw(at: CGPoint(x: 120, y: 9), withAttributes: hnLinksAttr)

        let items = [
            ("1. ▲ Swift 6.2 Released (swift.org)", "184 points by ben 3h ago | 94 comments"),
            ("2. ▲ Show HN: OuterView – Dual screen browser", "312 points by alex 5h ago | 142 comments"),
            ("3. ▲ WebKit standardizes CSS subgrid", "89 points by webkit 6h ago | 23 comments"),
            ("4. ▲ The Evolution of Modern Compilers", "240 points by larry 8h ago | 115 comments"),
            ("5. ▲ Ask HN: What are your favorite tools?", "156 points by dev 10h ago | 280 comments"),
            ("6. ▲ High Performance Graphics on Apple Silicon", "420 points by metal 12h ago | 176 comments")
        ]

        let itemTitleAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: UIColor.black]
        let itemSubAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor(white: 0.5, alpha: 1.0)]

        for (itemIndex, item) in items.enumerated() {
            let itemYOffset = 44 + CGFloat(itemIndex * 56)
            item.0.draw(at: CGPoint(x: 12, y: itemYOffset), withAttributes: itemTitleAttr)
            item.1.draw(at: CGPoint(x: 26, y: itemYOffset + 16), withAttributes: itemSubAttr)
        }
    }

    private static func drawStartPagePreview(size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0).setFill()
        UIRectFill(rect)

        let favHeaderAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 16, weight: .bold), .foregroundColor: UIColor.label]
        "Favorites".draw(at: CGPoint(x: 16, y: 24), withAttributes: favHeaderAttr)

        let colors: [UIColor] = [
            .black,
            UIColor(red: 0.96, green: 0.35, blue: 0.22, alpha: 1.0),
            UIColor(red: 0.14, green: 0.16, blue: 0.18, alpha: 1.0),
            UIColor(red: 0.88, green: 0.35, blue: 0.20, alpha: 1.0),
            UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0),
            UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        ]
        let initials = ["", "Swift", "GH", "DDG", "MDN", "W"]
        for tileIndex in 0 ..< 6 {
            let col = CGFloat(tileIndex % 3)
            let row = CGFloat(tileIndex / 3)
            let originX = 16 + col * 94
            let originY = 54 + row * 84
            let tileRect = CGRect(x: originX + 16, y: originY, width: 52, height: 52)
            let tilePath = UIBezierPath(roundedRect: tileRect, cornerRadius: 12)
            colors[tileIndex].setFill()
            tilePath.fill()

            let font = UIFont.systemFont(ofSize: 12, weight: .bold)
            let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let str = initials[tileIndex] as NSString
            let strSize = str.size(withAttributes: attr)
            str.draw(at: CGPoint(x: tileRect.midX - strSize.width / 2, y: tileRect.midY - strSize.height / 2), withAttributes: attr)
        }

        "Recently Visited".draw(at: CGPoint(x: 16, y: 240), withAttributes: favHeaderAttr)

        let recentTitles = ["Swift Tour", "GitHub", "WebKit Features", "Hacker News"]
        let recentAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: UIColor.label]
        for (recentIndex, recentTitle) in recentTitles.enumerated() {
            let recentYOffset = 274 + CGFloat(recentIndex * 36)
            let rowRect = CGRect(x: 16, y: recentYOffset, width: size.width - 32, height: 28)
            let rowPath = UIBezierPath(roundedRect: rowRect, cornerRadius: 6)
            UIColor.white.setFill()
            rowPath.fill()
            recentTitle.draw(at: CGPoint(x: 28, y: recentYOffset + 6), withAttributes: recentAttr)
        }
    }
}
