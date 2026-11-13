// Persistence — iCloud account plus CloudKit and KVS event status owner.

import CloudKit
import CoreData
import Foundation
import Observation
import os

@MainActor
@Observable
final class CloudSyncMonitor {
    enum Status: Sendable {
        case waitingForSignIn
        case syncing
        case synced
        case failed
    }

    nonisolated static let containerIdentifier = OuterViewDatabase.cloudKitContainerIdentifier
    nonisolated static let lastSyncDateKey = SyncedSettingsStore.lastSyncDateKey
    nonisolated static let maxErrorMessageLength = 200

    static let shared = CloudSyncMonitor()

    var status: Status = .waitingForSignIn
    var lastSyncDate: Date?
    var lastErrorMessage: String?

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let notificationCenter: NotificationCenter
    @ObservationIgnored
    private let accountStatusProvider: (@Sendable () async -> CKAccountStatus)?

    @ObservationIgnored
    private var cloudKitObserverToken: NSObjectProtocol?
    @ObservationIgnored
    private var keyValueObserverToken: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        accountStatusProvider: (@Sendable () async -> CKAccountStatus)? = nil
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.accountStatusProvider = accountStatusProvider
        self.lastSyncDate = defaults.object(forKey: Self.lastSyncDateKey) as? Date
        startObserving()
    }

    isolated deinit {
        if let cloudKitObserverToken {
            notificationCenter.removeObserver(cloudKitObserverToken)
        }
        if let keyValueObserverToken {
            notificationCenter.removeObserver(keyValueObserverToken)
        }
    }

    func refreshAccountStatus() async {
        let resolved = if let accountStatusProvider {
            await accountStatusProvider()
        } else {
            await Self.queryAccountStatus()
        }
        // Terminal states stick: KVS success and setup failure outlive account-only refreshes.
        guard status != .synced, status != .failed else { return }
        status = Self.status(for: resolved)
    }

    func noteImportSucceeded() {
        stampSyncDate()
        status = .synced
        lastErrorMessage = nil
    }

    func noteSyncFailed(_ message: String) {
        status = .failed
        if message.count > Self.maxErrorMessageLength {
            lastErrorMessage = String(message.prefix(Self.maxErrorMessageLength))
        } else {
            lastErrorMessage = message
        }
    }

    /// Surface container setup failures through the shared failure path.
    func reportSetupFailure(_ error: Error) {
        noteSyncFailed(error.localizedDescription)
    }

    nonisolated static func status(for accountStatus: CKAccountStatus) -> Status {
        switch accountStatus {
        case .available:
            .syncing
        default:
            .waitingForSignIn
        }
    }

    private nonisolated static func queryAccountStatus() async -> CKAccountStatus {
        do {
            return try await CKContainer(identifier: containerIdentifier).accountStatus()
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Sync")
                .error("CloudKit account status query failed: \(error.localizedDescription, privacy: .public)")
            return .couldNotDetermine
        }
    }

    private func startObserving() {
        if cloudKitObserverToken == nil {
            cloudKitObserverToken = notificationCenter.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: nil
            ) { [weak self] note in
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                    return
                }
                let isImport = event.type == .import
                let isExport = event.type == .export
                let errorMessage = event.error?.localizedDescription
                let didEnd = event.endDate != nil
                Task { [weak self] in
                    await self?.handleCloudKitEvent(isImport: isImport, isExport: isExport, errorMessage: errorMessage, didEnd: didEnd)
                }
            }
        }
        if keyValueObserverToken == nil {
            keyValueObserverToken = notificationCenter.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { [weak self] in
                    await self?.handleKeyValueStoreChange()
                }
            }
        }
    }

    private func handleCloudKitEvent(isImport: Bool, isExport: Bool, errorMessage: String?, didEnd: Bool) {
        // Remote traffic applies only when the toggle opts in.
        guard isSyncEnabled else { return }
        if let errorMessage {
            // Only import/export failures surface; setup noise stays silent.
            if isImport || isExport {
                noteSyncFailed(errorMessage)
            }
            return
        }
        guard didEnd else { return }
        // Either direction marks synced so export-only devices advance.
        if isImport || isExport {
            noteImportSucceeded()
        }
    }

    private func handleKeyValueStoreChange() {
        // Remote KVS traffic applies only when the toggle opts in.
        guard isSyncEnabled else { return }
        noteImportSucceeded()
    }

    /// Missing toggle means opt-in; the launch gate uses the same helper.
    private var isSyncEnabled: Bool {
        SyncedSettingsStore.isSyncEnabled(defaults: defaults)
    }

    /// Remote KVS pulls stamp through noteImportSucceeded only.
    private func stampSyncDate() {
        let now = Date()
        lastSyncDate = now
        defaults.set(now, forKey: Self.lastSyncDateKey)
    }
}
