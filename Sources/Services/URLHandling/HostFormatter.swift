//
//  HostFormatter.swift
//  OuterView
//

import Foundation

/// Single owner of host extraction for display and ranking.
/// Empty when the URL has no host so callers apply their own fallback.
enum HostFormatter: Sendable {
    nonisolated static func host(of url: URL?) -> String {
        guard let host = url?.host, !host.isEmpty else { return "" }
        return host
    }

    /// Display title for a page: trimmed title when present, otherwise host,
    /// otherwise the full URL string.
    nonisolated static func displayTitle(url: URL, title: String?) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty else { return trimmed }
        let host = host(of: url)
        return host.isEmpty ? url.absoluteString : host
    }

    /// Normalized host for dedupe and hue: lowercased with a single
    /// leading www. stripped. Other subdomains stay distinct.
    nonisolated static func normalizedHost(_ host: String?) -> String {
        guard let host, !host.isEmpty else { return "" }
        var normalized = host.lowercased()
        if normalized.hasPrefix("www.") {
            normalized = String(normalized.dropFirst(4))
        }
        return normalized
    }

    /// Stable hue fraction in [0, 1) for a host, independent of the
    /// per-process hash seed so the same host renders the same hue
    /// on every launch.
    nonisolated static func stableHue(forHost host: String?) -> Double {
        let normalized = normalizedHost(host)
        guard !normalized.isEmpty else { return 0 }
        var hash = 0
        for scalar in normalized.unicodeScalars {
            hash = (hash &* 31) &+ Int(scalar.value)
        }
        return Double(UInt(bitPattern: hash) % 360) / 360.0
    }
}
