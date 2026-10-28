//
//  BookmarkLocationTree.swift
//  OuterView
//

import Foundation

/// Item in the bookmark location tree picker.
struct BookmarkLocationOption: Identifiable, Equatable, Hashable {
    let id: String
    let location: BookmarkLocation
    let title: String
    let depth: Int
    let iconSystemName: String
}

enum BookmarkLocationTree {
    /// Builds the list of available location destinations for a bookmark.
    /// Favorites is first, followed by root Bookmarks, followed by nested folders.
    static func optionsForBookmark(folders: [BookmarkFolder]) -> [BookmarkLocationOption] {
        var options: [BookmarkLocationOption] = []
        options.append(
            BookmarkLocationOption(
                id: "favorites",
                location: .favorites,
                title: "Favorites",
                depth: 0,
                iconSystemName: "star"
            )
        )
        options.append(
            BookmarkLocationOption(
                id: "root",
                location: .root,
                title: "Bookmarks",
                depth: 0,
                iconSystemName: "book"
            )
        )

        appendFolders(folders: folders, parentId: nil, depth: 1, excluding: [], into: &options)
        return options
    }

    /// Builds the list of available parent destinations when editing a folder.
    /// Favorites is omitted (folders cannot live inside Favorites).
    /// The folder itself and all its descendants are excluded to avoid cycles.
    static func optionsForFolder(
        folderId: UUID?,
        folders: [BookmarkFolder]
    ) -> [BookmarkLocationOption] {
        var options: [BookmarkLocationOption] = []
        options.append(
            BookmarkLocationOption(
                id: "root",
                location: .root,
                title: "Bookmarks",
                depth: 0,
                iconSystemName: "book"
            )
        )

        var excludedIds = Set<UUID>()
        if let folderId {
            excludedIds.insert(folderId)
            excludedIds.formUnion(descendantIds(of: folderId, in: folders))
        }

        appendFolders(folders: folders, parentId: nil, depth: 1, excluding: excludedIds, into: &options)
        return options
    }

    private static func appendFolders(
        folders: [BookmarkFolder],
        parentId: UUID?,
        depth: Int,
        excluding: Set<UUID>,
        into options: inout [BookmarkLocationOption]
    ) {
        let children = folders
            .filter { $0.parentId == parentId && !excluding.contains($0.id) }
            .sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) }

        for child in children {
            options.append(
                BookmarkLocationOption(
                    id: child.id.uuidString,
                    location: .folder(child.id),
                    title: child.title,
                    depth: depth,
                    iconSystemName: "folder"
                )
            )
            appendFolders(
                folders: folders,
                parentId: child.id,
                depth: depth + 1,
                excluding: excluding,
                into: &options
            )
        }
    }

    private static func descendantIds(of rootId: UUID, in folders: [BookmarkFolder]) -> Set<UUID> {
        var descendants = Set<UUID>()
        var queue = [rootId]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            let children = folders.filter { $0.parentId == current }.map(\.id)
            for child in children where !descendants.contains(child) {
                descendants.insert(child)
                queue.append(child)
            }
        }
        return descendants
    }
}
