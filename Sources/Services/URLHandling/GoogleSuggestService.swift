//
//  GoogleSuggestService.swift
//  OuterView
//

import Foundation

/// Fetches per-engine search suggestions as the user types.
actor GoogleSuggestService {
    static let shared = GoogleSuggestService()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 2.0
            config.timeoutIntervalForResource = 2.0
            self.session = URLSession(configuration: config)
        }
    }

    /// Fetches up to `limit` suggestions for `query` using the endpoint for
    /// `engine`. Brave has no stable keyless endpoint and always yields empty,
    /// as does any network or decoding failure.
    func fetchSuggestions(for query: String, engine: SearchEngine, limit: Int = 5) async -> [String] {
        if engine == .brave {
            return []
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = Self.suggestURL(for: engine, query: trimmed)
        else {
            return []
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            return Self.parseSuggestions(data, engine: engine, limit: limit)
        } catch {
            return []
        }
    }

    /// Suggest endpoint for `engine`, or nil when the engine offers no
    /// stable keyless endpoint. The query is trimmed and RFC 3986 encoded
    /// before interpolation.
    nonisolated static func suggestURL(for engine: SearchEngine, query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: URLQueryEncoder.unreservedAllowed)
        else {
            return nil
        }
        let raw: String
        switch engine {
        case .google:
            raw = "https://suggestqueries.google.com/complete/search?client=safari&q=\(encoded)"
        case .bing:
            raw = "https://api.bing.com/osjson.aspx?query=\(encoded)"
        case .duckduckgo:
            raw = "https://duckduckgo.com/ac/?q=\(encoded)"
        case .brave:
            return nil
        }
        return URL(string: raw)
    }

    /// Parses per-engine suggest payloads. Google and Bing use the OpenSearch
    /// array shape; DuckDuckGo uses the phrase-dictionary shape; Brave and
    /// malformed payloads yield empty.
    nonisolated static func parseSuggestions(_ data: Data, engine: SearchEngine, limit: Int = 5) -> [String] {
        switch engine {
        case .duckduckgo:
            parsePhraseSuggestions(from: data, limit: limit)
        case .google, .bing:
            parseOpenSearchSuggestions(from: data, limit: limit)
        case .brave:
            []
        }
    }

    /// DuckDuckGo phrase shape: [{"phrase": "…"}, …].
    private nonisolated static func parsePhraseSuggestions(from data: Data, limit: Int) -> [String] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            return []
        }
        guard let rows = jsonObject as? [[String: Any]] else {
            return []
        }
        var results: [String] = []
        for row in rows {
            guard let phrase = row["phrase"] as? String else { continue }
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                results.append(trimmed)
            }
        }
        return Array(results.prefix(limit))
    }

    /// OpenSearch array shape: ["query", ["s1", "s2"]].
    private nonisolated static func parseOpenSearchSuggestions(from data: Data, limit: Int) -> [String] {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            return []
        }
        guard let json = jsonObject as? [Any],
              json.count >= 2,
              let rawSuggestions = json[1] as? [Any]
        else {
            return []
        }
        var results: [String] = []
        for item in rawSuggestions {
            if let str = item as? String {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    results.append(trimmed)
                }
            } else if let arr = item as? [Any], let str = arr.first as? String {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    results.append(trimmed)
                }
            }
        }
        return Array(results.prefix(limit))
    }

    /// Legacy Google-only entry point kept for existing callers.
    /// Supports both array-of-arrays (client=safari) and string-array (client=firefox) formats.
    nonisolated static func parseSuggestions(from data: Data, limit: Int = 5) -> [String] {
        parseOpenSearchSuggestions(from: data, limit: limit)
    }
}
