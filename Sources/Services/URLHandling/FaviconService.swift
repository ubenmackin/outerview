//
//  FaviconService.swift
//  OuterView
//

import os
import UIKit

/// Resolves high-resolution touch icons / favicons with disk & memory caching
/// and Safari-style monogram fallbacks.
@MainActor
final class FaviconService {
    static let shared = FaviconService()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let cacheDirectory: URL?
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.0
        self.session = URLSession(configuration: config)

        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = caches.appendingPathComponent("Favicons", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Favicons")
                    .error("favicon cache directory failed: \(error.localizedDescription, privacy: .public)")
            }
            self.cacheDirectory = dir
        } else {
            self.cacheDirectory = nil
        }
    }

    /// Fetches favicon asynchronously, returning cached or newly fetched image.
    /// Falls back to monogram on network failure.
    func favicon(for url: URL, size: CGFloat = 88) async -> UIImage {
        // Screenshot runs stay offline; monograms keep captures deterministic.
        if BrowserRootViewController.isScreenshotRun {
            return generateMonogram(for: HostFormatter.host(of: url), size: size)
        }
        let nsURL = url as NSURL
        if let cached = memoryCache.object(forKey: nsURL) {
            return resizedForDisplay(cached, size: size)
        }

        let host = HostFormatter.host(of: url)
        if let diskImage = await loadFromDisk(forHost: host) {
            memoryCache.setObject(diskImage, forKey: nsURL)
            return resizedForDisplay(diskImage, size: size)
        }

        // Fetch from S2 favicon service
        if let fetched = await fetchRemoteFavicon(host: host) {
            memoryCache.setObject(fetched, forKey: nsURL)
            saveToDisk(image: fetched, forHost: host)
            return resizedForDisplay(fetched, size: size)
        }

        // Fallback to monogram
        let monogram = generateMonogram(for: host, size: size)
        memoryCache.setObject(monogram, forKey: nsURL)
        return monogram
    }

    /// Synchronous retrieval: memory cache or instant monogram only.
    /// Disk I/O stays in the async path so scrolling never blocks the main thread.
    func cachedFaviconOrMonogram(for url: URL, size: CGFloat = 88) -> UIImage {
        let nsURL = url as NSURL
        if let cached = memoryCache.object(forKey: nsURL) {
            return resizedForDisplay(cached, size: size)
        }
        let host = HostFormatter.host(of: url)
        return generateMonogram(for: host, size: size)
    }

    // MARK: - Monogram Generator

    /// Generates a Safari-style tinted rounded tile with the domain's initial.
    func generateMonogram(for host: String, size: CGFloat = 88) -> UIImage {
        let cleanHost = host.lowercased().replacingOccurrences(of: "www.", with: "")
        let initial = String(cleanHost.first ?? "?").uppercased()

        let hue = CGFloat(HostFormatter.stableHue(forHost: host))
        let bgColor = UIColor(hue: hue, saturation: 0.55, brightness: 0.70, alpha: 1.0)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size * 0.22)
            bgColor.setFill()
            path.fill()

            let font = UIFont.systemFont(ofSize: size * 0.45, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]
            let string = NSAttributedString(string: initial, attributes: attributes)
            let strSize = string.size()
            let strRect = CGRect(
                x: (size - strSize.width) / 2,
                y: (size - strSize.height) / 2,
                width: strSize.width,
                height: strSize.height
            )
            string.draw(in: strRect)
        }
    }

    // MARK: - Private

    /// Cached and remote favicons are shared across callers requesting
    /// different point sizes, so normalize to the requested size on return.
    private func resizedForDisplay(_ image: UIImage, size: CGFloat) -> UIImage {
        let target = CGSize(width: size, height: size)
        guard size > 0, image.size != target else { return image }
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private func fetchRemoteFavicon(host: String) async -> UIImage? {
        // Screenshot runs never hit the network.
        guard !BrowserRootViewController.isScreenshotRun, !host.isEmpty else {
            return nil
        }
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "128")
        ]
        guard let serviceURL = components?.url else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: serviceURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let image = UIImage(data: data)
            else {
                return nil
            }
            return image
        } catch {
            return nil
        }
    }

    private func diskURL(forHost host: String) -> URL? {
        // Empty hosts skip disk caching; the hash suffix keeps sanitized names collision-free.
        guard !host.isEmpty else { return nil }
        let lowered = host.lowercased()
        var hash = 0
        for scalar in lowered.unicodeScalars {
            hash = (hash &* 31) &+ Int(scalar.value)
        }
        let suffix = String(UInt(bitPattern: hash), radix: 16)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        let sanitized = lowered.addingPercentEncoding(withAllowedCharacters: allowed) ?? "host"
        let prefix = String(sanitized.prefix(48))
        guard !prefix.isEmpty else { return nil }
        return cacheDirectory?.appendingPathComponent("\(prefix)-\(suffix).png")
    }

    private func loadFromDisk(forHost host: String) async -> UIImage? {
        guard let url = diskURL(forHost: host),
              let data = await FaviconDiskCache.shared.read(from: url),
              let image = UIImage(data: data)
        else {
            return nil
        }
        return image
    }

    private func saveToDisk(image: UIImage, forHost host: String) {
        // Screenshot runs keep favicons in memory only.
        guard !BrowserRootViewController.isScreenshotRun,
              let url = diskURL(forHost: host),
              let data = image.pngData()
        else {
            return
        }
        Task(priority: .utility) {
            await FaviconDiskCache.shared.write(data, to: url)
        }
    }
}

/// Dedicated background actor for offloading disk I/O from @MainActor.
actor FaviconDiskCache {
    static let shared = FaviconDiskCache()

    func read(from url: URL) -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch {
            return nil
        }
    }

    func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Favicons")
                .error("favicon cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
