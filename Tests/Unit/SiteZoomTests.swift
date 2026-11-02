//
//  SiteZoomTests.swift
//  OuterView
//

@testable import OuterView
import WebKit
import XCTest

@MainActor
final class SiteZoomTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let name = "SiteZoomTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }

    func testClampMatrix() {
        XCTAssertEqual(SiteZoomStore.clamp(0.4), 0.5, accuracy: 0.001)
        XCTAssertEqual(SiteZoomStore.clamp(0.57), 0.6, accuracy: 0.001)
        XCTAssertEqual(SiteZoomStore.clamp(1.0), 1.0, accuracy: 0.001)
        XCTAssertEqual(SiteZoomStore.clamp(3.1), 3.0, accuracy: 0.001)
        XCTAssertEqual(SiteZoomStore.clamp(0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(SiteZoomStore.clamp(3.0), 3.0, accuracy: 0.001)
        XCTAssertEqual(SiteZoomStore.clamp(1.54), 1.5, accuracy: 0.001)
        XCTAssertEqual(SiteZoomStore.clamp(2.06), 2.1, accuracy: 0.001)
    }

    func testDefaultZoomIsOne() throws {
        let store = try SiteZoomStore(defaults: makeDefaults())
        XCTAssertEqual(store.zoom(forHost: "example.com"), 1.0, accuracy: 0.001)
        XCTAssertEqual(store.zoom(forHost: nil), 1.0, accuracy: 0.001)
        XCTAssertEqual(store.zoom(forHost: ""), 1.0, accuracy: 0.001)
    }

    func testSetZoomSnapsToTenth() throws {
        let store = try SiteZoomStore(defaults: makeDefaults())
        store.setZoom(0.57, forHost: "example.com")
        XCTAssertEqual(store.zoom(forHost: "example.com"), 0.6, accuracy: 0.001)
        store.setZoom(2.34, forHost: "example.com")
        XCTAssertEqual(store.zoom(forHost: "example.com"), 2.3, accuracy: 0.001)
    }

    func testSetZoomClampsToBounds() throws {
        let store = try SiteZoomStore(defaults: makeDefaults())
        store.setZoom(0.4, forHost: "example.com")
        XCTAssertEqual(store.zoom(forHost: "example.com"), 0.5, accuracy: 0.001)
        store.setZoom(3.1, forHost: "example.com")
        XCTAssertEqual(store.zoom(forHost: "example.com"), 3.0, accuracy: 0.001)
    }

    func testResetToOneRemovesEntry() throws {
        let defaults = try makeDefaults()
        let store = SiteZoomStore(defaults: defaults)
        store.setZoom(1.5, forHost: "example.com")
        XCTAssertEqual(store.zoom(forHost: "example.com"), 1.5, accuracy: 0.001)
        store.setZoom(1.0, forHost: "example.com")
        XCTAssertEqual(store.zoom(forHost: "example.com"), 1.0, accuracy: 0.001)
        let raw = defaults.dictionary(forKey: SiteZoomStore.storeKey)
        XCTAssertNil(raw?["example.com"])
    }

    func testPerHostIsolation() throws {
        let store = try SiteZoomStore(defaults: makeDefaults())
        store.setZoom(1.5, forHost: "a.example.com")
        store.setZoom(2.0, forHost: "b.example.com")
        XCTAssertEqual(store.zoom(forHost: "a.example.com"), 1.5, accuracy: 0.001)
        XCTAssertEqual(store.zoom(forHost: "b.example.com"), 2.0, accuracy: 0.001)
        XCTAssertEqual(store.zoom(forHost: "c.example.com"), 1.0, accuracy: 0.001)
        store.setZoom(1.0, forHost: "a.example.com")
        XCTAssertEqual(store.zoom(forHost: "a.example.com"), 1.0, accuracy: 0.001)
        XCTAssertEqual(store.zoom(forHost: "b.example.com"), 2.0, accuracy: 0.001)
    }

    func testClearAll() throws {
        let store = try SiteZoomStore(defaults: makeDefaults())
        store.setZoom(1.5, forHost: "a.example.com")
        store.setZoom(2.0, forHost: "b.example.com")
        store.clearAll()
        XCTAssertEqual(store.zoom(forHost: "a.example.com"), 1.0, accuracy: 0.001)
        XCTAssertEqual(store.zoom(forHost: "b.example.com"), 1.0, accuracy: 0.001)
    }

    func testZoomPersistsAcrossInstances() throws {
        let defaults = try makeDefaults()
        let first = SiteZoomStore(defaults: defaults)
        first.setZoom(1.7, forHost: "example.com")
        let second = SiteZoomStore(defaults: defaults)
        XCTAssertEqual(second.zoom(forHost: "example.com"), 1.7, accuracy: 0.001)
    }

    func testViewModelResetPassthrough() throws {
        let defaults = try makeDefaults()
        let store = SiteZoomStore(defaults: defaults)
        store.setZoom(1.5, forHost: "a.example.com")
        store.setZoom(2.0, forHost: "b.example.com")
        let viewModel = try SettingsViewModel(defaults: makeDefaults())
        viewModel.resetAllTextZooms(siteZoomStore: store)
        XCTAssertEqual(store.zoom(forHost: "a.example.com"), 1.0, accuracy: 0.001)
        XCTAssertEqual(store.zoom(forHost: "b.example.com"), 1.0, accuracy: 0.001)
    }

    func testViewModelConfirmationText() {
        XCTAssertFalse(SettingsViewModel.resetAllTextZoomsConfirmationText.isEmpty)
    }

    func testPageWithoutStoreReadsDefault() {
        let page = WebPageController(configuration: WKWebViewConfiguration())
        XCTAssertNil(page.siteZoomStore)
        XCTAssertEqual(page.currentTextZoom(), 1.0, accuracy: 0.001)
    }

    func testSetTextZoomAppliesWithoutTouchingReader() throws {
        let page = WebPageController(configuration: WKWebViewConfiguration())
        page.siteZoomStore = try SiteZoomStore(defaults: makeDefaults())
        XCTAssertFalse(page.isReaderActive)
        page.setTextZoom(1.5)
        XCTAssertEqual(Double(page.webView.pageZoom), 1.5, accuracy: 0.01)
        XCTAssertFalse(page.isReaderActive)
        page.setTextZoom(5.0)
        XCTAssertEqual(Double(page.webView.pageZoom), 3.0, accuracy: 0.01)
        XCTAssertFalse(page.isReaderActive)
    }
}
