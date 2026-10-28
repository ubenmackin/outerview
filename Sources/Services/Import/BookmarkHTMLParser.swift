//
//  BookmarkHTMLParser.swift
//  OuterView
//

import Foundation

struct ParsedBookmark: Equatable, Sendable {
    let title: String
    let url: URL
    let folderPath: [String]
    let addedDate: Date?
}

struct BookmarkParseResult: Equatable, Sendable {
    let bookmarks: [ParsedBookmark]
    let skippedInvalid: Int
    let truncated: Int
}

enum BookmarkParseError: Error, Equatable {
    case fileTooLarge
}

/// Line-based parser for the Netscape bookmark format Safari emits when
/// exporting Bookmarks.html (`<DT><A HREF>` entries, `<DT><H3>` folder
/// headers, nested `<DL><p>` lists).
enum BookmarkHTMLParser {
    private enum Limits {
        static let maxInputBytes = 10 * 1024 * 1024
    }

    private enum LineEvent {
        case folderHeader(String)
        case bookmark(href: String, title: String, addDate: String?)
        case listOpen
        case listClose
    }

    private struct RegexKit {
        let folderHeader: NSRegularExpression
        let anchorTag: NSRegularExpression
        let href: NSRegularExpression
        let addDate: NSRegularExpression
        let listOpen: NSRegularExpression
        let listClose: NSRegularExpression

        init() throws {
            folderHeader = try NSRegularExpression(
                pattern: "<H3\\b[^>]*>([^<]*)</H3>",
                options: [.caseInsensitive]
            )
            anchorTag = try NSRegularExpression(
                pattern: "<A\\b[^>]*>([^<]*)</A>",
                options: [.caseInsensitive]
            )
            href = try NSRegularExpression(
                pattern: "HREF\\s*=\\s*\"([^\"]*)\"",
                options: [.caseInsensitive]
            )
            addDate = try NSRegularExpression(
                pattern: "ADD_DATE\\s*=\\s*\"(\\d+)\"",
                options: [.caseInsensitive]
            )
            listOpen = try NSRegularExpression(
                pattern: "<DL\\b",
                options: [.caseInsensitive]
            )
            listClose = try NSRegularExpression(
                pattern: "</DL\\b",
                options: [.caseInsensitive]
            )
        }
    }

    static func parse(_ html: Data) throws -> BookmarkParseResult {
        guard html.count <= Limits.maxInputBytes else {
            throw BookmarkParseError.fileTooLarge
        }
        // Netscape exports are UTF-8; fall back to Latin-1 so a file with a
        // stray non-UTF-8 byte still parses instead of failing outright.
        let text = String(data: html, encoding: .utf8)
            ?? String(data: html, encoding: .isoLatin1)
            ?? ""

        var folderStack: [String] = []
        var pendingFolderName: String?
        var bookmarks: [ParsedBookmark] = []
        var skippedInvalid = 0
        var truncated = 0
        let regex = try RegexKit()

        for line in text.components(separatedBy: .newlines) {
            for event in events(in: line, regex: regex) {
                switch event {
                case let .folderHeader(name):
                    pendingFolderName = name
                case .listOpen:
                    folderStack.append(pendingFolderName ?? "")
                    pendingFolderName = nil
                case .listClose:
                    if !folderStack.isEmpty {
                        folderStack.removeLast()
                    }
                case let .bookmark(href, title, addDate):
                    guard let url = URL(string: href),
                          let scheme = url.scheme?.lowercased(),
                          scheme == "http" || scheme == "https"
                    else {
                        skippedInvalid += 1
                        continue
                    }
                    let entry = ParsedBookmark(
                        title: title,
                        url: url,
                        folderPath: folderStack.filter { !$0.isEmpty },
                        addedDate: date(fromEpoch: addDate)
                    )
                    if bookmarks.count < BookmarkLimits.maxEntries {
                        bookmarks.append(entry)
                    } else {
                        truncated += 1
                    }
                }
            }
        }

        return BookmarkParseResult(
            bookmarks: bookmarks,
            skippedInvalid: skippedInvalid,
            truncated: truncated
        )
    }

    // MARK: - Line scanning

    /// A Netscape line can carry several tags (`<DT><H3>F</H3><DL><p>`), so
    /// events are merged and applied in tag order within the line.
    private static func events(in line: String, regex: RegexKit) -> [LineEvent] {
        var timed: [(location: Int, event: LineEvent)] = []
        let wholeLine = NSRange(line.startIndex..., in: line)

        func capture(_ match: NSTextCheckingResult, _ group: Int) -> String? {
            guard let range = Range(match.range(at: group), in: line) else { return nil }
            return String(line[range])
        }

        for match in regex.folderHeader.matches(in: line, range: wholeLine) {
            let name = decodeEntities(capture(match, 1) ?? "")
            timed.append((match.range.location, .folderHeader(name)))
        }
        for match in regex.anchorTag.matches(in: line, range: wholeLine) {
            guard let tagRange = Range(match.range, in: line) else { continue }
            let tag = String(line[tagRange])
            let href = firstCapture(of: regex.href, in: tag)
            let addDate = firstCapture(of: regex.addDate, in: tag)
            let title = decodeEntities(capture(match, 1) ?? "")
            timed.append((
                match.range.location,
                .bookmark(href: decodeEntities(href ?? ""), title: title, addDate: addDate)
            ))
        }
        for match in regex.listOpen.matches(in: line, range: wholeLine) {
            timed.append((match.range.location, .listOpen))
        }
        for match in regex.listClose.matches(in: line, range: wholeLine) {
            timed.append((match.range.location, .listClose))
        }

        return timed
            .sorted { $0.location < $1.location }
            .map(\.event)
    }

    private static func firstCapture(of regex: NSRegularExpression, in text: String) -> String? {
        let whole = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: whole),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Decodes the entity set Safari exports (&amp; &lt; &gt; &quot; &#39;).
    /// `&amp;` is replaced last so doubly-escaped text ("&amp;lt;") survives.
    private static func decodeEntities(_ raw: String) -> String {
        var decoded = raw
        for (entity, replacement) in [
            ("lt", "<"), ("gt", ">"), ("quot", "\""), ("#39", "'"), ("amp", "&")
        ] {
            decoded = decoded.replacingOccurrences(of: "&\(entity);", with: replacement)
        }
        return decoded
    }

    private static func date(fromEpoch raw: String?) -> Date? {
        guard let raw, let seconds = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
