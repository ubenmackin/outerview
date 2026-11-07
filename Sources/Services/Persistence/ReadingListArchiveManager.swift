// Persistence — Offline web-archive storage for Reading List.

import Foundation
import os

/// Manages offline web archive storage for Reading List items.
@MainActor
final class ReadingListArchiveManager {
    static let shared = ReadingListArchiveManager()

    private let fileManager = FileManager.default
    private let directoryURL: URL

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directoryURL = appSupport.appendingPathComponent("ReadingListArchives", isDirectory: true)
        }
        do {
            try fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("createDirectory for archives failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func archiveURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString).webarchive")
    }

    /// Single-file atomic writes stay synchronous so callers keep fail-closed ordering.
    func saveArchive(data: Data, for id: UUID) {
        let url = archiveURL(for: id)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("Saving reading list archive failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Missing files read as nil so offline-cache absence never surfaces to UI.
    func archiveData(for id: UUID) -> Data? {
        let url = archiveURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("Reading archive failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func deleteArchive(for id: UUID) {
        let url = archiveURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("Deleting archive failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func hasArchive(for id: UUID) -> Bool {
        let url = archiveURL(for: id)
        return fileManager.fileExists(atPath: url.path)
    }
}
