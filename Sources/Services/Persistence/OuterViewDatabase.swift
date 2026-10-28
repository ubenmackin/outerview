//
//  OuterViewDatabase.swift
//  OuterView
//

import Foundation
import SwiftData

/// Sole owner of the app's `ModelContainer`; every store shares this one
/// context so cross-store reads see a single consistent snapshot.
@MainActor
final class OuterViewDatabase {
    let container: ModelContainer
    let context: ModelContext

    /// On-disk by default; `inMemory: true` gives tests an isolated store.
    init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(
            for: Bookmark.self, BookmarkFolder.self, RecentSearch.self, HistoryEntry.self,
            TabRecord.self, TabGroup.self, TabSession.self, ReadingListItem.self,
            configurations: configuration
        )
        context = container.mainContext
        // Explicit saves only; implicit autosaves would race the stores'
        // deterministic save-then-read sequences.
        context.autosaveEnabled = false
    }
}
