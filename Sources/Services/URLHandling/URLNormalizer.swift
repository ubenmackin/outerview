//
//  URLNormalizer.swift
//  OuterView
//

import Foundation

/// Single owner of RFC 3986 unreserved encoding for query strings.
enum URLQueryEncoder: Sendable {
    static let unreservedAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}

/// Search engines the address bar can fall back to. The raw value is what
/// Settings persists under the "searchEngine" key.
enum SearchEngine: String, CaseIterable, Sendable {
    case google
    case duckduckgo
    case bing
    case brave

    var displayName: String {
        switch self {
        case .google: "Google"
        case .duckduckgo: "DuckDuckGo"
        case .bing: "Bing"
        case .brave: "Brave"
        }
    }

    /// Search URL for `query`. Spaces and every non-unreserved character are
    /// percent-encoded — spaces always become %20 — so every engine produces
    /// a deterministic URL.
    func searchURL(_ query: String) -> URL {
        let base = switch self {
        case .google:
            "https://google.com/search?q="
        case .duckduckgo:
            "https://duckduckgo.com/?q="
        case .bing:
            "https://bing.com/search?q="
        case .brave:
            "https://search.brave.com/search?q="
        }
        // Encoding below emits ASCII only, so the assembled string always parses.
        guard let url = URL(string: base + Self.percentEncodedQuery(query)) else {
            return URL(string: base) ?? URL(filePath: "/")
        }
        return url
    }

    /// Restricted to RFC 3986 unreserved ASCII so "&", "+", "#", and spaces are
    /// encoded and cannot alter the query structure.
    private static func percentEncodedQuery(_ query: String) -> String {
        query.addingPercentEncoding(withAllowedCharacters: URLQueryEncoder.unreservedAllowed) ?? query
    }
}

/// Single owner of raw address-bar input → URL conversion.
enum URLNormalizer: Sendable {
    enum NormalizerFailure: Error, Equatable, Sendable {
        case empty
        case tooLong
        case invalidCharacters
        case unsupportedScheme(String)
        case malformed
    }

    private enum Limits {
        static let maxRawLength = 2048
    }

    static func normalize(_ raw: String, engine: SearchEngine) -> Result<URL, NormalizerFailure> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        // The length rule applies to the raw input, before trimming.
        guard raw.count <= Limits.maxRawLength else { return .failure(.tooLong) }
        guard !containsControlScalar(trimmed) else { return .failure(.invalidCharacters) }

        // The single non-http special case allowed through.
        if trimmed == "about:blank" {
            guard let url = URL(string: "about:blank") else {
                return .failure(.malformed)
            }
            return .success(url)
        }

        if let scheme = explicitScheme(of: trimmed) {
            let lowered = scheme.lowercased()
            guard lowered == "http" || lowered == "https" else {
                return .failure(.unsupportedScheme(lowered))
            }
            guard let url = URL(string: trimmed) else { return .failure(.malformed) }
            return .success(url)
        }

        // Scheme-less input containing a space, or a single dot-less word, is
        // a search query.
        if trimmed.contains(" ") || !trimmed.contains(".") {
            return .success(engine.searchURL(trimmed))
        }

        guard let url = URL(string: "https://" + trimmed) else { return .failure(.malformed) }
        return .success(url)
    }

    /// Central scheme allowlist for anything that can reach a web view or
    /// persistence. Only http/https plus the literal about:blank may load;
    /// every other scheme is rejected at each load and write path.
    static func isLoadable(_ url: URL?) -> Bool {
        guard let url else { return false }
        if url.absoluteString.lowercased() == "about:blank" {
            return true
        }
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    static func unsupportedSchemeMessage(_ scheme: String) -> String {
        "“\(scheme)” links aren’t supported."
    }

    // MARK: - Classification helpers

    /// Returns the scheme text when the input carries a real scheme marker.
    /// A colon with nothing after it ("localhost:") is not a scheme marker; it
    /// routes to search like any other dot-less word.
    private static func explicitScheme(of input: String) -> String? {
        guard let colon = input.firstIndex(of: ":") else { return nil }
        let head = String(input[input.startIndex ..< colon])
        let rest = input[input.index(after: colon)...]
        guard !rest.isEmpty, isSchemeText(head) else { return nil }
        return head
    }

    /// Scheme grammar: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ), ASCII only.
    private static func isSchemeText(_ text: String) -> Bool {
        guard let first = text.first, first.isASCII, first.isLetter else { return false }
        return text.dropFirst().allSatisfy { character in
            character.isASCII
                && (character.isLetter || character.isNumber
                    || character == "+" || character == "-" || character == ".")
        }
    }

    private static func containsControlScalar(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}
