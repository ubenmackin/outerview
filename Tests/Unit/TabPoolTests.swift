//
//  TabPoolTests.swift
//  OuterView
//

@testable import OuterView
import WebKit
import XCTest

@MainActor
final class TabPoolTests: XCTestCase {
    func testCreateKeepsInsertionOrder() {
        let pool = TabPool()
        let firstID = UUID()
        let secondID = UUID()

        pool.create(id: firstID, isPrivate: false)
        pool.create(id: secondID, isPrivate: false)

        XCTAssertEqual(pool.pages.map(\.id), [firstID, secondID])
        XCTAssertNotNil(pool.pages.first?.page)
        XCTAssertNotNil(pool.pages[1].page)
    }

    func testDeleteRemovesEntry() {
        let pool = TabPool()
        let id = UUID()
        pool.create(id: id, isPrivate: false)

        pool.delete(id: id)

        XCTAssertTrue(pool.pages.isEmpty)
        XCTAssertNil(pool.page(for: id))
    }

    func testEvictionTargetsLeastRecentlyActivePage() {
        let pool = TabPool()
        let ids = (0 ..< TabPool.livePageLimit).map { _ in UUID() }
        for id in ids {
            pool.create(id: id, isPrivate: false)
        }
        _ = pool.page(for: ids[TabPool.livePageLimit - 1])

        pool.create(id: UUID(), isPrivate: false)

        XCTAssertEqual(pool.pages.count, TabPool.livePageLimit + 1)
        XCTAssertNil(pool.pages.first?.page)
        XCTAssertNotNil(pool.pages[TabPool.livePageLimit - 1].page)
        XCTAssertNotNil(pool.pages[TabPool.livePageLimit].page)
    }

    func testEvictionFollowsActivationNotCreationOrder() {
        let pool = TabPool()
        let ids = (0 ..< TabPool.livePageLimit).map { _ in UUID() }
        for id in ids {
            pool.create(id: id, isPrivate: false)
        }
        // Activate the oldest tab after all others were merely created, so it
        // is the most recently active despite being first.
        guard let oldestID = ids.first else {
            XCTFail("ids is empty")
            return
        }
        _ = pool.page(for: oldestID)

        pool.create(id: UUID(), isPrivate: false)

        XCTAssertNotNil(pool.pages.first?.page)
        XCTAssertNil(pool.pages[1].page)
    }

    func testEvictionOrderFollowsRecency() {
        let pool = TabPool()
        let ids = (0 ..< TabPool.livePageLimit).map { _ in UUID() }
        for id in ids {
            pool.create(id: id, isPrivate: false)
        }
        _ = pool.page(for: ids[5])

        pool.create(id: UUID(), isPrivate: false)
        pool.create(id: UUID(), isPrivate: false)

        XCTAssertNil(pool.pages.first?.page)
        XCTAssertNil(pool.pages[1].page)
        XCTAssertNotNil(pool.pages[2].page)
        XCTAssertNotNil(pool.pages[5].page)
    }

    func testEvictedPageIsRecreatedOnActivation() {
        let pool = TabPool()
        let ids = (0 ..< TabPool.livePageLimit).map { _ in UUID() }
        for id in ids {
            pool.create(id: id, isPrivate: false)
        }
        pool.create(id: UUID(), isPrivate: false)
        XCTAssertNil(pool.pages.first?.page)

        guard let evictedID = ids.first else {
            XCTFail("ids is empty")
            return
        }
        let recreated = pool.page(for: evictedID)

        XCTAssertNotNil(recreated)
        XCTAssertNotNil(pool.pages.first?.page)
        // Recreating fills the cap again, so the next least recently active
        // page is evicted instead.
        XCTAssertNil(pool.pages[1].page)
    }

    func testLivePageCapHoldsAfterChurn() {
        let pool = TabPool()
        let ids = (0 ..< (TabPool.livePageLimit + 10)).map { _ in UUID() }
        for id in ids {
            pool.create(id: id, isPrivate: false)
        }

        XCTAssertEqual(pool.pages.filter { $0.page != nil }.count, TabPool.livePageLimit)
        XCTAssertEqual(pool.pages.count, TabPool.livePageLimit + 10)
    }

    func testRecreatingAnExistingTabKeepsOrderAndPage() {
        let pool = TabPool()
        let firstID = UUID()
        let secondID = UUID()
        pool.create(id: firstID, isPrivate: false)
        pool.create(id: secondID, isPrivate: false)
        let existingPage = pool.page(for: firstID)

        pool.create(id: firstID, isPrivate: false)

        XCTAssertEqual(pool.pages.count, 2)
        XCTAssertEqual(pool.pages.first?.id, firstID)
        XCTAssertIdentical(pool.pages.first?.page, existingPage)
    }

    func testPrivateConfigurationUsesNonPersistentStore() {
        let configuration = TabPool.makeConfiguration(isPrivate: true)
        let second = TabPool.makeConfiguration(isPrivate: true)

        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertNotIdentical(configuration.websiteDataStore, WKWebsiteDataStore.default())
        XCTAssertIdentical(configuration.websiteDataStore, second.websiteDataStore)
    }

    func testNormalConfigurationUsesDefaultStore() {
        let configuration = TabPool.makeConfiguration(isPrivate: false)

        XCTAssertIdentical(configuration.websiteDataStore, WKWebsiteDataStore.default())
    }

    func testPoolSharesOneConfigurationPerMode() {
        let pool = TabPool()

        XCTAssertIdentical(pool.configuration(isPrivate: true), pool.configuration(isPrivate: true))
        XCTAssertIdentical(pool.configuration(isPrivate: false), pool.configuration(isPrivate: false))
        XCTAssertNotIdentical(pool.configuration(isPrivate: true), pool.configuration(isPrivate: false))
    }

    func testPrivateTabPageUsesNonPersistentStore() {
        let pool = TabPool()
        let id = UUID()
        pool.create(id: id, isPrivate: true)

        guard let store = pool.page(for: id)?.webView.configuration.websiteDataStore else {
            XCTFail("private tab has no website data store")
            return
        }

        XCTAssertFalse(store.isPersistent)
        XCTAssertIdentical(store, pool.configuration(isPrivate: true).websiteDataStore)
    }
}
