// Services/Downloads — background URLSession transfer owner for standard-tab downloads.
// Reassociates daemon callbacks to DownloadsManager rows and finalizes into Documents/Downloads.

import Foundation
import os

/// Pops the launch completion handler stored by the app delegate, keyed by session identifier.
@MainActor
protocol BackgroundLaunchHandlerStore: AnyObject {
    func popLaunchHandler(for identifier: String) -> (() -> Void)?
}

/// Sole transfer owner for standard-tab downloads, backed by one background session.
@MainActor
final class BackgroundDownloadService: NSObject, URLSessionDownloadDelegate {
    static let shared = BackgroundDownloadService()

    static let sessionIdentifier = "com.volcrypt.OuterView.downloads"

    /// Sole row owner; wired at boot so callbacks drive rows and the ring.
    @MainActor weak var manager: DownloadsManager?

    /// Strong fallback owning rows when wake arrives with no scene or root.
    @MainActor private var fallbackManager: DownloadsManager?

    /// Effective row owner: wired root manager first, fallback second.
    @MainActor private var effectiveManager: DownloadsManager? {
        manager ?? fallbackManager
    }

    /// Creates the fallback owner so background wake finalizes with rows.
    @MainActor
    func ensureManagerForBackgroundWake() -> DownloadsManager {
        if let existing = effectiveManager {
            return existing
        }
        let fresh = DownloadsManager()
        fallbackManager = fresh
        return fresh
    }

    /// Moves wake-created rows into the wired manager so the UI shows them.
    @MainActor
    func adoptFallbackRows(into manager: DownloadsManager) {
        guard let fallback = fallbackManager, fallback !== manager else { return }
        for row in fallback.rows {
            manager.importRow(row)
        }
        fallbackManager = nil
    }

    /// App delegate that drains wake callbacks; finish-events pops its handler per identifier.
    @MainActor weak var launchHandlerStore: BackgroundLaunchHandlerStore?

    /// Session binds its delegate at creation, so lazy waits until self exists.
    /// MainActor-isolated so creation and access stay serial under Sendable.
    @MainActor lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        // Rejoining the daemon by identifier lets earlier tasks finalize after relaunch.
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    /// Recreates the daemon session on wake so relaunch rejoins by identifier.
    /// Tests host no daemon; skipping keeps suite teardown from stalling.
    @MainActor
    func rejoin() {
        guard !AppEnvironment.isTestHost else { return }
        _ = ensureManagerForBackgroundWake()
        _ = session
    }

    private let logger = Logger(subsystem: "com.volcrypt.OuterView", category: "Downloads")
    @MainActor private var tasks: [UUID: URLSessionDownloadTask] = [:]
    @MainActor private var taskIDs: [ObjectIdentifier: UUID] = [:]
    @MainActor private var names: [UUID: String] = [:]

    override private init() {
        super.init()
    }

    // MARK: - Task lifecycle

    /// Schedules a daemon download task and registers its row; nil when rowless.
    /// Fail-closed: only isLoadable URLs start transfers, never orphan tasks.
    @MainActor
    @discardableResult
    func start(request: URLRequest, suggestedName: String, reusing rowID: UUID? = nil) -> UUID? {
        let clean = DownloadsManager.sanitizedFileName(suggestedName)
        // The manager-issued row id is the mapping key so callbacks hit the live row.
        guard let manager = effectiveManager else {
            // Fail-closed without a row owner: never schedule an orphan task.
            assertionFailure("BackgroundDownloadService manager unwired")
            return nil
        }
        guard request.url.map(URLNormalizer.isLoadable) ?? false else {
            // Rejected scheme never reaches the daemon; surface a failed row.
            assertionFailure("BackgroundDownloadService rejected URL")
            if let rowID, manager.rows.contains(where: { $0.id == rowID }) {
                manager.failDownload(id: rowID, reason: "Unsupported URL")
                return rowID
            }
            let id = manager.registerRow(name: clean, fileURL: nil)
            manager.failDownload(id: id, reason: "Unsupported URL")
            return id
        }
        if let rowID, manager.rows.contains(where: { $0.id == rowID }) {
            // Reuse the synchronously registered row so suspend during fetch keeps it.
            let destination = manager.nextDestinationURL(for: clean, excluding: rowID)
            manager.renameRow(id: rowID, name: destination.lastPathComponent, fileURL: destination)
            // Tests record rows without touching the daemon so teardown never stalls.
            guard !AppEnvironment.isTestHost else { return rowID }
            let task = session.downloadTask(with: request)
            tasks[rowID] = task
            taskIDs[ObjectIdentifier(task)] = rowID
            names[rowID] = destination.lastPathComponent
            task.resume()
            return rowID
        }
        // Reserve the destination upfront so same-name transfers diverge.
        let destination = manager.nextDestinationURL(for: clean, excluding: nil)
        let id = manager.registerRow(name: destination.lastPathComponent, fileURL: destination)
        // Tests record rows without touching the daemon so teardown never stalls.
        guard !AppEnvironment.isTestHost else { return id }
        let task = session.downloadTask(with: request)
        tasks[id] = task
        taskIDs[ObjectIdentifier(task)] = id
        names[id] = destination.lastPathComponent
        task.resume()
        return id
    }

    /// Cancels a background task; the delegate completion records the cancel row.
    @MainActor
    func cancel(id: UUID) {
        tasks[id]?.cancel()
    }

    /// Live task behind a row id, so tests can attach it to delegate callbacks.
    @MainActor
    func task(for id: UUID) -> URLSessionDownloadTask? {
        tasks[id]
    }

    /// Removes a file without throwing; failures only log.
    private nonisolated func cleanupItem(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("cleanup removeItem failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Clears task mappings for a finished row.
    @MainActor
    private func clearMapping(taskKey: ObjectIdentifier, rowID: UUID?) {
        taskIDs[taskKey] = nil
        if let rowID {
            tasks[rowID] = nil
            names[rowID] = nil
        }
    }

    // MARK: - Wake handling

    /// Delivered on the session queue after every enqueued message has been handled;
    /// returning the stored system completion here lets iOS snapshot the app switcher.
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }
        Task { @MainActor [weak self] in
            guard let store = self?.launchHandlerStore else { return }
            store.popLaunchHandler(for: identifier)?()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Unknown totals cannot yield a fraction, so they leave the current value.
        guard totalBytesExpectedToWrite > 0 else { return }
        let key = ObjectIdentifier(downloadTask)
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor [weak self] in
            guard let self, let id = self.taskIDs[key], let manager = self.effectiveManager else { return }
            manager.applyProgress(fraction, for: id)
        }
    }

    nonisolated func urlSession(
        _ _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let key = ObjectIdentifier(downloadTask)
        let fallback = downloadTask.response?.suggestedFilename ?? "download"
        // Stage synchronously off MainActor so the temp file survives the async handoff.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("ov-download-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: staging)
        } catch {
            logger.error("stage moveItem failed: \(error.localizedDescription, privacy: .private)")
            // System reclaims location after return; never hand it to async work.
            cleanupItem(at: location)
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let rowID = self.taskIDs[key] else {
                    self.taskIDs[key] = nil
                    return
                }
                self.taskIDs[key] = nil
                self.tasks[rowID] = nil
                self.names[rowID] = nil
                if let manager = self.effectiveManager,
                   let index = manager.rows.firstIndex(where: { $0.id == rowID }),
                   manager.rows[index].state == .inProgress
                {
                    manager.failDownload(id: rowID, reason: message)
                }
            }
            return
        }
        Task { [weak self] in
            await self?.finalizeDownload(taskKey: key, fallbackName: fallback, stagedURL: staging)
        }
    }

    nonisolated func urlSession(_ _: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let key = ObjectIdentifier(task)
        Task { @MainActor [weak self] in
            // Success without error is owned by finalize; leave mapping for it.
            guard let self, let error, let rowID = self.taskIDs[key] else { return }
            self.taskIDs[key] = nil
            self.tasks[rowID] = nil
            self.names[rowID] = nil
            guard let manager = self.effectiveManager else { return }
            // Map cancel distinctly so UI shows explicit Cancelled, not system text.
            let code = (error as NSError).code
            let domain = (error as NSError).domain
            let isCancelled = domain == NSURLErrorDomain && code == NSURLErrorCancelled
            manager.failDownload(id: rowID, reason: isCancelled ? "Cancelled" : error.localizedDescription)
        }
    }

    /// Resolved row plus destination for a staged download.
    private struct ResolvedDownload: Sendable {
        var rowID: UUID?
        var clean: String
        var destination: URL?
    }

    /// Resolves the row and destination on MainActor.
    @MainActor
    private func resolveDownload(taskKey: ObjectIdentifier, fallbackName: String) -> ResolvedDownload {
        let rowID = taskIDs[taskKey]
        guard let manager = self.effectiveManager else {
            return ResolvedDownload(rowID: rowID, clean: fallbackName, destination: nil)
        }
        if let rowID, let reserved = manager.reservedDestination(for: rowID) {
            // Reuse start-time reservation; concurrent same-name stays distinct.
            return ResolvedDownload(rowID: rowID, clean: reserved.lastPathComponent, destination: reserved)
        }
        let name = rowID.flatMap { names[$0] } ?? fallbackName
        let clean = DownloadsManager.sanitizedFileName(name)
        if let rowID {
            // Reserve now so concurrent completions diverge before moving.
            let destination = manager.nextDestinationURL(for: clean, excluding: rowID)
            manager.renameRow(id: rowID, name: destination.lastPathComponent, fileURL: destination)
            return ResolvedDownload(rowID: rowID, clean: destination.lastPathComponent, destination: destination)
        }
        // Unknown row after relaunch: register now so the name is reserved.
        let destination = manager.nextDestinationURL(for: clean, excluding: nil)
        let newID = manager.registerRow(name: destination.lastPathComponent, fileURL: destination)
        return ResolvedDownload(rowID: newID, clean: destination.lastPathComponent, destination: destination)
    }

    /// Drops a staged file with no destination and clears mappings.
    private nonisolated func discardStagedDownload(taskKey: ObjectIdentifier, resolved: ResolvedDownload, stagedURL: URL) async {
        cleanupItem(at: stagedURL)
        await MainActor.run { [weak self] in
            guard let self else { return }
            // No destination means no row owner at resolve; surface a failed row.
            if let manager = self.effectiveManager {
                if let rowID = resolved.rowID,
                   let index = manager.rows.firstIndex(where: { $0.id == rowID }),
                   manager.rows[index].state == .inProgress
                {
                    manager.failDownload(id: rowID, reason: "Download service unavailable")
                } else if resolved.rowID == nil {
                    let clean = DownloadsManager.sanitizedFileName(resolved.clean)
                    let newID = manager.registerRow(name: clean, fileURL: nil)
                    manager.failDownload(id: newID, reason: "Download service unavailable")
                }
            }
            self.clearMapping(taskKey: taskKey, rowID: resolved.rowID)
        }
    }

    /// Records a move failure on the mapped or relaunched row.
    private nonisolated func failStagedMove(
        taskKey: ObjectIdentifier,
        resolved: ResolvedDownload,
        stagedURL: URL,
        message: String
    ) async {
        cleanupItem(at: stagedURL)
        await MainActor.run { [weak self] in
            guard let self else { return }
            defer { self.clearMapping(taskKey: taskKey, rowID: resolved.rowID) }
            let manager = self.effectiveManager ?? self.ensureManagerForBackgroundWake()
            if let rowID = resolved.rowID {
                // Only in-progress rows fail; cancelled/deleted just clear.
                if let index = manager.rows.firstIndex(where: { $0.id == rowID }),
                   manager.rows[index].state == .inProgress
                {
                    manager.failDownload(id: rowID, reason: message)
                }
            } else {
                // Relaunch without mapping still surfaces a failed row.
                let newID = manager.registerRow(name: resolved.clean, fileURL: nil)
                manager.failDownload(id: newID, reason: message)
            }
        }
    }

    /// Completes a moved file; relaunched completions surface a finished row.
    private nonisolated func finishMovedDownload(
        taskKey: ObjectIdentifier,
        resolved: ResolvedDownload,
        destination: URL
    ) async {
        let shouldKeep: Bool = await MainActor.run { [weak self] in
            guard let self else { return false }
            defer { self.clearMapping(taskKey: taskKey, rowID: resolved.rowID) }
            let manager = self.effectiveManager ?? self.ensureManagerForBackgroundWake()
            if let rowID = resolved.rowID {
                // Only in-progress rows complete; cancelled/deleted just drop.
                guard let index = manager.rows.firstIndex(where: { $0.id == rowID }),
                      manager.rows[index].state == .inProgress
                else {
                    return false
                }
                manager.renameRow(id: rowID, name: destination.lastPathComponent, fileURL: destination)
                manager.completeDownload(id: rowID)
                return true
            }
            // Relaunch without mapping still surfaces a finished row.
            let newID = manager.registerRow(name: destination.lastPathComponent, fileURL: destination)
            manager.completeDownload(id: newID)
            return true
        }
        if !shouldKeep {
            // Cancelled/deleted or manager-absent files never resurrect.
            cleanupItem(at: destination)
        }
    }

    /// Resolves the destination on MainActor, moves off MainActor, then completes rows.
    private nonisolated func finalizeDownload(taskKey: ObjectIdentifier, fallbackName: String, stagedURL: URL) async {
        let resolved: ResolvedDownload = await MainActor.run { [weak self] in
            guard let self else { return ResolvedDownload(rowID: nil, clean: fallbackName, destination: nil) }
            return self.resolveDownload(taskKey: taskKey, fallbackName: fallbackName)
        }
        guard let destination = resolved.destination else {
            await discardStagedDownload(taskKey: taskKey, resolved: resolved, stagedURL: stagedURL)
            return
        }
        do {
            try FileManager.default.moveItem(at: stagedURL, to: destination)
        } catch {
            // A reservation race or external file can collide; retry once with a fresh name.
            let retried: URL? = await MainActor.run { [weak self] in
                guard let self, Self.isFileExistsError(error), let manager = self.effectiveManager else { return nil }
                let fresh = manager.nextDestinationURL(for: resolved.clean, excluding: resolved.rowID)
                if let rowID = resolved.rowID {
                    manager.renameRow(id: rowID, name: fresh.lastPathComponent, fileURL: fresh)
                }
                return fresh
            }
            if let retried {
                do {
                    try FileManager.default.moveItem(at: stagedURL, to: retried)
                    var moved = resolved
                    moved.destination = retried
                    moved.clean = retried.lastPathComponent
                    await finishMovedDownload(taskKey: taskKey, resolved: moved, destination: retried)
                    return
                } catch {
                    let message = error.localizedDescription
                    logger.error("moveItem retry failed: \(message, privacy: .private)")
                    await failStagedMove(taskKey: taskKey, resolved: resolved, stagedURL: stagedURL, message: message)
                    return
                }
            }
            let message = error.localizedDescription
            logger.error("moveItem failed: \(message, privacy: .private)")
            await failStagedMove(taskKey: taskKey, resolved: resolved, stagedURL: stagedURL, message: message)
            return
        }
        await finishMovedDownload(taskKey: taskKey, resolved: resolved, destination: destination)
    }

    /// True when a move failed because the destination already exists.
    private static func isFileExistsError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteFileExistsError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == EEXIST {
            return true
        }
        return false
    }
}
