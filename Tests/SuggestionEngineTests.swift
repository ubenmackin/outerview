//
//  SuggestionEngineTests.swift
//  OuterView
//

@testable import OuterView
import XCTest

final class SuggestionEngineTests: XCTestCase {
    private func bookmark(
        _ title: String,
        _ urlString: String,
        isFavorite: Bool = false
    ) -> SuggestionBookmark {
        SuggestionBookmark(title: title, url: url(urlString), isFavorite: isFavorite)
    }

    private func history(
        _ title: String,
        _ urlString: String,
        visitedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> SuggestionHistoryItem {
        SuggestionHistoryItem(title: title, url: url(urlString), visitedAt: visitedAt)
    }

    private func url(_ string: String) -> URL {
        guard let result = URL(string: string) else {
            XCTFail("invalid URL: \(string)")
            return URL(fileURLWithPath: "/")
        }
        return result
    }

    private func kinds(of suggestions: [Suggestion]) -> [SuggestionKind] {
        suggestions.map(\.kind)
    }

    func testEmptyQueryReturnsOnlySearchRow() {
        let results = SuggestionEngine.suggestions(
            for: "",
            currentURL: nil,
            bookmarks: [bookmark("Example", "https://example.com/")],
            recents: [history("Example", "https://example.com/")]
        )
        XCTAssertEqual(kinds(of: results), [.search(query: "")])
    }

    func testWhitespaceQueryReturnsOnlyTrailingRows() {
        let current = url("https://example.com/")
        let results = SuggestionEngine.suggestions(
            for: "   ",
            currentURL: current,
            bookmarks: [bookmark("Example", "https://example.com/")],
            recents: []
        )
        XCTAssertEqual(kinds(of: results), [.search(query: ""), .onPageFind(term: "")])
    }

    func testEmptyQueryWithRecentsIncludesTrailingRows() {
        let current = url("https://example.com/")
        let results = SuggestionEngine.suggestions(
            for: "",
            currentURL: current,
            recentSearches: ["apple", "banana"]
        )
        XCTAssertEqual(
            kinds(of: results),
            [
                .search(query: "apple"),
                .search(query: "banana"),
                .search(query: ""),
                .onPageFind(term: "")
            ]
        )
    }

    func testEmptyQueryWithRecentsRespectsCap() {
        let current = url("https://example.com/")
        let recents = (0 ..< 20).map { "query \($0)" }
        let results = SuggestionEngine.suggestions(
            for: "",
            currentURL: current,
            recentSearches: recents
        )
        XCTAssertEqual(results.count, 12)
        XCTAssertEqual(results.suffix(2).map(\.kind), [.search(query: ""), .onPageFind(term: "")])
    }

    func testFindRowAppearsOnlyWhenPageIsOpen() {
        let withoutPage = SuggestionEngine.suggestions(
            for: "example",
            currentURL: nil,
            bookmarks: [],
            recents: []
        )
        XCTAssertEqual(kinds(of: withoutPage), [.search(query: "example")])

        let current = url("https://example.com/")
        let withPage = SuggestionEngine.suggestions(
            for: "example",
            currentURL: current,
            bookmarks: [],
            recents: []
        )
        XCTAssertEqual(kinds(of: withPage), [.search(query: "example"), .onPageFind(term: "example")])
    }

    func testQueryIsTrimmedBeforeMatching() {
        let trimmed = SuggestionEngine.suggestions(
            for: "example",
            currentURL: nil,
            bookmarks: [bookmark("Example", "https://example.com/")],
            recents: []
        )
        let padded = SuggestionEngine.suggestions(
            for: "  example  ",
            currentURL: nil,
            bookmarks: [bookmark("Example", "https://example.com/")],
            recents: []
        )
        XCTAssertEqual(kinds(of: trimmed), kinds(of: padded))
    }

    func testExactHostMatchBeatsContainsOrdering() {
        let bookmarks = [
            bookmark("News Daily", "https://news.example.org/home"),
            bookmark("Example", "https://example.com/")
        ]
        let results = SuggestionEngine.suggestions(
            for: "example.com",
            currentURL: nil,
            bookmarks: bookmarks,
            recents: []
        )
        XCTAssertEqual(
            kinds(of: results),
            [
                .site(title: "Example", url: url("https://example.com/"), isFavorite: false),
                .search(query: "example.com")
            ]
        )
    }

    func testPrefixMatchingIsCaseInsensitive() throws {
        let results = SuggestionEngine.suggestions(
            for: "EXA",
            currentURL: nil,
            bookmarks: [bookmark("Example", "https://example.com/")],
            recents: []
        )
        XCTAssertEqual(results.count, 2)
        let first = try XCTUnwrap(results.first)
        guard case let .site(title, _, _) = first.kind else {
            XCTFail("expected site row first")
            return
        }
        XCTAssertEqual(title, "Example")
    }

    func testSchemelessPrefixMatchesDisplayForm() throws {
        let results = SuggestionEngine.suggestions(
            for: "example.com/pa",
            currentURL: nil,
            bookmarks: [bookmark("Example", "https://example.com/path")],
            recents: []
        )
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.last?.kind, .search(query: "example.com/pa"))
        let first = try XCTUnwrap(results.first)
        guard case .site = first.kind else {
            XCTFail("expected schemeless prefix site row")
            return
        }
    }

    func testContainsStageCapsAtFour() {
        let bookmarks = (0 ..< 6).map { bookmark("News \($0)", "https://example\($0).com/") }
        let results = SuggestionEngine.suggestions(
            for: "news",
            currentURL: nil,
            bookmarks: bookmarks,
            recents: []
        )
        XCTAssertEqual(results.count, 5)
        XCTAssertEqual(results.last?.kind, .search(query: "news"))
        XCTAssertEqual(
            results.prefix(4).map(\.kind),
            (0 ..< 4).map {
                SuggestionKind.site(
                    title: "News \($0)",
                    url: url("https://example\($0).com/"),
                    isFavorite: false
                )
            }
        )
    }

    func testExactMatchesAreNotRepeatedByContainsStage() {
        let bookmarks = [
            bookmark("Example", "https://example.com/", isFavorite: true),
            bookmark("Example News", "https://other.example.net/")
        ]
        let results = SuggestionEngine.suggestions(
            for: "example",
            currentURL: nil,
            bookmarks: bookmarks,
            recents: []
        )
        let siteRows = results.filter {
            if case .site = $0.kind {
                return true
            }
            return false
        }
        XCTAssertEqual(siteRows.count, 2)
        XCTAssertEqual(results.last?.kind, .search(query: "example"))
    }

    func testHistoryNewestFirstCappedAtFour() {
        let recents = (0 ..< 6).map {
            history(
                "Story \($0)",
                "https://history\($0).example.com/",
                visitedAt: Date(timeIntervalSince1970: TimeInterval($0))
            )
        }
        let results = SuggestionEngine.suggestions(
            for: "story",
            currentURL: nil,
            bookmarks: [],
            recents: recents
        )
        XCTAssertEqual(
            kinds(of: results),
            [
                .site(title: "Story 5", url: url("https://history5.example.com/"), isFavorite: false),
                .site(title: "Story 4", url: url("https://history4.example.com/"), isFavorite: false),
                .site(title: "Story 3", url: url("https://history3.example.com/"), isFavorite: false),
                .site(title: "Story 2", url: url("https://history2.example.com/"), isFavorite: false),
                .search(query: "story")
            ]
        )
    }

    func testHistoryTiesKeepInputOrder() {
        let moment = Date(timeIntervalSince1970: 500)
        let recents = [
            history("Alpha Note", "https://alpha.example.com/", visitedAt: moment),
            history("Alpha Page", "https://beta.example.com/", visitedAt: moment)
        ]
        let results = SuggestionEngine.suggestions(
            for: "alpha",
            currentURL: nil,
            bookmarks: [],
            recents: recents
        )
        XCTAssertEqual(
            kinds(of: results),
            [
                .site(title: "Alpha Note", url: url("https://alpha.example.com/"), isFavorite: false),
                .site(title: "Alpha Page", url: url("https://beta.example.com/"), isFavorite: false),
                .search(query: "alpha")
            ]
        )
    }

    func testPathOnlyQueryDoesNotMatchHistory() {
        let results = SuggestionEngine.suggestions(
            for: "/deep-path",
            currentURL: nil,
            bookmarks: [],
            recents: [history("Unrelated", "https://example.com/deep-path")]
        )
        XCTAssertEqual(kinds(of: results), [.search(query: "/deep-path")])
    }

    func testStageOrderIsBookmarksThenHistoryThenTrailing() {
        let bookmarks = [bookmark("Shop", "https://shop.example.com/")]
        let recents = [history("Shop Archive", "https://archive.example.org/")]
        let current = url("https://example.com/")
        let results = SuggestionEngine.suggestions(
            for: "shop",
            currentURL: current,
            bookmarks: bookmarks,
            recents: recents
        )
        XCTAssertEqual(
            kinds(of: results),
            [
                .site(title: "Shop", url: url("https://shop.example.com/"), isFavorite: false),
                .site(title: "Shop Archive", url: url("https://archive.example.org/"), isFavorite: false),
                .search(query: "shop"),
                .onPageFind(term: "shop")
            ]
        )
    }

    func testTotalCapReservesTrailingRows() {
        let bookmarks = (0 ..< 20).map { bookmark("Site \($0)", "https://example\($0).com/") }
        let withoutPage = SuggestionEngine.suggestions(
            for: "example",
            currentURL: nil,
            bookmarks: bookmarks,
            recents: []
        )
        XCTAssertEqual(withoutPage.count, 12)
        XCTAssertEqual(withoutPage.last?.kind, .search(query: "example"))

        let current = url("https://example.com/")
        let withPage = SuggestionEngine.suggestions(
            for: "example",
            currentURL: current,
            bookmarks: bookmarks,
            recents: []
        )
        XCTAssertEqual(withPage.count, 12)
        XCTAssertEqual(withPage.suffix(2).map(\.kind), [.search(query: "example"), .onPageFind(term: "example")])
    }

    func testFavoriteFlagSurvivesRanking() {
        let results = SuggestionEngine.suggestions(
            for: "example",
            currentURL: nil,
            bookmarks: [bookmark("Example", "https://example.com/", isFavorite: true)],
            recents: []
        )
        XCTAssertEqual(
            results.first?.kind,
            .site(title: "Example", url: url("https://example.com/"), isFavorite: true)
        )
    }

    func testOpenTabSuggestionsAppearFirst() {
        let tabID = UUID()
        let tabs = [SuggestionTab(id: tabID, title: "Apple News", url: url("https://apple.com/news"))]
        let results = SuggestionEngine.suggestions(
            for: "apple",
            currentURL: nil,
            googleSuggestions: ["apple store"],
            tabs: tabs,
            bookmarks: [bookmark("Apple", "https://apple.com")],
            recents: []
        )

        // First item should be the open tab
        XCTAssertEqual(
            results.first?.kind,
            .openTab(title: "Apple News", url: url("https://apple.com/news"), tabID: tabID)
        )
    }

    func testGoogleSuggestionsAppearInResults() {
        let results = SuggestionEngine.suggestions(
            for: "swift",
            currentURL: nil,
            googleSuggestions: ["swiftui tutorial", "swift language"],
            tabs: [],
            bookmarks: [],
            recents: []
        )

        let gKinds = results.filter {
            if case .googleSuggest = $0.kind {
                return true
            }
            return false
        }
        XCTAssertEqual(gKinds.count, 2)
    }

    func testGoogleSuggestServiceParsesSafariArrayOfArraysFormat() {
        let jsonString = """
        ["test",[["test","", [512,433,131]],["testosterone","",[512,433]],["test speed","",[512,433]]]]
        """
        let data = Data(jsonString.utf8)
        let suggestions = GoogleSuggestService.parseSuggestions(from: data, limit: 5)
        XCTAssertEqual(suggestions, ["test", "testosterone", "test speed"])
    }

    func testGoogleSuggestServiceParsesStringArrayFormat() {
        let jsonString = """
        ["test",["test","testosterone","test speed"]]
        """
        let data = Data(jsonString.utf8)
        let suggestions = GoogleSuggestService.parseSuggestions(from: data, limit: 5)
        XCTAssertEqual(suggestions, ["test", "testosterone", "test speed"])
    }

    func testSuggestionRowViewModelFormatting() {
        let googleSuggest = Suggestion(kind: .googleSuggest(query: "cool math games"))
        let vm = SuggestionRowViewModel.make(for: googleSuggest, engine: .google)
        XCTAssertEqual(vm.primary, "cool math games")
        XCTAssertEqual(vm.secondary, "Google Search")
        XCTAssertEqual(vm.systemImageName, "magnifyingglass")

        let tabID = UUID()
        let openTab = Suggestion(kind: .openTab(title: "Cool Math", url: url("https://coolmathgames.com"), tabID: tabID))
        let tabVM = SuggestionRowViewModel.make(for: openTab, engine: .google)
        XCTAssertEqual(tabVM.primary, "Cool Math")
        XCTAssertEqual(tabVM.secondary, "Switch to Tab • coolmathgames.com")
        XCTAssertEqual(tabVM.systemImageName, "square.on.square")
    }

    @MainActor
    func testAddressEditorViewSuggestionsRendering() {
        let editor = AddressEditorView(frame: CGRect(x: 0, y: 0, width: 360, height: 600))
        TestWindow.attach(editor)
        let sampleSuggestions = [
            Suggestion(kind: .googleSuggest(query: "cool math games")),
            Suggestion(kind: .search(query: "cool math games"))
        ]
        editor.configure(text: "cool math", suggestions: sampleSuggestions, engine: .google)
        XCTAssertEqual(editor.suggestions.count, 2)
    }
}
