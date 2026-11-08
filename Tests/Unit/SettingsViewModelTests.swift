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

    func testPortraitTabBarPositionDefaultsAndPersistence() throws {
        let defaults = try makeDefaults()
        let vm = SettingsViewModel(defaults: defaults)
        XCTAssertEqual(vm.portraitTabBarPosition, .right)

        final class PositionNotified: @unchecked Sendable {
            private let lock = NSLock()
            private var fired = false

            func mark() {
                lock.lock()
                fired = true
                lock.unlock()
            }

            var value: Bool {
                lock.lock()
                defer { lock.unlock() }
                return fired
            }
        }
        let notified = PositionNotified()
        let observer = NotificationCenter.default.addObserver(
            forName: .portraitTabBarPositionChanged,
            object: nil,
            queue: nil
        ) { notif in
            if notif.userInfo?["position"] as? String == "left" {
                notified.mark()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        vm.portraitTabBarPosition = .left
        XCTAssertTrue(notified.value)
        XCTAssertEqual(defaults.string(forKey: SettingsViewModel.portraitTabBarPositionDefaultsKey), "left")

        let reloaded = SettingsViewModel(defaults: defaults)
        XCTAssertEqual(reloaded.portraitTabBarPosition, .left)
    }

    func testIsDuoOrPadDeviceClassification() {
        // Plain regular without Duo hardware fail-closes.
        XCTAssertFalse(SettingsViewModel.isDuoOrPadDevice(horizontalSizeClass: .regular))
        XCTAssertFalse(SettingsViewModel.isDuoOrPadDevice(
            bounds: CGRect(x: 0, y: 0, width: 932, height: 430),
            deviceName: "iPhone 17 Pro Max",
            userInterfaceIdiom: .phone,
            horizontalSizeClass: .regular
        ))

        XCTAssertTrue(SettingsViewModel.isDuoOrPadDevice(userInterfaceIdiom: .pad))

        // Phone with Duo name -> true
        XCTAssertTrue(SettingsViewModel.isDuoOrPadDevice(
            deviceName: "iPhone Duo - Outer Display",
            userInterfaceIdiom: .phone
        ))

        // Duo outer geometry -> true
        XCTAssertTrue(SettingsViewModel.isDuoOrPadDevice(
            bounds: CGRect(x: 0, y: 0, width: 466, height: 678),
            userInterfaceIdiom: .phone
        ))

        // Duo inner portrait geometry with explicit regular size class -> true.
        XCTAssertTrue(SettingsViewModel.isDuoOrPadDevice(
            bounds: CGRect(x: 0, y: 0, width: 669, height: 951),
            userInterfaceIdiom: .phone,
            horizontalSizeClass: .regular
        ))

        // Standard phone -> false
        XCTAssertFalse(SettingsViewModel.isDuoOrPadDevice(
            bounds: CGRect(x: 0, y: 0, width: 402, height: 874),
            deviceName: "iPhone 17 Pro",
            userInterfaceIdiom: .phone
        ))
    }
}
