//
//  GoogleSuggestService.swift
//  OuterView
//

import Foundation

/// Fetches search suggestions from Google's suggest API as the user types.
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

    /// Fetches up to `limit` suggestions for `query`. Returns empty array on network failure.
    func fetchSuggestions(for query: String, limit: Int = 5) async -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: URLQueryEncoder.unreservedAllowed),
              let url = URL(string: "https://suggestqueries.google.com/complete/search?client=safari&q=\(encoded)")
        else {
            return []
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            return Self.parseSuggestions(from: data, limit: limit)
        } catch {
            return []
        }
    }

    /// Parses search suggestions from Google suggest JSON responses.
    /// Supports both array-of-arrays (client=safari) and string-array (client=firefox) formats.
    nonisolated static func parseSuggestions(from data: Data, limit: Int = 5) -> [String] {
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
}
