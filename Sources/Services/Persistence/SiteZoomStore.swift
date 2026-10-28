//
//  SiteZoomStore.swift
//  OuterView
//

import Foundation

@MainActor
final class SiteZoomStore {
    static let storeKey = "siteZoom"
    static let defaultZoom = 1.0
    static let minimumZoom = 0.5
    static let maximumZoom = 3.0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        if current.isEmpty {
            defaults.removeObject(forKey: Self.storeKey)
        } else {
            defaults.set(current, forKey: Self.storeKey)
        }
    }

    func clearAll() {
        defaults.removeObject(forKey: Self.storeKey)
    }

    private func normalized(_ host: String?) -> String? {
        guard let host, !host.isEmpty else { return nil }
        return host.lowercased()
    }

    private func storedZooms() -> [String: Double] {
        guard let raw = defaults.dictionary(forKey: Self.storeKey) else { return [:] }
        var result: [String: Double] = [:]
        for (key, value) in raw {
            if let double = value as? Double {
                result[key] = double
            } else if let number = value as? NSNumber {
                result[key] = number.doubleValue
            }
        }
        return result
    }
}
