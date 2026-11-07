// Settings — Search engine plus privacy toggles plus clearance tests.

@testable import OuterView
import XCTest

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let name = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }

    private func makeDatabase() throws -> OuterViewDatabase {
        try OuterViewDatabase(inMemory: true)
    }

    func testDefaultsToGoogleWhenNothingStored() throws {
        let defaults = try makeDefaults()
        XCTAssertEqual(SettingsViewModel(defaults: defaults).searchEngine, .google)
    }

    func testDefaultsToGoogleOnUnknownRawValue() throws {
        let defaults = try makeDefaults()
        defaults.set("unknown-engine", forKey: SettingsViewModel.searchEngineDefaultsKey)
        XCTAssertEqual(SettingsViewModel(defaults: defaults).searchEngine, .google)
    }

    func testReadsPersistedEngineAcrossAllCases() throws {
        for engine in SearchEngine.allCases {
            let defaults = try makeDefaults()
            defaults.set(engine.rawValue, forKey: SettingsViewModel.searchEngineDefaultsKey)
            XCTAssertEqual(SettingsViewModel(defaults: defaults).searchEngine, engine)
        }
    }

    func testChangingEnginePersistsRawValue() throws {
        let defaults = try makeDefaults()
        let viewModel = SettingsViewModel(defaults: defaults)
        viewModel.searchEngine = .brave
        XCTAssertEqual(defaults.string(forKey: SettingsViewModel.searchEngineDefaultsKey), "brave")
        XCTAssertEqual(SettingsViewModel(defaults: defaults).searchEngine, .brave)
    }

    func testSearchURLDelegatesToEngine() throws {
        let defaults = try makeDefaults()
        let viewModel = SettingsViewModel(defaults: defaults)
        viewModel.searchEngine = .bing
        XCTAssertEqual(
            viewModel.searchURL(for: "hello world"),
            SearchEngine.bing.searchURL("hello world")
        )
    }

    func testFormattedSummary() {
        let summary = ImportSummary(added: 5, skippedDuplicates: 1, skippedInvalid: 2, truncated: 0)
        XCTAssertEqual(
            SettingsViewModel.formattedSummary(summary),
            "Added 5, skipped 1 duplicates, 2 invalid, truncated 0."
        )
    }

    func testClearHistoryRemovesAllRows() throws {
        let database = try makeDatabase()
        let historyStore = HistoryStore(database: database)
        let urlA = try XCTUnwrap(URL(string: "https://example.com/a"))
        let urlB = try XCTUnwrap(URL(string: "https://example.com/b"))
        try historyStore.record(visit: PageVisit(url: urlA, title: "A"))
        try historyStore.record(visit: PageVisit(url: urlB, title: "B"))
        let defaults = try makeDefaults()
        let viewModel = SettingsViewModel(defaults: defaults)

        try viewModel.clearHistory(historyStore: historyStore)

        XCTAssertTrue(historyStore.fetchAll().isEmpty)
    }

    func testClearAllTabsLeavesSingleFreshTab() throws {
        let database = try makeDatabase()
        let tabStore = TabStore(database: database)
        let first = TabRecord(
            url: URL(string: "https://example.com/a"),
            title: "A",
            isPrivate: false
        )
        let second = TabRecord(
            url: URL(string: "https://example.com/b"),
            title: "B",
            isPrivate: false
        )
        try tabStore.saveSession(tabs: [first, second], selected: first.id)
        let defaults = try makeDefaults()
        let viewModel = SettingsViewModel(defaults: defaults)

        try viewModel.clearAllTabs(tabStore: tabStore)

        let (tabs, selected) = tabStore.loadSession()
        XCTAssertEqual(tabs.count, 1)
        let fresh = try XCTUnwrap(tabs.first)
        XCTAssertFalse(fresh.isPrivate)
        XCTAssertEqual(selected, fresh.id)
    }

    func testBiometricsAndContentBlockingDefaultsAndPersistence() throws {
        let defaults = try makeDefaults()
        let vmDefault = SettingsViewModel(defaults: defaults)
        XCTAssertTrue(vmDefault.requireBiometricsForPrivateTabs)
        XCTAssertTrue(vmDefault.blockTrackersAndAds)

        vmDefault.requireBiometricsForPrivateTabs = false
        vmDefault.blockTrackersAndAds = false
        XCTAssertFalse(defaults.bool(forKey: SettingsViewModel.requireBiometricsDefaultsKey))
        XCTAssertFalse(defaults.bool(forKey: SettingsViewModel.blockTrackersDefaultsKey))

        let vmReloaded = SettingsViewModel(defaults: defaults)
        XCTAssertFalse(vmReloaded.requireBiometricsForPrivateTabs)
        XCTAssertFalse(vmReloaded.blockTrackersAndAds)
    }
}
