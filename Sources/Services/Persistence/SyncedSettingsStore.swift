// Persistence — iCloud key-value mirror for lightweight settings.

import Foundation

/// Plist-safe value types mirrored cleanly through `SyncedSettingsStore` without type erasure.
protocol SyncedPlistValue: Sendable {
    func write(to defaults: UserDefaults, forKey key: String)
    func write(to store: NSUbiquitousKeyValueStore, forKey key: String)
}

extension Bool: SyncedPlistValue {
    func write(to defaults: UserDefaults, forKey key: String) {
        defaults.set(self, forKey: key)
    }

    func write(to store: NSUbiquitousKeyValueStore, forKey key: String) {
        store.set(self, forKey: key)
    }
}

extension Int: SyncedPlistValue {
    func write(to defaults: UserDefaults, forKey key: String) {
        defaults.set(self, forKey: key)
    }

    func write(to store: NSUbiquitousKeyValueStore, forKey key: String) {
        store.set(self, forKey: key)
    }
}

extension String: SyncedPlistValue {
    func write(to defaults: UserDefaults, forKey key: String) {
        defaults.set(self, forKey: key)
    }

    func write(to store: NSUbiquitousKeyValueStore, forKey key: String) {
        store.set(self, forKey: key)
    }
}

extension Data: SyncedPlistValue {
    func write(to defaults: UserDefaults, forKey key: String) {
        defaults.set(self, forKey: key)
    }

    func write(to store: NSUbiquitousKeyValueStore, forKey key: String) {
        store.set(self, forKey: key)
    }
}

extension [String: Double]: SyncedPlistValue {
    func write(to defaults: UserDefaults, forKey key: String) {
        defaults.set(self, forKey: key)
    }

    func write(to store: NSUbiquitousKeyValueStore, forKey key: String) {
        store.set(self, forKey: key)
    }
}

@MainActor
public final class SyncedSettingsStore {
    nonisolated static let iCloudSyncEnabledKey = "iCloudSyncEnabled"
    nonisolated static let lastSyncDateKey = "iCloudLastSyncDate"
    nonisolated static let syncedKeys: [String] = [
        SettingsViewModel.searchEngineDefaultsKey,
        SettingsViewModel.requireBiometricsDefaultsKey,
        SettingsViewModel.blockTrackersDefaultsKey,
        SettingsViewModel.portraitTabBarPositionDefaultsKey,
        ReaderMode.themeDefaultsKey,
        ReaderMode.fontSizeDefaultsKey,
        SiteZoomStore.storeKey,
        WebsiteSettingsStore.storeKey
    ]

    static let shared = SyncedSettingsStore()

    private let defaults: UserDefaults
    private let keyValueStore: NSUbiquitousKeyValueStore
    private let notificationCenter: NotificationCenter
    private var kvsObserverToken: NSObjectProtocol?
    /// Single owner: monitor stamps last-sync; store only notifies.
    /// The pull below always runs before the notify.
    var onSyncSucceeded: (@MainActor () -> Void)?

    init(
        defaults: UserDefaults = .standard,
        keyValueStore: NSUbiquitousKeyValueStore = .default,
        notificationCenter: NotificationCenter = .default,
        onSyncSucceeded: (@MainActor () -> Void)? = nil
    ) {
        self.defaults = defaults
        self.keyValueStore = keyValueStore
        self.notificationCenter = notificationCenter
        self.onSyncSucceeded = onSyncSucceeded
    }

    isolated deinit {
        if let kvsObserverToken {
            notificationCenter.removeObserver(kvsObserverToken)
        }
    }

    func startSync() {
        if kvsObserverToken == nil {
            kvsObserverToken = notificationCenter.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { [weak self] in
                    _ = await self?.pullRemoteValues()
                }
            }
        }
        let applied = pullRemoteValues()
        let pushed = backfillEmptyKeys()
        // Fresh reachable stores stamp once via monitor; outage stamps nothing.
        if pushed, !applied {
            onSyncSucceeded?()
        }
    }

    func set(_ value: some SyncedPlistValue, forKey key: String) {
        value.write(to: defaults, forKey: key)
        // Toggle itself stays local-only; only synced keys mirror to KVS.
        guard !isTestIsolated, isSyncEnabled, Self.syncedKeys.contains(key) else { return }
        value.write(to: keyValueStore, forKey: key)
    }

    func clearValue(forKey key: String) {
        defaults.removeObject(forKey: key)
        guard !isTestIsolated, isSyncEnabled, Self.syncedKeys.contains(key) else { return }
        keyValueStore.removeObject(forKey: key)
    }

    func storedValue<T>(forKey key: String, as _: T.Type = T.self) -> T? {
        guard !isTestIsolated, isSyncEnabled,
              Self.syncedKeys.contains(key)
        else {
            return defaults.object(forKey: key) as? T
        }
        // KVS miss fails closed to the local default.
        if let remote = keyValueStore.object(forKey: key) {
            return remote as? T
        }
        return defaults.object(forKey: key) as? T
    }

    /// Missing toggle means opt-in; bool(forKey:) reads missing as false.
    nonisolated static func isSyncEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: iCloudSyncEnabledKey) as? Bool ?? true
    }

    var isSyncEnabled: Bool {
        Self.isSyncEnabled(defaults: defaults)
    }

    /// Test suites share process KVS; isolate them to local defaults.
    private var isTestIsolated: Bool {
        AppEnvironment.isTestHost && keyValueStore === NSUbiquitousKeyValueStore.default
    }

    func mirroredString(forKey key: String) -> String? {
        guard isSyncEnabled else { return nil }
        return storedValue(forKey: key, as: String.self)
    }

    func mirroredBool(forKey key: String) -> Bool? {
        guard isSyncEnabled else { return nil }
        if let bool = storedValue(forKey: key, as: Bool.self) {
            return bool
        }
        return storedValue(forKey: key, as: NSNumber.self)?.boolValue
    }

    func mirroredInt(forKey key: String) -> Int? {
        guard isSyncEnabled else { return nil }
        if let int = storedValue(forKey: key, as: Int.self) {
            return int
        }
        return storedValue(forKey: key, as: NSNumber.self)?.intValue
    }

    func mirroredDoubleMap(forKey key: String) -> [String: Double]? {
        guard isSyncEnabled else { return nil }
        if let typed = storedValue(forKey: key, as: [String: Double].self) {
            return typed
        }
        guard let raw = storedValue(forKey: key, as: NSDictionary.self) else { return nil }
        return Self.decodedDoubleMap(raw)
    }

    func mirroredData(forKey key: String) -> Data? {
        guard isSyncEnabled else { return nil }
        return storedValue(forKey: key, as: Data.self)
    }

    func mirror(_ value: some SyncedPlistValue, forKey key: String) {
        set(value, forKey: key)
    }

    func clearMirror(forKey key: String) {
        clearValue(forKey: key)
    }

    nonisolated static func decodedDoubleMap(_ raw: NSDictionary) -> [String: Double] {
        var result: [String: Double] = [:]
        for case let (key as String, number as NSNumber) in raw {
            result[key] = number.doubleValue
        }
        return result
    }

    func synchronize() -> Bool {
        guard !isTestIsolated, isSyncEnabled else { return false }
        return keyValueStore.synchronize()
    }

    func mirroredKeyCount() -> Int {
        guard !isTestIsolated, isSyncEnabled else { return 0 }
        return Self.syncedKeys.filter { keyValueStore.object(forKey: $0) != nil }.count
    }

    @discardableResult
    private func pullRemoteValues() -> Bool {
        guard !isTestIsolated, isSyncEnabled else { return false }
        var applied = false
        for key in Self.syncedKeys {
            if let remote = keyValueStore.object(forKey: key) {
                defaults.set(remote, forKey: key)
                applied = true
            }
        }
        // Outage or empty pull leaves the date untouched.
        if applied {
            onSyncSucceeded?()
        }
        return applied
    }

    @discardableResult
    private func backfillEmptyKeys() -> Bool {
        guard !isTestIsolated, isSyncEnabled else { return false }
        var didPush = false
        for key in Self.syncedKeys {
            // Only fill KVS slots that are empty; never overwrite remote state.
            guard keyValueStore.object(forKey: key) == nil else { continue }
            if let local = defaults.object(forKey: key) {
                keyValueStore.set(local, forKey: key)
                didPush = true
            }
        }
        guard didPush else { return false }
        // Failed push means outage; caller stamps only on success.
        return keyValueStore.synchronize()
    }
}
