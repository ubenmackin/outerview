// WebPage — Pooled tab controllers plus shared configurations.

import WebKit

/// Owns one WebPageController per tab, keyed by tab id, with a shared
/// WKWebViewConfiguration per browsing mode.
@MainActor
final class TabPool {
    /// Overview-ordered entry; `page` is nil while the tab's web view is
    /// evicted (recreated on the next activation).
    struct PageEntry {
        let id: UUID
        let page: WebPageController?
    }

    static let livePageLimit = 30

    /// nonPersistent() vends a fresh instance per call (unlike the default()
    /// singleton), so share one static store to keep every private tab in the
    /// same ephemeral session.
    private static let sharedPrivateStore = WKWebsiteDataStore.nonPersistent()

    private struct Entry {
        var id: UUID
        var isPrivate: Bool
        var page: WebPageController?
        var lastActiveAt: Date
    }

    private var entries: [Entry] = []
    private let normalConfiguration = TabPool.makeConfiguration(isPrivate: false)
    private let privateConfiguration = TabPool.makeConfiguration(isPrivate: true)

    static func makeConfiguration(isPrivate: Bool) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        // One data store per mode: normal tabs share the persistent default
        // store, private tabs share the static non-persistent store so nothing
        // (cookies, cache, offline data) survives the session.
        configuration.websiteDataStore = isPrivate
            ? sharedPrivateStore
            : WKWebsiteDataStore.default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        return configuration
    }

    /// In-order pages for the tab overview.
    var pages: [PageEntry] {
        entries.map { PageEntry(id: $0.id, page: $0.page) }
    }

    func create(_ record: TabRecord) {
        create(id: record.id, isPrivate: record.isPrivate)
    }

    func create(id: UUID, isPrivate: Bool) {
        upsert(id: id, isPrivate: isPrivate, page: nil)
    }

    func create(id: UUID, isPrivate: Bool, page: WebPageController) {
        upsert(id: id, isPrivate: isPrivate, page: page)
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Registers a restored tab without allocating its web view. The page
    /// materializes on the next activation, so a large restored strip never
    /// allocates up front and the live cap only applies to real activity.
    /// Seeded with the persisted recency so cross-launch eviction order holds.
    func reserve(_ record: TabRecord) {
        guard entries.firstIndex(where: { $0.id == record.id }) == nil else { return }
        entries.append(
            Entry(
                id: record.id,
                isPrivate: record.isPrivate,
                page: nil,
                lastActiveAt: record.lastActiveAt
            )
        )
    }

    /// Registers an id without a page; used when only the mode is known.
    func reserve(id: UUID, isPrivate: Bool) {
        guard entries.firstIndex(where: { $0.id == id }) == nil else { return }
        entries.append(
            Entry(
                id: id,
                isPrivate: isPrivate,
                page: nil,
                lastActiveAt: Date()
            )
        )
    }

    /// Activates a tab: returns its live page, recreating it first when the
    /// page was evicted earlier.
    func page(for id: UUID) -> WebPageController? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        entries[index].lastActiveAt = Date()
        if let page = entries[index].page {
            return page
        }
        let page = WebPageController(configuration: configuration(isPrivate: entries[index].isPrivate))
        entries[index].page = page
        evictIfNeeded(excluding: id)
        return page
    }

    func configuration(isPrivate: Bool) -> WKWebViewConfiguration {
        isPrivate ? privateConfiguration : normalConfiguration
    }

    // MARK: - Private

    private func upsert(id: UUID, isPrivate: Bool, page: WebPageController?) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            // Re-creating an existing tab keeps its page and order.
            if let page {
                entries[index].page = page
            }
            entries[index].lastActiveAt = Date()
            return
        }
        let resolved = page ?? WebPageController(configuration: configuration(isPrivate: isPrivate))
        entries.append(
            Entry(
                id: id,
                isPrivate: isPrivate,
                page: resolved,
                lastActiveAt: Date()
            )
        )
        evictIfNeeded(excluding: nil)
    }

    private func evictIfNeeded(excluding excludedID: UUID?) {
        while entries.filter({ $0.page != nil }).count > Self.livePageLimit {
            // The just-recreated page is excluded so an activation can never
            // evict itself; with no eligible victim the loop exits.
            guard let victim = entries
                .enumerated()
                .filter({ $0.element.page != nil && $0.element.id != excludedID })
                .min(by: { $0.element.lastActiveAt < $1.element.lastActiveAt })
            else { break }
            entries[victim.offset].page = nil
        }
    }
}
