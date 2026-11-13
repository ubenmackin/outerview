// Persistence — Per-host website settings store with default cleanup.
import Foundation
import os

/// Per-host settings for desktop website mode and automatic reader mode.
public struct WebsiteSettings: Codable, Equatable, Sendable {
    public var requestDesktopWebsite: Bool
    public var useReaderAutomatically: Bool

    public init(requestDesktopWebsite: Bool = false, useReaderAutomatically: Bool = false) {
        self.requestDesktopWebsite = requestDesktopWebsite
        self.useReaderAutomatically = useReaderAutomatically
    }

    public var isDefault: Bool {
        !requestDesktopWebsite && !useReaderAutomatically
    }
}

/// Stores per-host website settings in UserDefaults.
@MainActor
public final class WebsiteSettingsStore {
    public nonisolated static let storeKey = "websiteSettings"
    nonisolated static let maxEphemeralHosts = 128

    private let defaults: UserDefaults
    private let syncedStore: SyncedSettingsStore
    private let logger = Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
    private var ephemeral: [String: WebsiteSettings] = [:]
    private var ephemeralOrder: [String] = []

    public init(defaults: UserDefaults = .standard, syncedStore: SyncedSettingsStore? = nil) {
        self.defaults = defaults
        self.syncedStore = syncedStore ?? SyncedSettingsStore(defaults: defaults)
    }

    public func settings(forHost host: String?, isPrivate: Bool) -> WebsiteSettings {
        guard let key = normalized(host) else {
            return WebsiteSettings()
        }
        if isPrivate {
            return ephemeral[key] ?? WebsiteSettings()
        }
        guard let stored = storedSettings()[key] else {
            return WebsiteSettings()
        }
        return stored
    }

    public func setRequestDesktopWebsite(_ enabled: Bool, forHost host: String?, isPrivate: Bool) {
        guard let key = normalized(host) else { return }
        if isPrivate {
            var item = ephemeral[key] ?? WebsiteSettings()
            item.requestDesktopWebsite = enabled
            saveEphemeral(item, for: key)
            return
        }
        var current = storedSettings()
        var item = current[key] ?? WebsiteSettings()
        item.requestDesktopWebsite = enabled
        saveItem(item, for: key, in: &current)
    }

    public func setUseReaderAutomatically(_ enabled: Bool, forHost host: String?, isPrivate: Bool) {
        guard let key = normalized(host) else { return }
        if isPrivate {
            var item = ephemeral[key] ?? WebsiteSettings()
            item.useReaderAutomatically = enabled
            saveEphemeral(item, for: key)
            return
        }
        var current = storedSettings()
        var item = current[key] ?? WebsiteSettings()
        item.useReaderAutomatically = enabled
        saveItem(item, for: key, in: &current)
    }

    public func updateSettings(_ settings: WebsiteSettings, forHost host: String?, isPrivate: Bool) {
        guard let key = normalized(host) else { return }
        if isPrivate {
            saveEphemeral(settings, for: key)
            return
        }
        var current = storedSettings()
        saveItem(settings, for: key, in: &current)
    }

    public func clearAll() {
        ephemeral.removeAll()
        ephemeralOrder.removeAll()
        defaults.removeObject(forKey: Self.storeKey)
        syncedStore.clearMirror(forKey: Self.storeKey)
    }

    private func normalized(_ host: String?) -> String? {
        guard let host, !host.isEmpty else { return nil }
        return host.lowercased()
    }

    private func saveItem(_ item: WebsiteSettings, for key: String, in current: inout [String: WebsiteSettings]) {
        if item.isDefault {
            current.removeValue(forKey: key)
        } else {
            current[key] = item
        }

        if current.isEmpty {
            defaults.removeObject(forKey: Self.storeKey)
            syncedStore.clearMirror(forKey: Self.storeKey)
        } else {
            do {
                let data = try JSONEncoder().encode(current)
                defaults.set(data, forKey: Self.storeKey)
                syncedStore.mirror(data, forKey: Self.storeKey)
            } catch {
                logger.error("Failed to encode website settings: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func saveEphemeral(_ item: WebsiteSettings, for key: String) {
        if item.isDefault {
            ephemeral.removeValue(forKey: key)
            ephemeralOrder.removeAll(where: { $0 == key })
            return
        }
        if ephemeral[key] == nil {
            ephemeralOrder.append(key)
        }
        ephemeral[key] = item
        while ephemeral.count > Self.maxEphemeralHosts, !ephemeralOrder.isEmpty {
            ephemeral.removeValue(forKey: ephemeralOrder.removeFirst())
        }
    }

    private func storedSettings() -> [String: WebsiteSettings] {
        if let mirrored = syncedStore.mirroredData(forKey: Self.storeKey) {
            do {
                return try JSONDecoder().decode([String: WebsiteSettings].self, from: mirrored)
            } catch {
                logger.warning("Failed to decode mirrored website settings; falling back to local defaults: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard let data = defaults.data(forKey: Self.storeKey) else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: WebsiteSettings].self, from: data)
        } catch {
            logger.error("Failed to decode website settings: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }
}
