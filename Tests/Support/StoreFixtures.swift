// Support — temp-store lifecycle helpers for on-disk SwiftData fixtures.

import Foundation
import SwiftData

enum StoreFixtures {
    /// Unique temp store URL under the process tmp dir.
    static func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".store")
    }

    /// Removes the store plus SQLite journal siblings after draining an empty
    /// autoreleasepool, so CoreData internals lagged from the test body close
    /// their connections before the files vanish.
    static func removeStoreArtifacts(at url: URL) {
        autoreleasepool {}
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    /// Runs `body` inside an explicit autoreleasepool so containers, contexts,
    /// and rows tear their SQLite connections down before returning; a live
    /// writer connection across store re-opens logs disk-I/O errors otherwise.
    static func quiesced<T>(_ body: () throws -> T) rethrows -> T {
        try autoreleasepool { try body() }
    }
}
