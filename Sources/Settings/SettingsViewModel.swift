// Settings — Search engine, privacy, and portrait tab bar position owner.

import Foundation
import Observation
import UIKit
import WebKit

enum PortraitTabBarPosition: String, CaseIterable, Identifiable, Sendable {
    case right
    case left

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .right: "Right Side (Default)"
        case .left: "Left Side"
        }
    }
}

extension Notification.Name {
    static let portraitTabBarPositionChanged = Notification.Name("outerViewPortraitTabBarPositionChanged")
}

@Observable
@MainActor
final class SettingsViewModel {
    nonisolated static let searchEngineDefaultsKey = "searchEngine"
    nonisolated static let requireBiometricsDefaultsKey = "requireBiometricsForPrivateTabs"
    nonisolated static let blockTrackersDefaultsKey = "blockTrackersAndAds"
    nonisolated static let portraitTabBarPositionDefaultsKey = "portraitTabBarPosition"
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

    var portraitTabBarPosition: PortraitTabBarPosition {
        didSet {
            guard oldValue != portraitTabBarPosition else { return }
            defaults.set(portraitTabBarPosition.rawValue, forKey: Self.portraitTabBarPositionDefaultsKey)
            NotificationCenter.default.post(
                name: .portraitTabBarPositionChanged,
                object: nil,
                userInfo: ["position": portraitTabBarPosition.rawValue]
            )
        }
    }

    var isDuoOrPad: Bool

    func refreshDuoOrPad() {
        let fresh = Self.currentIsDuoOrPad()
        if fresh != isDuoOrPad {
            isDuoOrPad = fresh
        }
    }

    private static func currentIsDuoOrPad() -> Bool {
        // Unit tests have no key window; resolve without scene lookup.
        if AppEnvironment.isTestHost {
            return isDuoOrPadDevice(userInterfaceIdiom: UIDevice.current.userInterfaceIdiom)
        }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
        return isDuoOrPadDevice(
            safeAreaInsets: window?.safeAreaInsets ?? .zero,
            bounds: window?.bounds ?? .zero,
            userInterfaceIdiom: UIDevice.current.userInterfaceIdiom,
            horizontalSizeClass: window?.traitCollection.horizontalSizeClass ?? .unspecified
        )
    }

    /// Hardware gate for the Tabs picker. Fail-closed: iPad idiom, Duo outer
    /// geometry/name, Duo launch args, or Duo inner canvas only.
    nonisolated static func isDuoOrPadDevice(
        safeAreaInsets: UIEdgeInsets = .zero,
        bounds: CGRect = .zero,
        deviceName: String? = nil,
        userInterfaceIdiom: UIUserInterfaceIdiom = .unspecified,
        horizontalSizeClass _: UIUserInterfaceSizeClass = .unspecified
    ) -> Bool {
        if userInterfaceIdiom == .pad {
            return true
        }
        let args = CommandLine.arguments
        if args.contains("-OuterViewNonDuoPhone") {
            return false
        }
        if args.contains("-OuterViewInnerLandscape")
            || args.contains("-OuterViewInnerPortrait")
            || args.contains("-OuterViewInnerDisplay")
            || args.contains("-OuterViewDuoOuter")
        {
            return true
        }
        if BrowserRootViewController.isDuoOuterDisplay(
            safeAreaInsets: safeAreaInsets,
            bounds: bounds,
            deviceName: deviceName
        ) {
            return true
        }
        // Duo inner canvas matches the documented inner-display geometry;
        // a generic size floor would misclassify standard large iPhones.
        let isInnerPortrait = abs(bounds.width - 669) < 1 && abs(bounds.height - 951) < 1
        let isInnerLandscape = abs(bounds.width - 951) < 1 && abs(bounds.height - 669) < 1
        if isInnerPortrait || isInnerLandscape {
            return true
        }
        return false
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.searchEngineDefaultsKey)
        let engine = stored.flatMap(SearchEngine.init(rawValue:)) ?? .google
        self.searchEngine = engine
        self.requireBiometricsForPrivateTabs = defaults.object(forKey: Self.requireBiometricsDefaultsKey) as? Bool ?? true
        self.blockTrackersAndAds = defaults.object(forKey: Self.blockTrackersDefaultsKey) as? Bool ?? true
        let storedPosition = defaults.string(forKey: Self.portraitTabBarPositionDefaultsKey)
        self.portraitTabBarPosition = storedPosition.flatMap(PortraitTabBarPosition.init(rawValue:)) ?? .right
        self.isDuoOrPad = Self.currentIsDuoOrPad()
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
