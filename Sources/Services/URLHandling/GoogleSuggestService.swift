//
//  GoogleSuggestService.swift
//  OuterView
//

import Foundation
import os

private struct DuckDuckGoPhraseRow: Decodable {
    let phrase: String?
}

private struct OpenSearchTupleRow: Decodable {
    let first: String

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        first = try container.decode(String.self)
    }
}

private func decodeOptionalMatch<T: Decodable>(
    _ type: T.Type,
    from container: SingleValueDecodingContainer
) throws -> T? {
    do {
        return try container.decode(type)
    } catch DecodingError.typeMismatch, DecodingError.valueNotFound {
        return nil
    }
}

private enum OpenSearchSuggestionValue: Decodable {
    case string(String)
    case tuple(OpenSearchTupleRow)
    case other

    var text: String? {
        switch self {
        case let .string(value):
            value
        case let .tuple(row):
            row.first
        case .other:
            nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try decodeOptionalMatch(String.self, from: container) {
            self = .string(string)
        } else if let tuple = try decodeOptionalMatch(OpenSearchTupleRow.self, from: container) {
            self = .tuple(tuple)
        } else {
            self = .other
        }
    }
}

private enum OpenSearchRootElement: Decodable {
    case query(String)
    case suggestions([OpenSearchSuggestionValue])
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let query = try decodeOptionalMatch(String.self, from: container) {
            self = .query(query)
        } else if let list = try decodeOptionalMatch([OpenSearchSuggestionValue].self, from: container) {
            self = .suggestions(list)
        } else {
            self = .other
        }
    }
}

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
        } catch is CancellationError {
            return []
        } catch let urlError as URLError where urlError.code == .cancelled {
            return []
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Suggestions")
                .error("Suggest fetch failed: \(error.localizedDescription, privacy: .public)")
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
        let rows: [DuckDuckGoPhraseRow]
        do {
            rows = try JSONDecoder().decode([DuckDuckGoPhraseRow].self, from: data)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Suggestions")
                .debug("DuckDuckGo suggest decode failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        var results: [String] = []
        for row in rows {
            guard let phrase = row.phrase else { continue }
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                results.append(trimmed)
            }
        }
        return Array(results.prefix(limit))
    }

    /// OpenSearch array shape: ["query", ["s1", "s2"]].
    private nonisolated static func parseOpenSearchSuggestions(from data: Data, limit: Int) -> [String] {
        let root: [OpenSearchRootElement]
        do {
            root = try JSONDecoder().decode([OpenSearchRootElement].self, from: data)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Suggestions")
                .debug("OpenSearch suggest decode failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        guard root.count >= 2,
              case let .suggestions(items) = root[1]
        else {
            return []
        }
        var results: [String] = []
        for item in items {
            guard let text = item.text else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                results.append(trimmed)
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
