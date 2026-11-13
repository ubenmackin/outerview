// Tests — iCloud sync contracts for container, encoding, mirror, plus status.

import CloudKit
import CoreData
@testable import OuterView
import SwiftData
import XCTest

/// Isolated KVS double: the shared store is process-global, so suites inject
/// this instead and never touch the real ubiquity container.
private final class MockKeyValueStore: NSUbiquitousKeyValueStore {
    var storage: [String: Any] = [:]
    var synchronizeResult = true
    var synchronizeCallCount = 0
    var outage = false

    override func object(forKey key: String) -> Any? {
        guard !outage else { return nil }
        return storage[key]
    }

    override func set(_ value: Any?, forKey key: String) {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    override func removeObject(forKey key: String) {
        storage.removeValue(forKey: key)
    }

    override func synchronize() -> Bool {
        synchronizeCallCount += 1
        return synchronizeResult && !outage
    }
}

@MainActor
final class CloudSyncTests: XCTestCase {
    private static let containerID = "iCloud.com.volcrypt.OuterView"

    private func makeDefaults() throws -> UserDefaults {
        let name = "CloudSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }

    private func makeDatabase() throws -> OuterViewDatabase {
        try OuterViewDatabase(inMemory: true)
    }

    private func makeMonitor(
        defaults: UserDefaults,
        center: NotificationCenter = NotificationCenter(),
        provider: (@Sendable () async -> CKAccountStatus)? = nil
    ) -> CloudSyncMonitor {
        CloudSyncMonitor(defaults: defaults, notificationCenter: center, accountStatusProvider: provider)
    }

    private func makeMirror(defaults: UserDefaults, kvs: NSUbiquitousKeyValueStore) -> SyncedSettingsStore {
        SyncedSettingsStore(defaults: defaults, keyValueStore: kvs, notificationCenter: NotificationCenter())
    }

    private func tab(_ name: String) -> TabRecord {
        TabRecord(
            url: URL(string: "https://example.com/\(name.lowercased())"),
            title: name,
            isPrivate: false
        )
    }

    private func snapshotRow(in database: OuterViewDatabase) throws -> TabSession {
        let rows = try database.context.fetch(FetchDescriptor<TabSession>())
        return try XCTUnwrap(rows.first)
    }

    /// Status is not Equatable, so tests compare exhaustive name snapshots instead.
    private func statusName(_ status: CloudSyncMonitor.Status) -> String {
        switch status {
        case .waitingForSignIn:
            "waitingForSignIn"
        case .syncing:
            "syncing"
        case .synced:
            "synced"
        case .failed:
            "failed"
        }
    }

    // MARK: - Container identity

    func testContainerIdentifiersMatchPrivateDatabase() {
        XCTAssertEqual(OuterViewDatabase.cloudKitContainerIdentifier, Self.containerID)
        XCTAssertEqual(CloudSyncMonitor.containerIdentifier, Self.containerID)
    }

    func testOnDiskConfigurationTargetsPrivateDatabase() {
        let described = String(describing: OuterViewDatabase.cloudKitConfiguration().cloudKitDatabase)
        XCTAssertTrue(
            described.contains(Self.containerID),
            "On-disk configuration must target the private CloudKit database, got \(described)"
        )
    }

    func testInMemoryAndLocalConfigurationsStayLocalOnly() throws {
        let inMemoryDescribed = String(describing: OuterViewDatabase.inMemoryConfiguration().cloudKitDatabase)
        XCTAssertFalse(
            inMemoryDescribed.contains(Self.containerID),
            "In-memory configuration must stay local-only, got \(inMemoryDescribed)"
        )
        let localDescribed = String(describing: OuterViewDatabase.localConfiguration().cloudKitDatabase)
        XCTAssertFalse(
            localDescribed.contains(Self.containerID),
            "Local fallback configuration must stay local-only, got \(localDescribed)"
        )
        XCTAssertTrue(OuterViewDatabase.inMemoryConfiguration().isStoredInMemoryOnly)
        XCTAssertNoThrow(try OuterViewDatabase(inMemory: true))
    }

    // MARK: - TabSession encoding

    func testSessionEncodeRoundTripPreservesOrderAndSelection() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let tabs = [tab("A"), tab("B"), tab("C")]
        try store.saveSession(tabs: tabs, selected: tabs[1].id)

        let snapshot = try snapshotRow(in: database)
        XCTAssertEqual(snapshot.tabIds, tabs.map(\.id))
        XCTAssertEqual(snapshot.tabIdsEncoded, tabs.map(\.id).map(\.uuidString).joined(separator: ","))

        let (loaded, selected) = store.loadSession()
        XCTAssertEqual(loaded.map(\.id), tabs.map(\.id))
        XCTAssertEqual(selected, tabs[1].id)
    }

    func testSessionLegacyArrayFallbackWhenEncodedIsEmpty() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let tabs = [tab("A"), tab("B")]
        try store.saveSession(tabs: tabs, selected: tabs[0].id)

        // An empty payload marks a pre-migration row, so order falls back to the legacy array.
        let snapshot = try snapshotRow(in: database)
        snapshot.tabIdsEncoded = ""
        try database.context.save()

        let (loaded, selected) = store.loadSession()
        XCTAssertEqual(loaded.map(\.id), tabs.map(\.id))
        XCTAssertEqual(selected, tabs[0].id)
    }

    func testSessionDropsUnknownAndMalformedIDs() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let tabs = [tab("A"), tab("B")]
        try store.saveSession(tabs: tabs, selected: nil)
        let snapshot = try snapshotRow(in: database)
        let unknown = UUID()

        snapshot.tabIdsEncoded = [
            tabs[0].id.uuidString,
            "not-a-uuid",
            "",
            unknown.uuidString,
            tabs[1].id.uuidString
        ].joined(separator: ",")
        snapshot.tabIds = [tabs[0].id, unknown, tabs[1].id]
        try database.context.save()

        // Encoded order wins when present, so malformed plus unknown segments drop here.
        XCTAssertEqual(store.loadSession().tabs.map(\.id), tabs.map(\.id))

        // With no encoded payload the legacy array drops ids that resolve to no row.
        snapshot.tabIdsEncoded = ""
        try database.context.save()
        XCTAssertEqual(store.loadSession().tabs.map(\.id), tabs.map(\.id))
    }

    func testSessionEncodeBoundCapsAt5000IDs() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let many = (0 ..< 5005).map { _ in TabRecord(isPrivate: false) }

        // Reorder writes the snapshot without persisting rows, keeping this bound check cheap.
        try store.reorder(tabs: many)

        let snapshot = try snapshotRow(in: database)
        XCTAssertEqual(snapshot.tabIds.count, 5000)
        XCTAssertEqual(snapshot.tabIds, Array(many.map(\.id).prefix(5000)))
        XCTAssertEqual(snapshot.tabIdsEncoded.split(separator: ",").count, 5000)
        XCTAssertEqual(
            snapshot.tabIdsEncoded,
            many.map(\.id).prefix(5000).map(\.uuidString).joined(separator: ",")
        )

        // Capped ids resolve to no rows, so restore stays empty instead of surfacing ghosts.
        let (loaded, selected) = store.loadSession()
        XCTAssertTrue(loaded.isEmpty)
        XCTAssertNil(selected)
    }

    // MARK: - Synced keys

    func testSyncedKeysAreExactlyTheContractedSet() {
        XCTAssertEqual(
            Set(SyncedSettingsStore.syncedKeys),
            Set([
                "searchEngine",
                "requireBiometricsForPrivateTabs",
                "blockTrackersAndAds",
                "portraitTabBarPosition",
                "readerTheme",
                "readerFontSize",
                "siteZoom",
                "websiteSettings"
            ])
        )
        XCTAssertEqual(SyncedSettingsStore.syncedKeys.count, 8)
    }

    func testTransientKeysStayLocalOnly() {
        let synced = Set(SyncedSettingsStore.syncedKeys)
        XCTAssertTrue(synced.contains(SettingsViewModel.searchEngineDefaultsKey))
        XCTAssertTrue(synced.contains(SettingsViewModel.requireBiometricsDefaultsKey))
        XCTAssertTrue(synced.contains(SettingsViewModel.blockTrackersDefaultsKey))
        XCTAssertTrue(synced.contains(SettingsViewModel.portraitTabBarPositionDefaultsKey))
        XCTAssertTrue(synced.contains(ReaderMode.themeDefaultsKey))
        XCTAssertTrue(synced.contains(ReaderMode.fontSizeDefaultsKey))
        XCTAssertTrue(synced.contains(SiteZoomStore.storeKey))
        XCTAssertTrue(synced.contains(WebsiteSettingsStore.storeKey))

        XCTAssertFalse(synced.contains(SyncedSettingsStore.iCloudSyncEnabledKey))
        XCTAssertFalse(synced.contains(LibraryTabBar.libraryTabDefaultsKey))
        XCTAssertFalse(synced.contains(TabOverviewViewController.overviewModeDefaultsKey))
        XCTAssertFalse(synced.contains(TabOverviewViewController.overviewGroupDefaultsKey))
        XCTAssertFalse(synced.contains(BookmarksBrowserView.displayModeDefaultsKey))
        XCTAssertFalse(synced.contains(BookmarksBrowserView.sortModeDefaultsKey))
        XCTAssertFalse(synced.contains(BookmarksBrowserView.showsFoldersOnTopDefaultsKey))
        XCTAssertFalse(synced.contains(ReadingListView.displayModeDefaultsKey))
        XCTAssertFalse(synced.contains(ReadingListView.filterModeDefaultsKey))
    }

    func testToggleKeyNeverMirrorsToRemote() throws {
        let defaults = try makeDefaults()
        let kvs = MockKeyValueStore()
        defaults.set(true, forKey: SyncedSettingsStore.iCloudSyncEnabledKey)
        let store = makeMirror(defaults: defaults, kvs: kvs)

        store.set(true, forKey: SyncedSettingsStore.iCloudSyncEnabledKey)

        XCTAssertNil(kvs.storage[SyncedSettingsStore.iCloudSyncEnabledKey])
        XCTAssertEqual(store.storedValue(forKey: SyncedSettingsStore.iCloudSyncEnabledKey, as: Bool.self), true)
    }

    // MARK: - Settings mirror

    func testMirrorPrefersRemoteWhenToggleIsOn() throws {
        let defaults = try makeDefaults()
        let kvs = MockKeyValueStore()
        defaults.set(true, forKey: SyncedSettingsStore.iCloudSyncEnabledKey)
        defaults.set("local-engine", forKey: "searchEngine")
        kvs.storage["searchEngine"] = "remote-engine"
        let store = makeMirror(defaults: defaults, kvs: kvs)
        let monitor = makeMonitor(defaults: defaults)
        // Monitor owns stamping; store only notifies.
        store.onSyncSucceeded = { monitor.noteImportSucceeded() }

        XCTAssertEqual(store.storedValue(forKey: "searchEngine", as: String.self), "remote-engine")

        store.set("fresh-engine", forKey: "searchEngine")
        XCTAssertEqual(defaults.string(forKey: "searchEngine"), "fresh-engine")
        XCTAssertEqual(kvs.storage["searchEngine"] as? String, "fresh-engine")

        store.startSync()
        XCTAssertEqual(defaults.string(forKey: "searchEngine"), "fresh-engine")
        XCTAssertNotNil(monitor.lastSyncDate)
        XCTAssertNotNil(defaults.object(forKey: SyncedSettingsStore.lastSyncDateKey))
    }

    func testMirrorStaysLocalWhenToggleIsOff() throws {
        let defaults = try makeDefaults()
        let kvs = MockKeyValueStore()
        defaults.set(false, forKey: SyncedSettingsStore.iCloudSyncEnabledKey)
        defaults.set("local-engine", forKey: "searchEngine")
        kvs.storage["searchEngine"] = "remote-engine"
        let store = makeMirror(defaults: defaults, kvs: kvs)

        XCTAssertEqual(store.storedValue(forKey: "searchEngine", as: String.self), "local-engine")

        store.set("edited-engine", forKey: "searchEngine")
        XCTAssertEqual(defaults.string(forKey: "searchEngine"), "edited-engine")
        XCTAssertEqual(kvs.storage["searchEngine"] as? String, "remote-engine")

        store.startSync()
        XCTAssertEqual(defaults.string(forKey: "searchEngine"), "edited-engine")
        XCTAssertNil(defaults.object(forKey: SyncedSettingsStore.lastSyncDateKey))
    }

    func testMirrorBackfillsEmptyRemoteKeysWithoutOverwriting() throws {
        let defaults = try makeDefaults()
        let kvs = MockKeyValueStore()
        defaults.set(true, forKey: SyncedSettingsStore.iCloudSyncEnabledKey)
        defaults.set("local-engine", forKey: "searchEngine")
        defaults.set("local-theme", forKey: "readerTheme")
        kvs.storage["readerTheme"] = "remote-theme"
        let store = makeMirror(defaults: defaults, kvs: kvs)

        store.startSync()

        XCTAssertEqual(kvs.storage["searchEngine"] as? String, "local-engine")
        XCTAssertEqual(kvs.storage["readerTheme"] as? String, "remote-theme")
        XCTAssertEqual(defaults.string(forKey: "readerTheme"), "remote-theme")
        XCTAssertGreaterThan(kvs.synchronizeCallCount, 0)
    }

    func testMirrorSurvivesKeyValueStoreOutage() throws {
        let defaults = try makeDefaults()
        let kvs = MockKeyValueStore()
        kvs.outage = true
        defaults.set(true, forKey: SyncedSettingsStore.iCloudSyncEnabledKey)
        defaults.set("local-engine", forKey: "searchEngine")
        let store = makeMirror(defaults: defaults, kvs: kvs)

        // Every entry point fails closed to local state instead of throwing.
        store.startSync()
        store.set("edited-engine", forKey: "searchEngine")
        XCTAssertEqual(store.storedValue(forKey: "searchEngine", as: String.self), "edited-engine")
        XCTAssertFalse(store.synchronize())
        XCTAssertEqual(defaults.string(forKey: "searchEngine"), "edited-engine")
    }

    // MARK: - Sync monitor

    func testMonitorMapsAccountStates() {
        XCTAssertEqual(statusName(CloudSyncMonitor.status(for: .available)), "syncing")
        XCTAssertEqual(statusName(CloudSyncMonitor.status(for: .noAccount)), "waitingForSignIn")
        XCTAssertEqual(statusName(CloudSyncMonitor.status(for: .restricted)), "waitingForSignIn")
        XCTAssertEqual(statusName(CloudSyncMonitor.status(for: .couldNotDetermine)), "waitingForSignIn")
        XCTAssertEqual(statusName(CloudSyncMonitor.status(for: .temporarilyUnavailable)), "waitingForSignIn")
    }

    func testRefreshAccountStatusUsesInjectedProvider() async throws {
        let defaults = try makeDefaults()
        let available = makeMonitor(defaults: defaults, provider: { .available })
        await available.refreshAccountStatus()
        XCTAssertEqual(statusName(available.status), "syncing")

        let signedOut = makeMonitor(defaults: defaults, provider: { .noAccount })
        await signedOut.refreshAccountStatus()
        XCTAssertEqual(statusName(signedOut.status), "waitingForSignIn")
    }

    func testMonitorClampsFailureTextTo200Chars() throws {
        let defaults = try makeDefaults()
        let monitor = makeMonitor(defaults: defaults)
        XCTAssertEqual(CloudSyncMonitor.maxErrorMessageLength, 200)

        let long = String(repeating: "x", count: 300)
        monitor.noteSyncFailed(long)
        XCTAssertEqual(statusName(monitor.status), "failed")
        XCTAssertEqual(monitor.lastErrorMessage?.count, 200)
        XCTAssertEqual(monitor.lastErrorMessage, String(long.prefix(200)))

        monitor.noteSyncFailed("short")
        XCTAssertEqual(monitor.lastErrorMessage, "short")
    }

    func testMonitorClearsFailureOnNextSuccess() throws {
        let defaults = try makeDefaults()
        let monitor = makeMonitor(defaults: defaults)
        monitor.noteSyncFailed("boom")
        XCTAssertEqual(statusName(monitor.status), "failed")

        monitor.noteImportSucceeded()
        XCTAssertEqual(statusName(monitor.status), "synced")
        XCTAssertNil(monitor.lastErrorMessage)
        XCTAssertNotNil(monitor.lastSyncDate)
    }

    func testMonitorStampsAndRestoresLastSyncDate() throws {
        let defaults = try makeDefaults()
        let monitor = makeMonitor(defaults: defaults)
        XCTAssertNil(monitor.lastSyncDate)

        monitor.noteImportSucceeded()
        let stamped = try XCTUnwrap(monitor.lastSyncDate)
        let stored = try XCTUnwrap(defaults.object(forKey: CloudSyncMonitor.lastSyncDateKey) as? Date)
        XCTAssertEqual(stored.timeIntervalSince1970, stamped.timeIntervalSince1970, accuracy: 0.001)

        let restored = makeMonitor(defaults: defaults)
        let restoredDate = try XCTUnwrap(restored.lastSyncDate)
        XCTAssertEqual(restoredDate.timeIntervalSince1970, stamped.timeIntervalSince1970, accuracy: 0.001)
    }

    func testMonitorIgnoresPayloadlessCloudKitEvent() async throws {
        let defaults = try makeDefaults()
        let center = NotificationCenter()
        let monitor = makeMonitor(defaults: defaults, center: center)

        center.post(name: NSPersistentCloudKitContainer.eventChangedNotification, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(statusName(monitor.status), "waitingForSignIn")
        XCTAssertNil(monitor.lastErrorMessage)
        XCTAssertNil(monitor.lastSyncDate)
    }

    func testMonitorStampsDateOnKeyValueStoreChange() async throws {
        let defaults = try makeDefaults()
        let center = NotificationCenter()
        let monitor = makeMonitor(defaults: defaults, center: center)
        XCTAssertNil(monitor.lastSyncDate)

        center.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil)
        for _ in 0 ..< 100 {
            if monitor.lastSyncDate != nil {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertNotNil(monitor.lastSyncDate)
        XCTAssertNotNil(defaults.object(forKey: CloudSyncMonitor.lastSyncDateKey))
    }

    // MARK: - Status surface

    func testSyncStatusSurfaceExposesExactlyFourCases() {
        // Exhaustive with no default: adding or removing a status breaks this contract,
        // forcing the Settings status UI to account for the new case.
        let names = [
            statusName(.waitingForSignIn),
            statusName(.syncing),
            statusName(.synced),
            statusName(.failed)
        ]
        XCTAssertEqual(Set(names).count, 4)
    }

    // MARK: - Private-tab exclusion under sync writes

    func testUpsertDropsPrivateTabsFromBothEncodedAndLegacyFields() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let visible = tab("A")
        let hidden = TabRecord(
            url: URL(string: "https://example.com/hidden"),
            title: "Hidden",
            isPrivate: true
        )
        try store.saveSession(tabs: [visible], selected: visible.id)

        try store.upsertTab(hidden)

        let snapshot = try snapshotRow(in: database)
        XCTAssertFalse(snapshot.tabIds.contains(hidden.id))
        XCTAssertFalse(snapshot.tabIdsEncoded.split(separator: ",").map(String.init).contains(hidden.id.uuidString))
        let (loaded, selected) = store.loadSession()
        XCTAssertEqual(loaded.map(\.id), [visible.id])
        XCTAssertEqual(selected, visible.id)
    }

    func testSaveSessionDropsPrivateTabsFromBothFields() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let visible = tab("A")
        let hidden = TabRecord(
            url: URL(string: "https://example.com/hidden"),
            title: "Hidden",
            isPrivate: true
        )
        let otherHidden = TabRecord(
            url: URL(string: "https://example.com/other"),
            title: "Other",
            isPrivate: true
        )

        try store.saveSession(tabs: [hidden, visible, otherHidden], selected: visible.id)

        let snapshot = try snapshotRow(in: database)
        XCTAssertEqual(snapshot.tabIds, [visible.id])
        XCTAssertEqual(snapshot.tabIdsEncoded, visible.id.uuidString)
        let (loaded, selected) = store.loadSession()
        XCTAssertEqual(loaded.map(\.id), [visible.id])
        XCTAssertEqual(selected, visible.id)

        let records = try database.context.fetch(FetchDescriptor<TabRecord>())
        XCTAssertFalse(records.contains { $0.isPrivate })
    }
}
