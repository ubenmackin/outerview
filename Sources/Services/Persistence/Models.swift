//
//  Models.swift
//  OuterView
//

import Foundation
import SwiftData

/// Persisted bookmark; URL-based dedupe keeps the earliest row.
@Model
final class Bookmark {
    var id: UUID
    var title: String
    var url: URL
    var addedAt: Date
    var isFavorite: Bool
    var folderId: UUID?
    var sortOrder: Int

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
    var id: UUID
    var title: String
    var parentId: UUID?
    var createdAt: Date
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        title: String,
        parentId: UUID? = nil,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.parentId = parentId
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}

/// Persisted search query entered by the user in the address bar.
@Model
final class RecentSearch {
    var id: UUID
    var query: String
    var searchedAt: Date

    init(id: UUID = UUID(), query: String, searchedAt: Date = Date()) {
        self.id = id
        self.query = query
        self.searchedAt = searchedAt
    }
}

/// Persisted page visit; one row per visit, no URL dedupe.
@Model
final class HistoryEntry {
    var id: UUID
    var title: String
    var url: URL
    var visitedAt: Date

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
    var id: UUID
    var url: URL?
    var title: String?
    var isPrivate: Bool
    var createdAt: Date
    var lastActiveAt: Date
    var groupId: UUID?

    init(
        id: UUID = UUID(),
        url: URL? = nil,
        title: String? = nil,
        isPrivate: Bool,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        groupId: UUID? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.isPrivate = isPrivate
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.groupId = groupId
    }
}

/// Schema foundation for named tab groups; no store reads or writes it yet.
@Model
final class TabGroup {
    static let maxNameLength = 32

    var id: UUID
    var name: String
    var createdAt: Date

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
    var id: UUID
    var tabIds: [UUID]
    var selectedTabId: UUID?

    init(id: UUID, tabIds: [UUID] = [], selectedTabId: UUID? = nil) {
        self.id = id
        self.tabIds = tabIds
        self.selectedTabId = selectedTabId
    }
}

/// Saved-for-later page; URL-based dedupe keeps the earliest row.
@Model
final class ReadingListItem {
    static let maxTitleLength = 200
    static let maxPreviewLength = 400

    var id: UUID
    var title: String
    var url: URL
    var addedAt: Date
    var isRead: Bool
    var sortIndex: Int
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
