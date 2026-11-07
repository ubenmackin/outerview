// URLHandling — Async favicon fetching with disk caching plus monogram fallback.

import os
import UIKit

/// Resolves high-resolution touch icons / favicons with disk & memory caching
/// and Safari-style monogram fallbacks.
@MainActor
final class FaviconService {
    static let shared = FaviconService()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let privateMemoryCache = NSCache<NSURL, UIImage>()
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
    /// Private URLs stay in memory only, never touching disk or network.
    func favicon(for url: URL, size: CGFloat = 88, isPrivate: Bool = false) async -> UIImage {
        let nsURL = url as NSURL
        // Private tabs use an isolated in-memory cache so disk-derived
        // entries never surface there and private monograms never poison
        // later standard fetches sharing the same URL key.
        if isPrivate {
            if let cached = privateMemoryCache.object(forKey: nsURL) {
                return resizedForDisplay(cached, size: size)
            }
            let host = HostFormatter.host(of: url)
            if let brand = brandFavicon(for: host, size: size) {
                privateMemoryCache.setObject(brand, forKey: nsURL)
                return brand
            }
            let monogram = generateMonogram(for: host, size: size)
            privateMemoryCache.setObject(monogram, forKey: nsURL)
            return monogram
        }

        if let cached = memoryCache.object(forKey: nsURL) {
            return resizedForDisplay(cached, size: size)
        }

        let host = HostFormatter.host(of: url)
        if let brand = brandFavicon(for: host, size: size) {
            memoryCache.setObject(brand, forKey: nsURL)
            return brand
        }

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

    /// Synchronous retrieval: memory cache, brand favicon, or instant monogram.
    /// Disk I/O stays in the async path so scrolling never blocks the main thread.
    func cachedFaviconOrMonogram(for url: URL, size: CGFloat = 88, isPrivate: Bool = false) -> UIImage {
        let nsURL = url as NSURL
        // Private sync reads stay in the isolated cache; shared disk-derived
        // entries never surface in private tabs.
        if isPrivate {
            if let cached = privateMemoryCache.object(forKey: nsURL) {
                return resizedForDisplay(cached, size: size)
            }
            let host = HostFormatter.host(of: url)
            if let brand = brandFavicon(for: host, size: size) {
                privateMemoryCache.setObject(brand, forKey: nsURL)
                return brand
            }
            return generateMonogram(for: host, size: size)
        }
        if let cached = memoryCache.object(forKey: nsURL) {
            return resizedForDisplay(cached, size: size)
        }
        let host = HostFormatter.host(of: url)
        if let brand = brandFavicon(for: host, size: size) {
            memoryCache.setObject(brand, forKey: nsURL)
            return brand
        }
        return generateMonogram(for: host, size: size)
    }

    /// Shared binding lifecycle for reusable favicon views: synchronous
    /// cache-or-monogram, then an async upgrade that lands only while the
    /// task is live and `currentIdentity()` still matches the bound identity.
    func bind(
        url: URL,
        into view: UIImageView,
        identity: UUID,
        currentIdentity: @escaping @MainActor () -> UUID?,
        size: CGFloat,
        isPrivate: Bool = false
    ) -> Task<Void, Never> {
        view.image = cachedFaviconOrMonogram(for: url, size: size, isPrivate: isPrivate)
        return Task { [weak view] in
            let image = await favicon(for: url, size: size, isPrivate: isPrivate)
            guard let view, !Task.isCancelled, currentIdentity() == identity else { return }
            view.image = image
        }
    }

    // MARK: - Brand Favicons

    /// High-resolution brand icons for prominent domains, ensuring crisp favicons
    /// during screenshot runs and offline sessions.
    func brandFavicon(for host: String, size: CGFloat = 88) -> UIImage? {
        let cleanHost = host.lowercased().replacingOccurrences(of: "www.", with: "")

        if isBrandHost(cleanHost, matching: "apple.com") {
            return drawSymbolFavicon(backgroundColor: .black, systemName: "apple.logo", size: size)
        }
        if isBrandHost(cleanHost, matching: "wikipedia.org") {
            let font = UIFont(name: "Georgia-Bold", size: size * 0.55) ?? UIFont.systemFont(ofSize: size * 0.55, weight: .bold)
            return drawTextFavicon(
                backgroundColor: .white,
                text: "W",
                font: font,
                textColor: UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0),
                borderColor: .separator,
                size: size
            )
        }
        if isBrandHost(cleanHost, matching: "github.com") {
            let font = UIFont.systemFont(ofSize: size * 0.38, weight: .heavy)
            return drawTextFavicon(
                backgroundColor: UIColor(red: 0.14, green: 0.16, blue: 0.18, alpha: 1.0),
                text: "GH",
                font: font,
                textColor: .white,
                size: size
            )
        }
        if isBrandHost(cleanHost, matching: "swift.org") {
            return drawSymbolFavicon(
                backgroundColor: UIColor(red: 0.96, green: 0.35, blue: 0.22, alpha: 1.0),
                systemName: "swift",
                symbolWeight: .medium,
                size: size
            )
        }
        if isBrandHost(cleanHost, matching: "news.ycombinator.com") {
            let font = UIFont.systemFont(ofSize: size * 0.55, weight: .heavy)
            return drawTextFavicon(
                backgroundColor: UIColor(red: 1.0, green: 0.40, blue: 0.0, alpha: 1.0),
                text: "Y",
                font: font,
                textColor: .white,
                size: size
            )
        }
        if isBrandHost(cleanHost, matching: "duckduckgo.com") {
            let font = UIFont.systemFont(ofSize: size * 0.36, weight: .heavy)
            return drawTextFavicon(
                backgroundColor: UIColor(red: 0.88, green: 0.35, blue: 0.20, alpha: 1.0),
                text: "DDG",
                font: font,
                textColor: .white,
                size: size
            )
        }
        if isBrandHost(cleanHost, matching: "mozilla.org") {
            let font = UIFont.systemFont(ofSize: size * 0.34, weight: .black)
            return drawTextFavicon(
                backgroundColor: UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0),
                text: "MDN",
                font: font,
                textColor: UIColor(red: 0.33, green: 0.65, blue: 1.0, alpha: 1.0),
                size: size
            )
        }
        if isBrandHost(cleanHost, matching: "arstechnica.com") {
            let font = UIFont.systemFont(ofSize: size * 0.40, weight: .bold)
            return drawTextFavicon(
                backgroundColor: UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1.0),
                text: "ars",
                font: font,
                textColor: UIColor(red: 1.0, green: 0.28, blue: 0.20, alpha: 1.0),
                size: size
            )
        }
        if isBrandHost(cleanHost, matching: "webkit.org") {
            return drawSymbolFavicon(
                backgroundColor: UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0),
                systemName: "safari",
                size: size
            )
        }
        if isBrandHost(cleanHost, matching: "rust-lang.org") {
            let font = UIFont.systemFont(ofSize: size * 0.55, weight: .heavy)
            return drawTextFavicon(
                backgroundColor: UIColor(red: 0.20, green: 0.15, blue: 0.12, alpha: 1.0),
                text: "R",
                font: font,
                textColor: UIColor(red: 0.85, green: 0.55, blue: 0.35, alpha: 1.0),
                size: size
            )
        }

        return nil
    }

    /// Exact-host or label-boundary suffix match only; substring matching
    /// would render counterfeit brand icons for lookalike domains.
    private func isBrandHost(_ cleanHost: String, matching domain: String) -> Bool {
        cleanHost == domain || cleanHost.hasSuffix("." + domain)
    }

    private func drawSymbolFavicon(
        backgroundColor: UIColor,
        systemName: String,
        symbolWeight: UIImage.SymbolWeight = .semibold,
        size: CGFloat
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
        let cornerRadius = size * 0.22
        return renderer.image { _ in
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            backgroundColor.setFill()
            path.fill()
            let config = UIImage.SymbolConfiguration(pointSize: size * 0.52, weight: symbolWeight)
            if let symbol = UIImage(systemName: systemName, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                let symbolRect = CGRect(
                    x: (size - symbol.size.width) / 2,
                    y: (size - symbol.size.height) / 2,
                    width: symbol.size.width,
                    height: symbol.size.height
                )
                symbol.draw(in: symbolRect)
            }
        }
    }

    private func drawTextFavicon(
        backgroundColor: UIColor,
        text: String,
        font: UIFont,
        textColor: UIColor,
        borderColor: UIColor? = nil,
        size: CGFloat
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
        let cornerRadius = size * 0.22
        return renderer.image { _ in
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            backgroundColor.setFill()
            path.fill()
            if let borderColor {
                borderColor.setStroke()
                path.lineWidth = 1.0
                path.stroke()
            }
            let attr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let str = NSAttributedString(string: text, attributes: attr)
            let strSize = str.size()
            let strRect = CGRect(
                x: (size - strSize.width) / 2,
                y: (size - strSize.height) / 2,
                width: strSize.width,
                height: strSize.height
            )
            str.draw(in: strRect)
        }
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
