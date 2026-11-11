// Downloads — row plus destination plus transfer owner for standard and private downloads.

import Foundation
import Observation
import os
import UIKit
import WebKit

/// Discrete lifecycle of one download row.
enum DownloadState: Equatable, Sendable {
    case inProgress
    case finished
    case failed(String?)
}

/// One row in the downloads list.
struct DownloadRow: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var progress: Double
    var state: DownloadState
    var sizeLabel: String
    var fileURL: URL?
}

/// Row, progress and destination owner writing to Documents/Downloads.
@Observable
@MainActor
final class DownloadsManager: NSObject {
    private(set) var rows: [DownloadRow] = [] {
        didSet {
            onProgressChange?()
        }
    }

    @ObservationIgnored
    var onProgressChange: (@MainActor () -> Void)?

    /// Mean of in-progress fractions, or nil when nothing is downloading.
    var overallProgress: Double? {
        let active = rows.filter { $0.state == .inProgress }
        guard !active.isEmpty else { return nil }
        return active.reduce(0.0) { $0 + $1.progress } / Double(active.count)
    }

    let directoryURL: URL
    @ObservationIgnored
    private let fileManager: FileManager

    @ObservationIgnored
    private var downloads: [UUID: WKDownload] = [:]
    @ObservationIgnored
    private var destinations: [UUID: URL] = [:]
    @ObservationIgnored
    private var downloadIDs: [ObjectIdentifier: UUID] = [:]
    @ObservationIgnored
    private var observations: [UUID: NSKeyValueObservation] = [:]
    /// Sole daemon transfer owner; cancel/delete forward so no orphan task survives.
    @ObservationIgnored
    weak var backgroundService: BackgroundDownloadService?

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        let resolved: URL = if let directoryURL {
            directoryURL
        } else if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            documents.appendingPathComponent("Downloads", isDirectory: true)
        } else {
            fileManager.temporaryDirectory.appendingPathComponent("Downloads", isDirectory: true)
        }
        self.directoryURL = resolved
        self.fileManager = fileManager
        super.init()
        do {
            try fileManager.createDirectory(at: resolved, withIntermediateDirectories: true)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Downloads")
                .error("createDirectory failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - File naming

    /// Strips directory components and unsafe separators; blanks become "download".
    nonisolated static func sanitizedFileName(_ raw: String) -> String {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate = (candidate as NSString).lastPathComponent
        if candidate.contains("\\") {
            candidate = candidate.split(separator: "\\").last.map(String.init) ?? ""
        }
        // All-separator input collapses to "/" as the last component.
        if candidate == "/" {
            return "download"
        }
        candidate = candidate
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .controlCharacters)
        if candidate.isEmpty || candidate == "." || candidate == ".." {
            return "download"
        }
        // Cap at 255 bytes preserving the extension so the type survives.
        if candidate.utf8.count > 255 {
            let ext = (candidate as NSString).pathExtension
            var base = (candidate as NSString).deletingPathExtension
            if ext.isEmpty {
                while base.utf8.count > 255, !base.isEmpty {
                    base = String(base.dropLast())
                }
                candidate = base.isEmpty ? "download" : base
            } else {
                let maxBaseBytes = max(0, 255 - ext.utf8.count - 1)
                while base.utf8.count > maxBaseBytes, !base.isEmpty {
                    base = String(base.dropLast())
                }
                if base.isEmpty {
                    base = "download"
                }
                candidate = base + "." + ext
                while candidate.utf8.count > 255, !candidate.isEmpty {
                    candidate = String(candidate.dropLast())
                }
            }
        }
        return candidate
    }

    /// First non-colliding destination, appending " (2)", " (3)", … before the extension.
    static func uniqueDestinationURL(
        for fileName: String,
        in directory: URL,
        fileManager: FileManager = .default,
        reservedNames: Set<String> = []
    ) -> URL {
        let sanitized = sanitizedFileName(fileName)
        let ext = (sanitized as NSString).pathExtension
        let base = (sanitized as NSString).deletingPathExtension
        var candidate = sanitized
        var counter = 1
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path)
            || reservedNames.contains(candidate)
        {
            counter += 1
            if ext.isEmpty {
                candidate = "\(base) (\(counter))"
            } else {
                candidate = "\(base) (\(counter)).\(ext)"
            }
        }
        return directory.appendingPathComponent(candidate)
    }

    nonisolated static func formattedSize(byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    /// Non-2xx HTTP status codes surface a failure reason so error pages never save as files.
    nonisolated static func httpErrorReason(for response: URLResponse?) -> String? {
        guard let http = response as? HTTPURLResponse,
              !(200 ..< 300).contains(http.statusCode)
        else {
            return nil
        }
        return "Download failed (HTTP \(http.statusCode))"
    }

    /// Attaches matching cookies, browser User-Agent, and downgrade-safe Referer for daemon transfers.
    nonisolated static func preparedRequest(
        base: URLRequest,
        customUserAgent: String?,
        defaultUserAgent: String,
        pageURL: URL?,
        cookies: [HTTPCookie]
    ) -> URLRequest {
        var request = base
        if let url = base.url {
            let matching = matchingCookies(cookies, for: url)
            if !matching.isEmpty {
                for (field, value) in HTTPCookie.requestHeaderFields(with: matching) {
                    request.setValue(value, forHTTPHeaderField: field)
                }
            }
            if request.value(forHTTPHeaderField: "Referer") == nil,
               let referer = sanitizedReferer(from: pageURL, targetURL: url)
            {
                request.setValue(referer, forHTTPHeaderField: "Referer")
            }
        }
        if let customUserAgent, !customUserAgent.isEmpty {
            request.setValue(customUserAgent, forHTTPHeaderField: "User-Agent")
        } else if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")
        }
        return request
    }

    /// Cookies matching host plus path plus secure, for the daemon request.
    nonisolated static func matchingCookies(_ all: [HTTPCookie], for url: URL) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }
        let path = url.path.isEmpty ? "/" : url.path
        let isSecure = url.scheme?.lowercased() == "https"
        return all.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: .init(charactersIn: "."))
            guard host == domain || host.hasSuffix("." + domain) else { return false }
            if cookie.isSecure, !isSecure {
                return false
            }
            let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
            if path == cookiePath {
                return true
            }
            // Boundary check so /private never matches /private-evil per RFC6265.
            let prefix = cookiePath.hasSuffix("/") ? cookiePath : cookiePath + "/"
            return path.hasPrefix(prefix)
        }
    }

    /// Strips credentials and fragments and enforces no-referrer-when-downgrade.
    nonisolated static func sanitizedReferer(from pageURL: URL?, targetURL: URL) -> String? {
        guard let pageURL,
              let sourceScheme = pageURL.scheme?.lowercased(),
              sourceScheme == "http" || sourceScheme == "https",
              let targetScheme = targetURL.scheme?.lowercased(),
              targetScheme == "http" || targetScheme == "https",
              !(sourceScheme == "https" && targetScheme == "http"),
              var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        components.user = nil
        components.password = nil
        components.fragment = nil
        return components.url?.absoluteString
    }

    nonisolated static func isAttachmentResponse(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse,
              let disposition = http.value(forHTTPHeaderField: "Content-Disposition")
        else {
            return false
        }
        return disposition.lowercased().contains("attachment")
    }

    /// A response that cannot render inline or carries an attachment disposition downloads.
    static func shouldDownload(navigationResponse: WKNavigationResponse) -> Bool {
        !navigationResponse.canShowMIMEType || isAttachmentResponse(navigationResponse.response)
    }

    private func reservedFileNames(excluding excludedID: UUID? = nil) -> Set<String> {
        Set(destinations.compactMap { id, url in
            guard id != excludedID else { return nil }
            return url.lastPathComponent
        })
    }

    private func uniqueDestination(for fileName: String, excluding excludedID: UUID? = nil) -> URL {
        Self.uniqueDestinationURL(
            for: fileName,
            in: directoryURL,
            fileManager: fileManager,
            reservedNames: reservedFileNames(excluding: excludedID)
        )
    }

    // MARK: - Background service seams

    /// Destination seam for BackgroundDownloadService: first free name in Documents/Downloads.
    func nextDestinationURL(for fileName: String, excluding excludedID: UUID? = nil) -> URL {
        uniqueDestination(for: fileName, excluding: excludedID)
    }

    /// Reserved destination for an in-flight row, so daemon finalize reuses it.
    func reservedDestination(for id: UUID) -> URL? {
        destinations[id] ?? rows.first(where: { $0.id == id })?.fileURL
    }

    /// Adopts a relaunched row created on the wake fallback manager.
    func importRow(_ row: DownloadRow) {
        guard !rows.contains(where: { $0.id == row.id }) else { return }
        rows.append(row)
        if let fileURL = row.fileURL {
            destinations[row.id] = fileURL
        }
    }

    /// Applies the resolved destination (name + URL) to an in-progress row.
    func renameRow(id: UUID, name: String, fileURL: URL?) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].name = name
        rows[index].fileURL = fileURL
        if let fileURL {
            destinations[id] = fileURL
        }
    }

    // MARK: - Tracking

    @discardableResult
    func begin(download: WKDownload, suggestedName: String) -> Progress? {
        let destination = uniqueDestination(for: Self.sanitizedFileName(suggestedName))
        let id = UUID()
        rows.append(DownloadRow(
            id: id,
            name: destination.lastPathComponent,
            progress: 0,
            state: .inProgress,
            sizeLabel: "",
            fileURL: destination
        ))
        downloads[id] = download
        destinations[id] = destination
        downloadIDs[ObjectIdentifier(download)] = id
        download.delegate = self
        observations[id] = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                self?.applyProgress(progress.fractionCompleted, for: id)
            }
        }
        return download.progress
    }

    /// Test and delegate seam: creates an in-progress row without a live WKDownload.
    func registerRow(name: String, fileURL: URL?) -> UUID {
        let id = UUID()
        rows.append(DownloadRow(
            id: id,
            name: name,
            progress: 0,
            state: .inProgress,
            sizeLabel: "",
            fileURL: fileURL
        ))
        if let fileURL {
            destinations[id] = fileURL
        }
        return id
    }

    func applyProgress(_ fraction: Double, for id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }),
              rows[index].state == .inProgress
        else {
            return
        }
        rows[index].progress = min(max(fraction, 0), 1)
    }

    func completeDownload(id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].progress = 1
        rows[index].state = .finished
        let url = destinations[id] ?? rows[index].fileURL
        let resolvedSize: Int? = {
            guard let url else { return nil }
            do {
                return try fileManager.attributesOfItem(atPath: url.path)[.size] as? Int
            } catch {
                return nil
            }
        }()
        if let resolvedSize {
            rows[index].sizeLabel = Self.formattedSize(byteCount: resolvedSize)
        } else {
            rows[index].sizeLabel = ""
        }
    }

    func failDownload(id: UUID, reason: String?) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].state = .failed(reason)
        if let fileURL = destinations[id] ?? rows[index].fileURL,
           !fileManager.fileExists(atPath: fileURL.path)
        {
            // Release reservation when no file landed on disk so retries reuse the original name.
            destinations[id] = nil
            rows[index].fileURL = nil
        }
    }

    func cancel(id: UUID) {
        if let download = downloads[id] {
            download.cancel { _ in }
        }
        // Forward to the daemon so UI cancel leaves no orphan task.
        backgroundService?.cancel(id: id)
        observations[id]?.invalidate()
        observations[id] = nil
        if let index = rows.firstIndex(where: { $0.id == id }),
           rows[index].state == .inProgress
        {
            rows[index].state = .failed("Cancelled")
            releaseReservationAndCleanup(id: id)
        }
    }

    /// Suspend fail-closed: cancel foreground work; daemon tasks survive.
    func suspendForegroundDownloads() {
        for id in Array(downloads.keys) {
            guard let download = downloads[id],
                  let index = rows.firstIndex(where: { $0.id == id }),
                  rows[index].state == .inProgress
            else { continue }
            download.cancel { _ in }
            observations[id]?.invalidate()
            observations[id] = nil
            rows[index].state = .failed("Cancelled")
            releaseReservationAndCleanup(id: id)
            downloads[id] = nil
            for (key, value) in downloadIDs where value == id {
                downloadIDs.removeValue(forKey: key)
            }
        }
    }

    /// Frees the reserved name and deletes the partial file; row keeps its name.
    private func releaseReservationAndCleanup(id: UUID) {
        let fileURL = destinations[id] ?? rows.first(where: { $0.id == id })?.fileURL
        if let fileURL {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Downloads")
                    .error("removeItem failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        destinations[id] = nil
        if let index = rows.firstIndex(where: { $0.id == id }) {
            rows[index].fileURL = nil
        }
    }

    func delete(id: UUID) {
        observations[id]?.invalidate()
        observations[id] = nil
        if let download = downloads[id] {
            download.cancel { _ in }
        }
        // Forward to the daemon so delete leaves no orphan row.
        backgroundService?.cancel(id: id)
        downloads[id] = nil
        let fileURL = destinations[id] ?? rows.first(where: { $0.id == id })?.fileURL
        if let fileURL {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Downloads")
                    .error("removeItem failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        destinations[id] = nil
        for (key, value) in downloadIDs where value == id {
            downloadIDs.removeValue(forKey: key)
        }
        rows.removeAll(where: { $0.id == id })
    }

    // MARK: - Files app

    func deleteAll() {
        let ids = rows.map(\.id)
        for id in ids {
            delete(id: id)
        }
    }

    func makeFilesPicker() -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [directoryURL], asCopy: true)
    }
}

// MARK: - WKDownloadDelegate

extension DownloadsManager: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let clean = Self.sanitizedFileName(suggestedFilename.isEmpty ? (response.suggestedFilename ?? "download") : suggestedFilename)
        let key = ObjectIdentifier(download)
        if let reason = Self.httpErrorReason(for: response) {
            // Reject HTTP error responses so WKDownload never writes an error page to disk.
            if let id = downloadIDs[key] {
                failDownload(id: id, reason: reason)
                observations[id]?.invalidate()
                observations[id] = nil
                downloads[id] = nil
                downloadIDs[key] = nil
            } else {
                let id = registerRow(name: clean, fileURL: nil)
                failDownload(id: id, reason: reason)
            }
            completionHandler(nil)
            return
        }
        if let id = downloadIDs[key] {
            let destination = uniqueDestination(for: clean, excluding: id)
            destinations[id] = destination
            if let index = rows.firstIndex(where: { $0.id == id }) {
                rows[index].name = destination.lastPathComponent
                rows[index].fileURL = destination
            }
            completionHandler(destination)
            return
        }
        let destination = uniqueDestination(for: clean)
        let id = UUID()
        rows.append(DownloadRow(
            id: id,
            name: destination.lastPathComponent,
            progress: 0,
            state: .inProgress,
            sizeLabel: "",
            fileURL: destination
        ))
        downloads[id] = download
        destinations[id] = destination
        downloadIDs[ObjectIdentifier(download)] = id
        observations[id] = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                self?.applyProgress(progress.fractionCompleted, for: id)
            }
        }
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let id = downloadIDs[ObjectIdentifier(download)] else { return }
        completeDownload(id: id)
        observations[id]?.invalidate()
        observations[id] = nil
        downloads[id] = nil
    }

    func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData _: Data?
    ) {
        guard let id = downloadIDs[ObjectIdentifier(download)] else { return }
        failDownload(id: id, reason: error.localizedDescription)
        observations[id]?.invalidate()
        observations[id] = nil
        downloads[id] = nil
    }
}
