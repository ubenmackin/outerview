// Settings — Search engine plus privacy toggles plus clearance actions owner.

import Foundation
import Observation
import WebKit

@Observable
@MainActor
final class SettingsViewModel {
    nonisolated static let searchEngineDefaultsKey = "searchEngine"
    nonisolated static let requireBiometricsDefaultsKey = "requireBiometricsForPrivateTabs"
    nonisolated static let blockTrackersDefaultsKey = "blockTrackersAndAds"
    nonisolated static let appVersionLabel = "OuterView 0.1.0"
    nonisolated static let safariExportInstructions =
        "Export from Safari: Settings → Apps → Safari → Export → Bookmarks, then open the ZIP in Files and pick Bookmarks.html."
    nonisolated static let resetAllTextZoomsConfirmationText = "This resets text zoom for all sites."

    @ObservationIgnored
    private let defaults: UserDefaults

    var searchEngine: SearchEngine {
        didSet {
            defaults.set(searchEngine.rawValue, forKey: Self.searchEngineDefaultsKey)
        }
    }

    var requireBiometricsForPrivateTabs: Bool {
        didSet {
            defaults.set(requireBiometricsForPrivateTabs, forKey: Self.requireBiometricsDefaultsKey)
        }
    }

    var blockTrackersAndAds: Bool {
        didSet {
            defaults.set(blockTrackersAndAds, forKey: Self.blockTrackersDefaultsKey)
            // Persist only; the notification-to-root path owns live rule apply.
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.searchEngineDefaultsKey)
        let engine = stored.flatMap(SearchEngine.init(rawValue:)) ?? .google
        self.searchEngine = engine
        self.requireBiometricsForPrivateTabs = defaults.object(forKey: Self.requireBiometricsDefaultsKey) as? Bool ?? true
        self.blockTrackersAndAds = defaults.object(forKey: Self.blockTrackersDefaultsKey) as? Bool ?? true
    }

    func searchURL(for query: String) -> URL {
        searchEngine.searchURL(query)
    }

    func importBookmarks(_ data: Data, bookmarkStore: BookmarkStore) async -> ImportSummary {
        await BookmarkImporter().importFromData(data, bookmarkStore: bookmarkStore)
    }

    func clearHistory(historyStore: HistoryStore) throws {
        try historyStore.clear()
    }

    func clearWebsiteData(dataStore: WKWebsiteDataStore = .default()) async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await dataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
    }

    func clearHistoryAndWebsiteData(historyStore: HistoryStore, dataStore: WKWebsiteDataStore = .default()) async throws {
        try clearHistory(historyStore: historyStore)
        await clearWebsiteData(dataStore: dataStore)
    }

    func clearAllTabs(tabStore: TabStore) throws {
        let (tabs, _) = tabStore.loadSession()
        for tab in tabs {
            try tabStore.deleteTab(id: tab.id)
        }
        let fresh = TabRecord(isPrivate: false)
        try tabStore.saveSession(tabs: [fresh], selected: fresh.id)
    }

    func resetAllTextZooms(siteZoomStore: SiteZoomStore) {
        siteZoomStore.clearAll()
    }

    static func formattedSummary(_ summary: ImportSummary) -> String {
        "Added \(summary.added), skipped \(summary.skippedDuplicates) duplicates, "
            + "\(summary.skippedInvalid) invalid, truncated \(summary.truncated)."
    }
}
