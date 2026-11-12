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
    public static let storeKey = "websiteSettings"

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func settings(forHost host: String?) -> WebsiteSettings {
        guard let key = normalized(host), let stored = storedSettings()[key] else {
            return WebsiteSettings()
        }
        return stored
    }

    public func setRequestDesktopWebsite(_ enabled: Bool, forHost host: String?) {
        guard let key = normalized(host) else { return }
        var current = storedSettings()
        var item = current[key] ?? WebsiteSettings()
        item.requestDesktopWebsite = enabled
        saveItem(item, for: key, in: &current)
    }

    public func setUseReaderAutomatically(_ enabled: Bool, forHost host: String?) {
        guard let key = normalized(host) else { return }
        var current = storedSettings()
        var item = current[key] ?? WebsiteSettings()
        item.useReaderAutomatically = enabled
        saveItem(item, for: key, in: &current)
    }

    public func updateSettings(_ settings: WebsiteSettings, forHost host: String?) {
        guard let key = normalized(host) else { return }
        var current = storedSettings()
        saveItem(settings, for: key, in: &current)
    }

    public func clearAll() {
        defaults.removeObject(forKey: Self.storeKey)
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
        } else {
            do {
                let data = try JSONEncoder().encode(current)
                defaults.set(data, forKey: Self.storeKey)
            } catch {
                logger.error("Failed to encode website settings: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func storedSettings() -> [String: WebsiteSettings] {
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
