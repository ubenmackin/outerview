// Persistence — iCloud key-value mirror for lightweight settings.

import Foundation

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
    /// Token lifetime is lock-guarded; teardown needs no actor hop.
    private var observation: KVSObservation?
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

    func startSync() {
        if observation == nil {
            let box = KVSObservation(center: notificationCenter, store: self)
            observation = box
            box.begin()
        }
        let applied = pullRemoteValues()
        let pushed = backfillEmptyKeys()
        // Fresh reachable stores stamp once via monitor; outage stamps nothing.
        if pushed, !applied {
            onSyncSucceeded?()
        }
    }

    func set(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        // Toggle itself stays local-only; only synced keys mirror to KVS.
        guard !isTestIsolated, isSyncEnabled, Self.syncedKeys.contains(key) else { return }
        if let value {
            keyValueStore.set(value, forKey: key)
        } else {
            keyValueStore.removeObject(forKey: key)
        }
    }

    func value(forKey key: String) -> Any? {
        guard !isTestIsolated, isSyncEnabled,
              Self.syncedKeys.contains(key)
        else {
            return defaults.object(forKey: key)
        }
        // KVS miss fails closed to the local default.
        if let remote = keyValueStore.object(forKey: key) {
            return remote
        }
        return defaults.object(forKey: key)
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
        return value(forKey: key) as? String
    }

    func mirroredBool(forKey key: String) -> Bool? {
        guard isSyncEnabled else { return nil }
        let stored = value(forKey: key)
        if let bool = stored as? Bool {
            return bool
        }
        return (stored as? NSNumber)?.boolValue
    }

    func mirroredInt(forKey key: String) -> Int? {
        guard isSyncEnabled else { return nil }
        let stored = value(forKey: key)
        if let int = stored as? Int {
            return int
        }
        return (stored as? NSNumber)?.intValue
    }

    func mirroredDoubleMap(forKey key: String) -> [String: Double]? {
        guard isSyncEnabled else { return nil }
        if let typed = value(forKey: key) as? [String: Double] {
            return typed
        }
        guard let raw = value(forKey: key) as? [String: Any] else { return nil }
        return Self.decodedDoubleMap(raw)
    }

    func mirroredData(forKey key: String) -> Data? {
        guard isSyncEnabled else { return nil }
        return value(forKey: key) as? Data
    }

    func mirror(_ value: Any?, forKey key: String) {
        set(value, forKey: key)
    }

    nonisolated static func decodedDoubleMap(_ raw: [String: Any]) -> [String: Double] {
        var result: [String: Double] = [:]
        for (key, stored) in raw {
            if let double = stored as? Double {
                result[key] = double
            } else if let number = stored as? NSNumber {
                result[key] = number.doubleValue
            }
        }
        return result
    }

    func synchronize() -> Bool {
        guard !isTestIsolated, isSyncEnabled else { return false }
        return keyValueStore.synchronize()
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

    /// The block pulls first so stamping follows
    /// the pull via onSyncSucceeded. The lock guards the token.
    private final class KVSObservation: @unchecked Sendable {
        private let center: NotificationCenter
        private weak var store: SyncedSettingsStore?
        private let lock = NSLock()
        private var token: NSObjectProtocol?

        @MainActor init(center: NotificationCenter, store: SyncedSettingsStore) {
            self.center = center
            self.store = store
        }

        @MainActor func begin() {
            lock.lock()
            defer { lock.unlock() }
            guard token == nil else { return }
            token = center.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    _ = self?.store?.pullRemoteValues()
                }
            }
        }

        deinit {
            lock.lock()
            let existing = token
            token = nil
            lock.unlock()
            if let existing {
                center.removeObserver(existing)
            }
        }
    }
}
