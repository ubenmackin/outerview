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

    /// Removes a file off MainActor without throwing; failures only log.
    @MainActor
    private func removeFileOffMainActor(at url: URL) async {
        do {
            try await StagedDownloadFileWorker.shared.removeItem(at: url)
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
        Task { [weak self] in
            await self?.handleSessionDidFinishEvents(identifier: identifier)
        }
    }

    @MainActor
    private func handleSessionDidFinishEvents(identifier: String) {
        launchHandlerStore?.popLaunchHandler(for: identifier)?()
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Unknown totals or non-2xx responses never advance the progress ring.
        guard totalBytesExpectedToWrite > 0,
              DownloadsManager.httpErrorReason(for: downloadTask.response) == nil
        else { return }
        let key = ObjectIdentifier(downloadTask)
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { [weak self] in
            await self?.handleDownloadProgress(taskKey: key, fraction: fraction)
        }
    }

    @MainActor
    private func handleDownloadProgress(taskKey: ObjectIdentifier, fraction: Double) {
        guard let id = taskIDs[taskKey], let manager = effectiveManager else { return }
        manager.applyProgress(fraction, for: id)
    }

    nonisolated func urlSession(
        _ _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let key = ObjectIdentifier(downloadTask)
        let fallback = downloadTask.response?.suggestedFilename ?? "download"
        if let reason = DownloadsManager.httpErrorReason(for: downloadTask.response) {
            // Drop non-2xx error bodies before staging so HTTP failures never save as files.
            cleanupItem(at: location)
            Task { [weak self] in
                await self?.failHTTPResponse(taskKey: key, fallbackName: fallback, reason: reason)
            }
            return
        }
        // Stage synchronously off MainActor so the temp file survives the async handoff.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("ov-download-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: staging)
        } catch {
            logger.error("stage moveItem failed: \(error.localizedDescription, privacy: .private)")
            // System reclaims location after return; never hand it to async work.
            cleanupItem(at: location)
            let message = error.localizedDescription
            Task { [weak self] in
                await self?.handleStagingFailure(taskKey: key, message: message)
            }
            return
        }
        Task { [weak self] in
            await self?.finalizeDownload(taskKey: key, fallbackName: fallback, stagedURL: staging)
        }
    }

    @MainActor
    private func handleStagingFailure(taskKey: ObjectIdentifier, message: String) {
        guard let rowID = taskIDs[taskKey] else {
            taskIDs[taskKey] = nil
            return
        }
        clearMapping(taskKey: taskKey, rowID: rowID)
        if let manager = effectiveManager,
           let index = manager.rows.firstIndex(where: { $0.id == rowID }),
           manager.rows[index].state == .inProgress
        {
            manager.failDownload(id: rowID, reason: message)
        }
    }

    nonisolated func urlSession(_ _: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let key = ObjectIdentifier(task)
        let nsError = error as NSError
        let isCancelled = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        let message = isCancelled ? "Cancelled" : error.localizedDescription
        Task { [weak self] in
            await self?.handleTaskCompletion(taskKey: key, message: message)
        }
    }

    @MainActor
    private func handleTaskCompletion(taskKey: ObjectIdentifier, message: String) {
        // Success without error is owned by finalize; leave mapping for it.
        guard let rowID = taskIDs[taskKey] else { return }
        clearMapping(taskKey: taskKey, rowID: rowID)
        guard let manager = effectiveManager else { return }
        manager.failDownload(id: rowID, reason: message)
    }

    /// Clears mappings and surfaces an HTTP status failure on the mapped or relaunched row.
    @MainActor
    private func failHTTPResponse(taskKey: ObjectIdentifier, fallbackName: String, reason: String) {
        let rowID = taskIDs[taskKey]
        let reserved = rowID.flatMap { names[$0] } ?? fallbackName
        defer { clearMapping(taskKey: taskKey, rowID: rowID) }
        let manager = effectiveManager ?? ensureManagerForBackgroundWake()
        if let rowID {
            if let index = manager.rows.firstIndex(where: { $0.id == rowID }),
               manager.rows[index].state == .inProgress
            {
                manager.failDownload(id: rowID, reason: reason)
            }
        } else {
            let clean = DownloadsManager.sanitizedFileName(reserved)
            let newID = manager.registerRow(name: clean, fileURL: nil)
            manager.failDownload(id: newID, reason: reason)
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
    @MainActor
    private func discardStagedDownload(taskKey: ObjectIdentifier, resolved: ResolvedDownload, stagedURL: URL) async {
        await removeFileOffMainActor(at: stagedURL)
        // No destination means no row owner at resolve; surface a failed row.
        if let manager = effectiveManager {
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
        clearMapping(taskKey: taskKey, rowID: resolved.rowID)
    }

    /// Records a move failure on the mapped or relaunched row.
    @MainActor
    private func failStagedMove(
        taskKey: ObjectIdentifier,
        resolved: ResolvedDownload,
        stagedURL: URL,
        message: String
    ) async {
        await removeFileOffMainActor(at: stagedURL)
        defer { clearMapping(taskKey: taskKey, rowID: resolved.rowID) }
        let manager = effectiveManager ?? ensureManagerForBackgroundWake()
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

    /// Completes a moved file; relaunched completions surface a finished row.
    @MainActor
    private func finishMovedDownload(
        taskKey: ObjectIdentifier,
        resolved: ResolvedDownload,
        destination: URL
    ) async {
        let shouldKeep = completeMovedDownloadRow(taskKey: taskKey, resolved: resolved, destination: destination)
        if !shouldKeep {
            // Cancelled/deleted or manager-absent files never resurrect.
            await removeFileOffMainActor(at: destination)
        }
    }

    @MainActor
    private func completeMovedDownloadRow(
        taskKey: ObjectIdentifier,
        resolved: ResolvedDownload,
        destination: URL
    ) -> Bool {
        defer { clearMapping(taskKey: taskKey, rowID: resolved.rowID) }
        let manager = effectiveManager ?? ensureManagerForBackgroundWake()
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

    @MainActor
    private func retryDestinationAfterCollision(for resolved: ResolvedDownload, error: Error) -> URL? {
        guard Self.isFileExistsError(error), let manager = effectiveManager else { return nil }
        let fresh = manager.nextDestinationURL(for: resolved.clean, excluding: resolved.rowID)
        if let rowID = resolved.rowID {
            manager.renameRow(id: rowID, name: fresh.lastPathComponent, fileURL: fresh)
        }
        return fresh
    }

    /// Resolves the destination on MainActor, moves off MainActor, then completes rows.
    @MainActor
    private func finalizeDownload(taskKey: ObjectIdentifier, fallbackName: String, stagedURL: URL) async {
        let resolved = resolveDownload(taskKey: taskKey, fallbackName: fallbackName)
        guard let destination = resolved.destination else {
            await discardStagedDownload(taskKey: taskKey, resolved: resolved, stagedURL: stagedURL)
            return
        }
        do {
            try await StagedDownloadFileWorker.shared.moveItem(at: stagedURL, to: destination)
        } catch {
            // A reservation race or external file can collide; retry once with a fresh name.
            if let retried = retryDestinationAfterCollision(for: resolved, error: error) {
                do {
                    try await StagedDownloadFileWorker.shared.moveItem(at: stagedURL, to: retried)
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

/// Offloads blocking staged-file moves and removals off MainActor without MainActor.run hops.
private actor StagedDownloadFileWorker {
    static let shared = StagedDownloadFileWorker()

    func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
