//
//  BookmarkImporter.swift
//  OuterView
//

import Foundation

struct ImportSummary: Equatable, Sendable {
    let added: Int
    let skippedDuplicates: Int
    let skippedInvalid: Int
    let truncated: Int
}

/// Imports a Netscape bookmarks export into the bookmark store, deduplicating
/// against bookmarks already present by exact URL equality.
@MainActor
struct BookmarkImporter {
    func importFromData(_ data: Data, bookmarkStore: BookmarkStore) async -> ImportSummary {
        let parseResult: BookmarkParseResult
        do {
            // Parse detached so a large export never blocks the main thread;
            // store writes below stay on the main actor.
            parseResult = try await Task.detached(priority: .userInitiated) {
                try BookmarkHTMLParser.parse(data)
            }.value
        } catch {
            // Malformed or oversize input imports nothing instead of crashing.
            return ImportSummary(added: 0, skippedDuplicates: 0, skippedInvalid: 0, truncated: 0)
        }

        var seen = Set<URL>(bookmarkStore.fetchAll().map(\.url))
        var added = 0
        var skippedDuplicates = 0
        var skippedInvalid = parseResult.skippedInvalid

        for bookmark in parseResult.bookmarks {
            guard !seen.contains(bookmark.url) else {
                skippedDuplicates += 1
                continue
            }
            do {
                try bookmarkStore.add(
                    title: bookmark.title,
                    url: bookmark.url,
                    isFavorite: Self.isFavorite(folderPath: bookmark.folderPath),
                    addedDate: bookmark.addedDate
                )
            } catch {
                skippedInvalid += 1
                continue
            }
            seen.insert(bookmark.url)
            added += 1
        }

        return ImportSummary(
            added: added,
            skippedDuplicates: skippedDuplicates,
            skippedInvalid: skippedInvalid,
            truncated: parseResult.truncated
        )
    }

    /// A bar/toolbar/favorites folder name marks its entries for the favorites
    /// grid. Matches whole folder names and whole words so "Sidebar" or
    /// "Barbecue" never match; the spaceless "BookmarksBar" needs its own
    /// entry since it contains no word boundary.
    private static let favoriteFolderNames: Set<String> = [
        "bar", "bookmarks bar", "bookmarksbar", "toolbar", "favorites", "favourites"
    ]
    private static let favoriteWords: Set<String> = ["bar", "toolbar", "favorites", "favourites"]

    static func isFavorite(folderPath: [String]) -> Bool {
        folderPath.contains { folder in
            let lowered = folder.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if favoriteFolderNames.contains(lowered) {
                return true
            }
            let words = lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            return words.contains { favoriteWords.contains(String($0)) }
        }
    }
}
