// Persistence — SwiftData models for bookmarks/folders/history/tabs.

import Foundation
import SwiftData

/// Persisted bookmark; URL-based dedupe keeps the earliest row.
@Model
final class Bookmark {
    var id: UUID = UUID()
    var title: String = ""
    var url: URL = URL(string: "about:blank") ?? URL(filePath: "/")
    var addedAt: Date = Date()
    var isFavorite: Bool = false
    var folderId: UUID?
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        addedAt: Date,
        isFavorite: Bool = false,
        folderId: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.addedAt = addedAt
        self.isFavorite = isFavorite
        self.folderId = folderId
        self.sortOrder = sortOrder
    }
}

/// Persisted folder for organizing bookmarks hierarchically.
@Model
final class BookmarkFolder {
    var id: UUID = UUID()
    var title: String = ""
    var parentId: UUID?
    var createdAt: Date = Date()
    var sortOrder: Int = 0
    var isFavorite: Bool = false

    init(
        id: UUID = UUID(),
        title: String,
        parentId: UUID? = nil,
        createdAt: Date = Date(),
        sortOrder: Int = 0,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.parentId = parentId
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.isFavorite = isFavorite
    }
}

/// Persisted search query entered by the user in the address bar.
@Model
final class RecentSearch {
    var id: UUID = UUID()
    var query: String = ""
    var searchedAt: Date = Date()

    init(id: UUID = UUID(), query: String, searchedAt: Date = Date()) {
        self.id = id
        self.query = query
        self.searchedAt = searchedAt
    }
}

/// Persisted page visit; one row per visit, no URL dedupe.
@Model
final class HistoryEntry {
    var id: UUID = UUID()
    var title: String = ""
    var url: URL = URL(string: "about:blank") ?? URL(filePath: "/")
    var visitedAt: Date = Date()

    init(id: UUID = UUID(), title: String, url: URL, visitedAt: Date) {
        self.id = id
        self.title = title
        self.url = url
        self.visitedAt = visitedAt
    }
}

/// Persisted mirror of a browser tab. Private tabs never reach a store; the
/// persisted copy is therefore always non-private.
@Model
final class TabRecord {
    var id: UUID = UUID()
    var url: URL?
    var title: String?
    var isPrivate: Bool = false
    var createdAt: Date = Date()
    var lastActiveAt: Date = Date()
    var groupId: UUID?

    /// Link-opened lineage: the id of the tab the user was viewing when this
    /// tab was created from a link. Set only by the two link-open creation
    /// sites; never scrubbed on close (readers fail closed when it is gone).
    var parentTabID: UUID?

    init(
        id: UUID = UUID(),
        url: URL? = nil,
        title: String? = nil,
        isPrivate: Bool,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        groupId: UUID? = nil,
        parentTabID: UUID? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.isPrivate = isPrivate
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.groupId = groupId
        self.parentTabID = parentTabID
    }
}

/// Schema for named tab groups; TabStore owns CRUD with 32-char clamp.
@Model
final class TabGroup {
    static let maxNameLength = 32

    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        // Names clamp at creation so persisted values never exceed the cap.
        self.name = String(name.prefix(Self.maxNameLength))
        self.createdAt = createdAt
    }
}

/// Single-row snapshot of the tab strip. `TabRecord` carries no order field,
/// so strip order and the selected tab live here across relaunches.
@Model
final class TabSession {
    var id: UUID = UUID()
    var tabIds: [UUID] = []
    var selectedTabId: UUID?
    /// Comma-joined uuidStrings in strip order; the array-backed store type
    /// does not sync through CloudKit, so this string is the synced order.
    var tabIdsEncoded: String = ""

    init(id: UUID, tabIds: [UUID] = [], selectedTabId: UUID? = nil, tabIdsEncoded: String = "") {
        self.id = id
        self.tabIds = tabIds
        self.selectedTabId = selectedTabId
        self.tabIdsEncoded = tabIdsEncoded
    }
}

/// Saved-for-later page; URL-based dedupe keeps the earliest row.
@Model
final class ReadingListItem {
    static let maxTitleLength = 200
    static let maxPreviewLength = 400

    var id: UUID = UUID()
    var title: String = ""
    var url: URL = URL(string: "about:blank") ?? URL(filePath: "/")
    var addedAt: Date = Date()
    var isRead: Bool = false
    var sortIndex: Int = 0
    var previewText: String?

    init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        addedAt: Date = Date(),
        isRead: Bool = false,
        sortIndex: Int = 0,
        previewText: String? = nil
    ) {
        self.id = id
        // Titles clamp at creation so persisted values never exceed the cap.
        self.title = String(title.prefix(Self.maxTitleLength))
        self.url = url
        self.addedAt = addedAt
        self.isRead = isRead
        self.sortIndex = sortIndex
        self.previewText = previewText.map { String($0.prefix(Self.maxPreviewLength)) }
    }
}
