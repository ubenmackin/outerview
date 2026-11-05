//
//  SuggestionEngine.swift
//  OuterView
//

import Foundation

enum SuggestionKind: Hashable, Sendable {
    case site(title: String, url: URL, isFavorite: Bool)
    case openTab(title: String, url: URL, tabID: UUID)
    case googleSuggest(query: String)
    case search(query: String)
    case onPageFind(term: String)
}

/// A ranked address-bar row. Identity is derived from the row content so two
/// equal rows compare equal and diff cleanly.
struct Suggestion: Identifiable, Hashable, Sendable {
    let kind: SuggestionKind

    var id: String {
        switch kind {
        case let .site(title, url, isFavorite):
            "site|\(url.absoluteString)|\(title)|\(isFavorite)"
        case let .openTab(title, url, tabID):
            "tab|\(tabID.uuidString)|\(url.absoluteString)|\(title)"
        case let .googleSuggest(query):
            "google|\(query)"
        case let .search(query):
            "search|\(query)"
        case let .onPageFind(term):
            "find|\(term)"
        }
    }

    var isSearchSuggestion: Bool {
        switch kind {
        case .googleSuggest, .search, .onPageFind:
            true
        case .openTab, .site:
            false
        }
    }
}

/// Value-type snapshot of a bookmark so ranking can run off the main actor.
struct SuggestionBookmark: Hashable, Sendable {
    let title: String
    let url: URL
    let isFavorite: Bool
}

/// Value-type snapshot of an open tab so ranking can run off the main actor.
struct SuggestionTab: Hashable, Sendable {
    let id: UUID
    let title: String
    let url: URL
}

/// Value-type snapshot of a history row so ranking can run off the main actor.
struct SuggestionHistoryItem: Hashable, Sendable {
    let title: String
    let url: URL
    let visitedAt: Date
}

/// Synchronous pure ranker for the address bar's suggestion list; callers own
/// any debounce timing. Stage order: open tab matches, exact/prefix bookmark rows,
/// Google suggestions, title/host contains bookmarks (≤ 4), history contains rows (≤ 4, newest first),
/// then the always-present search row and, when a page is open, the page-find row,
/// all capped at 12 rows total.
enum SuggestionEngine: Sendable {
    private enum Limits {
        static let maxRows = 12
        static let maxGoogleSuggest = 3
        static let maxBookmarkContains = 4
        static let maxHistory = 4
    }

    static func suggestions(
        for query: String,
        currentURL: URL?,
        googleSuggestions: [String] = [],
        tabs: [SuggestionTab] = [],
        bookmarks: [SuggestionBookmark] = [],
        recents: [SuggestionHistoryItem] = [],
        recentSearches: [String] = []
    ) -> [Suggestion] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = text.lowercased()

        var trailing: [SuggestionKind] = [.search(query: text)]
        if currentURL != nil {
            trailing.append(.onPageFind(term: text))
        }

        // An empty needle contains-matches everything, so empty input
        // surfaces recent searches alongside the trailing rows.
        guard !needle.isEmpty else {
            let cleaned = dedupedRecentSearches(recentSearches)
            guard !cleaned.isEmpty else {
                return trailing.map { Suggestion(kind: $0) }
            }
            // Reserve room so the trailing rows always survive the cap.
            let budget = max(0, Limits.maxRows - trailing.count)
            let capped = Array(cleaned.prefix(budget))
            return capped.map { Suggestion(kind: .search(query: $0)) } + trailing.map { Suggestion(kind: $0) }
        }

        // Reserve room for the trailing rows so they always survive the cap.
        let budget = max(0, Limits.maxRows - trailing.count)

        var kinds: [SuggestionKind] = []
        var surfacedBookmarks = Set<Int>()
        appendOpenTabMatches(tabs: tabs, needle: needle, budget: budget, kinds: &kinds)
        appendExactOrPrefixMatches(
            bookmarks: bookmarks,
            needle: needle,
            budget: budget,
            kinds: &kinds,
            surfaced: &surfacedBookmarks
        )
        appendGoogleMatches(suggestions: googleSuggestions, needle: needle, budget: budget, kinds: &kinds)
        appendContainsMatches(
            bookmarks: bookmarks,
            needle: needle,
            budget: budget,
            kinds: &kinds,
            surfaced: &surfacedBookmarks
        )
        appendHistoryMatches(recents: recents, needle: needle, budget: budget, kinds: &kinds)

        return (kinds + trailing).map { Suggestion(kind: $0) }
    }

    private static func appendOpenTabMatches(
        tabs: [SuggestionTab],
        needle: String,
        budget: Int,
        kinds: inout [SuggestionKind]
    ) {
        // Open tabs matching query (Switch to Tab)
        for tab in tabs {
            guard kinds.count < budget else { break }
            if isContainsMatch(title: tab.title, url: tab.url, needle: needle) {
                kinds.append(.openTab(title: tab.title, url: tab.url, tabID: tab.id))
            }
        }
    }

    private static func appendExactOrPrefixMatches(
        bookmarks: [SuggestionBookmark],
        needle: String,
        budget: Int,
        kinds: inout [SuggestionKind],
        surfaced: inout Set<Int>
    ) {
        // Exact or prefix matches on host or URL, in store order.
        for (index, bookmark) in bookmarks.enumerated() {
            guard kinds.count < budget else { break }
            if isExactOrPrefixMatch(bookmark, needle: needle) {
                surfaced.insert(index)
                kinds.append(siteKind(for: bookmark))
            }
        }
    }

    private static func appendGoogleMatches(
        suggestions: [String],
        needle: String,
        budget: Int,
        kinds: inout [SuggestionKind]
    ) {
        // Google live suggestions (queries distinct from exact needle)
        for suggestion in suggestions.prefix(Limits.maxGoogleSuggest) {
            guard kinds.count < budget else { break }
            let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.lowercased() != needle {
                kinds.append(.googleSuggest(query: trimmed))
            }
        }
    }

    private static func appendContainsMatches(
        bookmarks: [SuggestionBookmark],
        needle: String,
        budget: Int,
        kinds: inout [SuggestionKind],
        surfaced: inout Set<Int>
    ) {
        // Title/host contains matches, excluding rows already surfaced.
        var containsMatches = 0
        for (index, bookmark) in bookmarks.enumerated() {
            guard kinds.count < budget, containsMatches < Limits.maxBookmarkContains else { break }
            guard !surfaced.contains(index) else { continue }
            if isContainsMatch(title: bookmark.title, url: bookmark.url, needle: needle) {
                surfaced.insert(index)
                kinds.append(siteKind(for: bookmark))
                containsMatches += 1
            }
        }
    }

    private static func appendHistoryMatches(
        recents: [SuggestionHistoryItem],
        needle: String,
        budget: Int,
        kinds: inout [SuggestionKind]
    ) {
        // History contains matches, newest first.
        guard kinds.count < budget else { return }
        for entry in historyMatches(recents: recents, needle: needle).prefix(Limits.maxHistory) {
            guard kinds.count < budget else { break }
            kinds.append(.site(title: entry.title, url: entry.url, isFavorite: false))
        }
    }

    private static func historyMatches(
        recents: [SuggestionHistoryItem],
        needle: String
    ) -> [SuggestionHistoryItem] {
        recents.enumerated()
            .filter { isContainsMatch(title: $0.element.title, url: $0.element.url, needle: needle) }
            .sorted {
                $0.element.visitedAt != $1.element.visitedAt
                    ? $0.element.visitedAt > $1.element.visitedAt
                    : $0.offset < $1.offset
            }
            .map(\.element)
    }

    private static func dedupedRecentSearches(_ queries: [String]) -> [String] {
        var seen = Set<String>()
        var cleaned: [String] = []
        for query in queries {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            cleaned.append(trimmed)
            if cleaned.count >= Limits.maxRows {
                break
            }
        }
        return cleaned
    }

    // MARK: - Matching

    private static func siteKind(for bookmark: SuggestionBookmark) -> SuggestionKind {
        .site(title: bookmark.title, url: bookmark.url, isFavorite: bookmark.isFavorite)
    }

    /// Exact or prefix match on host, full URL, or the scheme-less display
    /// form — scheme-less input is a first-class URL form for this app.
    private static func isExactOrPrefixMatch(_ bookmark: SuggestionBookmark, needle: String) -> Bool {
        let forms = [
            HostFormatter.host(of: bookmark.url).lowercased(),
            bookmark.url.absoluteString.lowercased(),
            schemelessString(of: bookmark.url).lowercased()
        ]
        return forms.contains { $0 == needle || $0.hasPrefix(needle) }
    }

    private static func isContainsMatch(title: String, url: URL, needle: String) -> Bool {
        title.lowercased().contains(needle) || HostFormatter.host(of: url).lowercased().contains(needle)
    }

    private static func schemelessString(of url: URL) -> String {
        let absolute = url.absoluteString
        guard let scheme = url.scheme else { return absolute }
        let separator = absolute.hasPrefix(scheme + "://") ? "://" : ":"
        return String(absolute.dropFirst(scheme.count + separator.count))
    }
}
