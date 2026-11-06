// Import — Folder routing plus dedupe for Safari imports.

import Foundation
import os

struct ImportSummary: Equatable, Sendable {
    let added: Int
    let skippedDuplicates: Int
    let skippedInvalid: Int
    let truncated: Int
}

/// Dedicated background worker actor for HTML parsing and file reading.
actor BookmarkImportWorker {
    static let shared = BookmarkImportWorker()

    func parse(_ data: Data) throws -> BookmarkParseResult {
        try BookmarkHTMLParser.parse(data)
    }

    func readFile(at url: URL) -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Settings")
                .error("bookmarks file read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// Imports a Netscape bookmarks export into the bookmark store, deduplicating
/// against bookmarks already present by exact URL equality.
@MainActor
struct BookmarkImporter {
    func importFromData(_ data: Data, bookmarkStore: BookmarkStore) async -> ImportSummary {
        let parseResult: BookmarkParseResult
        do {
            parseResult = try await BookmarkImportWorker.shared.parse(data)
        } catch {
            // Malformed or oversize input imports nothing instead of crashing.
            return ImportSummary(added: 0, skippedDuplicates: 0, skippedInvalid: 0, truncated: 0)
        }

        var folderMap: [[String]: UUID] = [:]
        var existingFolders = bookmarkStore.fetchAllFolders()

        func resolveOrCreateFolder(path: [String]) throws -> UUID? {
            guard !path.isEmpty else { return nil }
            // Trim once so spaced H3 text hits the same cache and stored rows.
            let normalizedPath = path.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let folderTitle = normalizedPath.last, !folderTitle.isEmpty else {
                throw BookmarkStoreError.invalidTitle
            }
            if normalizedPath.count == 1, let first = normalizedPath.first, Self.isTopLevelFavoriteContainer(parentPath: [], title: first) {
                return nil
            }
            if let cached = folderMap[normalizedPath] {
                return cached
            }

            let parentPath = Array(normalizedPath.dropLast())
            let parentId = try resolveOrCreateFolder(path: parentPath)
            let isFav = Self.isFavorite(folderPath: normalizedPath)

            let existing = existingFolders.first {
                $0.title == folderTitle &&
                    $0.parentId == parentId &&
                    (parentId != nil || $0.isFavorite == isFav)
            }
            if let existing {
                folderMap[normalizedPath] = existing.id
                return existing.id
            }

            let created = try bookmarkStore.createFolder(
                title: folderTitle,
                parentId: parentId,
                isFavorite: isFav
            )
            existingFolders.append(created)
            folderMap[normalizedPath] = created.id
            return created.id
        }

        // Create folders first (including empty folders)
        for folder in parseResult.folders {
            // Empty titles never persist as untitled folders.
            guard !folder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            do {
                _ = try resolveOrCreateFolder(path: folder.parentPath + [folder.title])
            } catch {
                // Unresolvable branches stay absent; bookmarks beneath skip as invalid below.
                continue
            }
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
            let folderId: UUID?
            do {
                folderId = try resolveOrCreateFolder(path: bookmark.folderPath)
            } catch {
                // Storage failure never falls back to root; the row skips as invalid.
                skippedInvalid += 1
                continue
            }
            // Store owns flag truth; heuristic only covers root-level rows.
            let isFav = Self.isFavorite(folderPath: bookmark.folderPath)
            do {
                try bookmarkStore.add(
                    title: bookmark.title,
                    url: bookmark.url,
                    isFavorite: isFav,
                    addedDate: bookmark.addedDate,
                    folderId: folderId
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

    static func isTopLevelFavoriteContainer(parentPath: [String], title: String) -> Bool {
        parentPath.isEmpty && isFavorite(folderPath: [title])
    }

    /// Favorites-folder names route to the favorites grid. Whole-name plus
    /// whole-word match avoids "Sidebar"/"Barbecue" hits; "BookmarksBar"
    /// needs its own entry since it has no word boundary.
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
