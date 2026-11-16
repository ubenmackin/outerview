// Persistence — SwiftData container plus shared context owner.

import Foundation
import os
import SwiftData

/// Sole owner of the app's `ModelContainer`; every store shares this one
/// context so cross-store reads see a single consistent snapshot.
@MainActor
final class OuterViewDatabase {
    nonisolated static let cloudKitContainerIdentifier = "iCloud.com.volcrypt.OuterView"

    /// The only model roster in the codebase.
    nonisolated static let syncedModelTypes: [any PersistentModel.Type] = [
        Bookmark.self,
        BookmarkFolder.self,
        HistoryEntry.self,
        RecentSearch.self,
        ReadingListItem.self,
        TabRecord.self,
        TabGroup.self,
        TabSession.self
    ]

    let container: ModelContainer
    let context: ModelContext

    /// On-disk by default; `inMemory: true` gives tests an isolated store.
    init(inMemory: Bool = false) throws {
        let reconciliationMode: ReconciliationMode?
        if inMemory {
            container = try Self.makeContainer(configuration: Self.inMemoryConfiguration())
            reconciliationMode = nil
        } else if !SyncedSettingsStore.isSyncEnabled() {
            // Sync opted out: stay local-only so no library model syncs via CloudKit.
            container = try Self.makeContainer(configuration: Self.localConfiguration())
            reconciliationMode = .local
        } else {
            do {
                container = try Self.makeContainer(configuration: Self.cloudKitConfiguration())
                reconciliationMode = .cloud
            } catch {
                // CloudKit setup can throw when the container is unavailable;
                // fall back to a local-only store with identical schema.
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("CloudKit container setup failed, falling back to local store: \(error.localizedDescription, privacy: .public)")
                CloudSyncMonitor.shared.reportSetupFailure(error)
                container = try Self.makeContainer(configuration: Self.localConfiguration())
                reconciliationMode = .local
            }
        }
        context = container.mainContext
        // Explicit saves only; implicit autosaves would race the stores'
        // deterministic save-then-read sequences.
        context.autosaveEnabled = false
        // Reconciliation runs post-init on the MainActor; the in-memory path
        // schedules nothing.
        if let reconciliationMode {
            scheduleReconciliation(mode: reconciliationMode)
        }
    }

    static func inMemoryConfiguration() -> ModelConfiguration {
        ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    }

    static func cloudKitConfiguration() -> ModelConfiguration {
        ModelConfiguration(cloudKitDatabase: .private(cloudKitContainerIdentifier))
    }

    /// Unnamed configuration targeting default.store without CloudKit;
    /// SwiftData's persistent-history tracking lets a formerly
    /// CloudKit-managed store re-open plainly here.
    static func plainDefaultConfiguration() -> ModelConfiguration {
        ModelConfiguration(cloudKitDatabase: .none)
    }

    /// Fallback file stays distinct so local data never meets CloudKit metadata;
    /// StoreReconciler copies default.store rows into it once at fallback launch.
    static func localConfiguration() -> ModelConfiguration {
        ModelConfiguration("OuterViewLocal", cloudKitDatabase: .none)
    }

    private static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        // Property defaults in Models keep every attribute CloudKit-ready and
        // let lightweight migration fill tabIdsEncoded for pre-migration rows.
        try ModelContainer(
            for: Schema(syncedModelTypes),
            configurations: [configuration]
        )
    }

    private enum ReconciliationMode: Sendable {
        case local
        case cloud
    }

    /// One-shot bootstrap copy between default.store and the local fallback
    /// file, scheduled after init so the synchronous launch path stays fast;
    /// failures log here and never surface through the sync monitor.
    private func scheduleReconciliation(mode: ReconciliationMode) {
        Task { @MainActor in
            do {
                // Local runs copy cloud-managed default.store rows into the
                // fallback file; cloud runs copy local rows into default.store
                // ahead of CloudKit.
                switch mode {
                case .local:
                    try StoreReconciler.reconcile(
                        direction: .cloudToLocal,
                        models: Self.syncedModelTypes,
                        destination: container,
                        sourceConfiguration: Self.plainDefaultConfiguration()
                    )
                case .cloud:
                    try StoreReconciler.reconcile(
                        direction: .localToCloud,
                        models: Self.syncedModelTypes,
                        destination: container,
                        sourceConfiguration: Self.localConfiguration()
                    )
                }
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("Store reconciliation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
