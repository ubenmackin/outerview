// Persistence — Per-host text-zoom store with default cleanup.

import Foundation

@MainActor
final class SiteZoomStore {
    nonisolated static let storeKey = "siteZoom"
    nonisolated static let defaultZoom = 1.0
    nonisolated static let minimumZoom = 0.5
    nonisolated static let maximumZoom = 3.0

    private let defaults: UserDefaults
    private let syncedStore: SyncedSettingsStore

    init(defaults: UserDefaults = .standard, syncedStore: SyncedSettingsStore? = nil) {
        self.defaults = defaults
        self.syncedStore = syncedStore ?? SyncedSettingsStore(defaults: defaults)
    }

    static func clamp(_ zoom: Double) -> Double {
        let bounded = min(max(zoom, minimumZoom), maximumZoom)
        return (bounded * 10).rounded() / 10
    }

    func zoom(forHost host: String?) -> Double {
        guard let key = normalized(host), let stored = storedZooms()[key] else {
            return Self.defaultZoom
        }
        return stored
    }

    func setZoom(_ zoom: Double, forHost host: String?) {
        guard let key = normalized(host) else { return }
        var current = storedZooms()
        let clamped = Self.clamp(zoom)
        if clamped == Self.defaultZoom {
            current.removeValue(forKey: key)
        } else {
            current[key] = clamped
        }
        persist(current)
    }

    func clearAll() {
        persist([:])
    }

    private func normalized(_ host: String?) -> String? {
        guard let host, !host.isEmpty else { return nil }
        return host.lowercased()
    }

    private func persist(_ zooms: [String: Double]) {
        if zooms.isEmpty {
            defaults.removeObject(forKey: Self.storeKey)
            syncedStore.clearMirror(forKey: Self.storeKey)
        } else {
            defaults.set(zooms, forKey: Self.storeKey)
            syncedStore.mirror(zooms, forKey: Self.storeKey)
        }
    }

    private func storedZooms() -> [String: Double] {
        if let remote = syncedStore.mirroredDoubleMap(forKey: Self.storeKey) {
            return remote
        }
        guard let raw = defaults.object(forKey: Self.storeKey) as? NSDictionary else { return [:] }
        return SyncedSettingsStore.decodedDoubleMap(raw)
    }
}
