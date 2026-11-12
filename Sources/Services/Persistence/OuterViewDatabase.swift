// Persistence — SwiftData container plus shared context owner.

import Foundation
import os
import SwiftData

/// Sole owner of the app's `ModelContainer`; every store shares this one
/// context so cross-store reads see a single consistent snapshot.
@MainActor
final class OuterViewDatabase {
    nonisolated static let cloudKitContainerIdentifier = "iCloud.com.volcrypt.OuterView"

    let container: ModelContainer
    let context: ModelContext

    /// On-disk by default; `inMemory: true` gives tests an isolated store.
    init(inMemory: Bool = false) throws {
        if inMemory {
            container = try Self.makeContainer(configuration: Self.inMemoryConfiguration())
        } else if !SyncedSettingsStore.isSyncEnabled() {
            // Sync opted out: stay local-only so no library model syncs via CloudKit.
            container = try Self.makeContainer(configuration: Self.localConfiguration())
        } else {
            do {
                container = try Self.makeContainer(configuration: Self.cloudKitConfiguration())
            } catch {
                // CloudKit setup can throw when the container is unavailable;
                // fall back to a local-only store with identical schema.
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("CloudKit container setup failed, falling back to local store: \(error.localizedDescription, privacy: .public)")
                iCloudSyncMonitor.shared.reportSetupFailure(error)
                container = try Self.makeContainer(configuration: Self.localConfiguration())
            }
        }
        context = container.mainContext
        // Explicit saves only; implicit autosaves would race the stores'
        // deterministic save-then-read sequences.
        context.autosaveEnabled = false
    }

    static func inMemoryConfiguration() -> ModelConfiguration {
        ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    }

    static func cloudKitConfiguration() -> ModelConfiguration {
        ModelConfiguration(cloudKitDatabase: .private(cloudKitContainerIdentifier))
    }

    /// Fallback file stays distinct so local data never meets CloudKit metadata.
    static func localConfiguration() -> ModelConfiguration {
        ModelConfiguration("OuterViewLocal", cloudKitDatabase: .none)
    }

    private static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        // Property defaults in Models keep every attribute CloudKit-ready and
        // let lightweight migration fill tabIdsEncoded for pre-migration rows.
        try ModelContainer(
            for: Bookmark.self,
            BookmarkFolder.self,
            HistoryEntry.self,
            RecentSearch.self,
            ReadingListItem.self,
            TabRecord.self,
            TabGroup.self,
            TabSession.self,
            configurations: configuration
        )
    }
}
