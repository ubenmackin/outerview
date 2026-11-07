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

private struct BookmarkLocationKey: Hashable {
    let folderId: UUID?
    let isFavorite: Bool
    let url: URL
}

private struct ContainerKey: Hashable {
    let parentId: UUID?
    let isFavorite: Bool
}

/// Imports a Netscape bookmarks export into the bookmark store, deduplicating
/// against bookmarks already present in the same container by exact URL equality.
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
        var containerOrder: [ContainerKey: Int] = [:]

        func nextOrder(for key: ContainerKey) -> Int {
            if let current = containerOrder[key] {
                containerOrder[key] = current + 1
                return current
            }
            let maxOrder: Int
            if key.parentId == nil, key.isFavorite {
                let bmMax = bookmarkStore.fetchFavorites(rootOnly: true).map(\.sortOrder).max() ?? -1
                let fMax = existingFolders.filter { $0.parentId == nil && $0.isFavorite }.map(\.sortOrder).max() ?? -1
                maxOrder = max(bmMax, fMax)
            } else if key.parentId == nil, !key.isFavorite {
                let bmMax = bookmarkStore.fetchBookmarks(folderId: nil).map(\.sortOrder).max() ?? -1
                let fMax = existingFolders.filter { $0.parentId == nil && !$0.isFavorite }.map(\.sortOrder).max() ?? -1
                maxOrder = max(bmMax, fMax)
            } else {
                let bmMax = bookmarkStore.fetchBookmarks(folderId: key.parentId).map(\.sortOrder).max() ?? -1
                let fMax = existingFolders.filter { $0.parentId == key.parentId }.map(\.sortOrder).max() ?? -1
                maxOrder = max(bmMax, fMax)
            }
            let start = maxOrder + 1
            containerOrder[key] = start + 1
            return start
        }

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

            let order = nextOrder(for: ContainerKey(parentId: parentId, isFavorite: isFav))
            let created = try bookmarkStore.createFolder(
                title: folderTitle,
                parentId: parentId,
                isFavorite: isFav,
                sortOrder: order
            )
            existingFolders.append(created)
            folderMap[normalizedPath] = created.id
            return created.id
        }

        var seen = Set<BookmarkLocationKey>(bookmarkStore.fetchAll().map {
            BookmarkLocationKey(folderId: $0.folderId, isFavorite: $0.isFavorite, url: $0.url)
        })
        var added = 0
        var skippedDuplicates = 0
        var skippedInvalid = parseResult.skippedInvalid

        for item in parseResult.items {
            switch item {
            case let .folder(folder):
                guard !folder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                do {
                    _ = try resolveOrCreateFolder(path: folder.parentPath + [folder.title])
                } catch {
                    continue
                }

            case let .bookmark(bookmark):
                let folderId: UUID?
                do {
                    folderId = try resolveOrCreateFolder(path: bookmark.folderPath)
                } catch {
                    skippedInvalid += 1
                    continue
                }
                let isFav = Self.isFavorite(folderPath: bookmark.folderPath)
                let key = BookmarkLocationKey(folderId: folderId, isFavorite: isFav, url: bookmark.url)
                guard !seen.contains(key) else {
                    skippedDuplicates += 1
                    continue
                }
                let order = nextOrder(for: ContainerKey(parentId: folderId, isFavorite: isFav))
                do {
                    try bookmarkStore.add(
                        title: bookmark.title,
                        url: bookmark.url,
                        isFavorite: isFav,
                        addedDate: bookmark.addedDate,
                        folderId: folderId,
                        sortOrder: order
                    )
                } catch {
                    skippedInvalid += 1
                    continue
                }
                seen.insert(key)
                added += 1
            }
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
