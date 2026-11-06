// Settings — Search engine plus data-clearance actions owner.

import Foundation
import Observation
import WebKit

@Observable
@MainActor
final class SettingsViewModel {
    static let searchEngineDefaultsKey = "searchEngine"
    static let appVersionLabel = "OuterView 0.1.0"
    static let safariExportInstructions =
        "Export from Safari: Settings → Apps → Safari → Export → Bookmarks, then open the ZIP in Files and pick Bookmarks.html."
    static let resetAllTextZoomsConfirmationText = "This resets text zoom for all sites."

    @ObservationIgnored
    private let defaults: UserDefaults

    var searchEngine: SearchEngine {
        didSet {
            defaults.set(searchEngine.rawValue, forKey: Self.searchEngineDefaultsKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.searchEngineDefaultsKey)
        let engine = stored.flatMap(SearchEngine.init(rawValue:)) ?? .google
        self.searchEngine = engine
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
