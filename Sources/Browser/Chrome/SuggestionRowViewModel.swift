// Chrome — Suggestion row content for address editor lists.
import Foundation

/// Testable row content for one `Suggestion`, independent of table cells.
struct SuggestionRowViewModel: Hashable, Sendable {
    let systemImageName: String
    let primary: String
    let secondary: String

    static func make(for suggestion: Suggestion, engine: SearchEngine) -> SuggestionRowViewModel {
        switch suggestion.kind {
        case let .site(title, url, isFavorite):
            let (primary, host) = displayHostAndTitle(title: title, url: url)
            return SuggestionRowViewModel(
                systemImageName: isFavorite ? "star.fill" : "globe",
                primary: primary,
                secondary: host
            )
        case let .openTab(title, url, _):
            let (primary, host) = displayHostAndTitle(title: title, url: url)
            return SuggestionRowViewModel(
                systemImageName: "square.on.square",
                primary: primary,
                secondary: "Switch to Tab • \(host)"
            )
        case let .googleSuggest(query):
            return SuggestionRowViewModel(
                systemImageName: "magnifyingglass",
                primary: query,
                secondary: "\(engine.displayName) Suggestions"
            )
        case let .search(query):
            return SuggestionRowViewModel(
                systemImageName: "magnifyingglass",
                primary: query,
                secondary: "Search \(engine.displayName)"
            )
        case let .onPageFind(term):
            return SuggestionRowViewModel(
                systemImageName: "text.magnifyingglass",
                primary: "Find \"\(term)\"",
                secondary: "On This Page"
            )
        }
    }

    private static func displayHostAndTitle(title: String, url: URL) -> (primary: String, host: String) {
        let rawHost = HostFormatter.host(of: url)
        let host = rawHost.isEmpty ? url.absoluteString : rawHost
        let primary = HostFormatter.displayTitle(url: url, title: title)
        return (primary, host)
    }
}
