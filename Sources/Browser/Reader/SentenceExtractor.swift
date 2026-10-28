//
//  SentenceExtractor.swift
//  OuterView
//

import Foundation

enum SentenceExtractor: Sendable {
    /// Extracts the first 1 to `maxCount` sentences from `text`, trimmed and capped at `maxLength`.
    static func firstSentences(from text: String, maxCount: Int = 2, maxLength: Int = 300) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var sentences: [String] = []
        trimmed.enumerateSubstrings(in: trimmed.startIndex ..< trimmed.endIndex, options: [.bySentences, .localized]) { substring, _, _, stop in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                sentences.append(sentence)
                if sentences.count >= maxCount {
                    stop = true
                }
            }
        }

        if sentences.isEmpty {
            return String(trimmed.prefix(maxLength))
        }

        let combined = sentences.joined(separator: " ")
        if combined.count <= maxLength {
            return combined
        }
        return String(combined.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
