//
//  BrowserRootViewController+Editor.swift
//  OuterView
//

import UIKit

extension BrowserRootViewController {
    // MARK: - Editor

    enum PillTapRoute: Sendable, Equatable { case restoreChrome, beginEditing }

    static func routePillTap(pill: PillState, isEditing: Bool) -> PillTapRoute? {
        if isEditing {
            return nil
        }
        switch pill {
        case .editing:
            return nil
        case .minified:
            return .restoreChrome
        case .expanded:
            return .beginEditing
        }
    }

    func handlePillTap() {
        guard let route = Self.routePillTap(pill: chromeController.state.pill, isEditing: isEditingAddress) else {
            return
        }
        switch route {
        case .restoreChrome:
            applyBrowsingResumed(animated: true)
        case .beginEditing:
            beginEditing()
        }
    }

    func beginEditing() {
        editorView.applyPlacement(for: chromePlacement)
        let engine = currentSearchEngine()
        configureEditor(text: editorInitialText(), engine: engine)
        if selectedTabID != nil, peekActivePage()?.snapshot.url != nil {
            showStartPageForActiveTab()
        }
        isEditingAddress = true
        applyEditBegan()
        editorView.reloadContent()
        cancelPendingSuggestions()
        bringChromeToFront()
        updateRailItems()
        applyRailViews(animated: true)
        activateEditor()
    }

    func endEditing(submitted: Bool) {
        cancelPendingSuggestions()
        deactivateEditor()
        applyEditEnded(submitted: submitted)
        isEditingAddress = false
        updateRailItems()
        applyRailViews(animated: true)
    }

    func submitAddressText(_ text: String) {
        let engine = currentSearchEngine()
        switch URLNormalizer.normalize(text, engine: engine) {
        case let .success(url):
            // Private tabs never persist: skip recent-search recording so
            // private queries leave no on-disk trace.
            if tabs.first(where: { $0.id == selectedTabID })?.isPrivate != true {
                do {
                    try recentSearchStore?.record(query: text)
                } catch {
                    logPersistenceError(error, operation: "recordSearch")
                }
            }
            clearEditorInputError()
            clearForcedStartPageForSelectedTab()
            loadActivePage(url)
            endEditing(submitted: true)
        case .failure(.empty):
            clearEditorInputError()
            endEditing(submitted: false)
        case let .failure(failure):
            showEditorInputError(Self.inputErrorMessage(for: failure))
        }
    }

    static func inputErrorMessage(for failure: URLNormalizer.NormalizerFailure) -> String {
        switch failure {
        case .empty:
            "Enter an address or search."
        case .tooLong:
            "That address is too long."
        case .invalidCharacters:
            "That address contains invalid characters."
        case let .unsupportedScheme(scheme):
            URLNormalizer.unsupportedSchemeMessage(scheme)
        case .malformed:
            "That address couldn’t be opened."
        }
    }

    func currentSearchEngine() -> SearchEngine {
        let stored = UserDefaults.standard.string(forKey: SettingsViewModel.searchEngineDefaultsKey)
        return stored.flatMap(SearchEngine.init(rawValue:)) ?? .google
    }

    func refreshSuggestions(for text: String) {
        scheduleSuggestionRefresh(for: text)
    }

    func openSuggestion(_ suggestion: Suggestion) {
        switch suggestion.kind {
        case let .site(_, url, _):
            // History and bookmark rows predate the allowlist; re-validate
            // before loading so a poisoned row surfaces an input error.
            guard URLNormalizer.isLoadable(url) else {
                showEditorInputError(
                    Self.inputErrorMessage(for: .unsupportedScheme(url.scheme?.lowercased() ?? "unknown"))
                )
                return
            }
            clearEditorInputError()
            clearForcedStartPageForSelectedTab()
            loadActivePage(url)
            endEditing(submitted: true)
        case let .openTab(_, _, tabID):
            selectTab(id: tabID)
            endEditing(submitted: true)
        case let .googleSuggest(query):
            submitAddressText(query)
        case let .search(query):
            submitAddressText(query)
        case let .onPageFind(term):
            let needle = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else {
                showEditorInputError("Enter text to find on page.")
                return
            }
            clearEditorInputError()
            clearForcedStartPageForSelectedTab()
            endEditing(submitted: true)
            refreshForActiveSnapshot()
            findInPage(needle)
        }
    }

    func findInPage(_ term: String) {
        beginFind(initialQuery: term)
    }

    // MARK: - Editor bridges

    func applyEditBegan() {
        let commands = chromeController.handle(.editBegan)
        applyCommands(commands, animated: true)
    }

    func applyEditEnded(submitted: Bool) {
        let commands = chromeController.handle(.editEnded(submitted: submitted))
        applyCommands(commands, animated: true)
    }

    func editorInitialText() -> String {
        activePage()?.snapshot.url?.absoluteString ?? ""
    }

    func configureEditor(text: String, engine: SearchEngine) {
        editorView.configure(text: text, suggestions: [], engine: engine)
    }

    func editorFieldText() -> String {
        editorView.fieldText
    }

    func activateEditor() {
        editorView.becomeFirstResponder()
    }

    func deactivateEditor() {
        editorView.resignFirstResponder()
    }

    func clearEditorInputError() {
        editorView.clearInputError()
    }

    func showEditorInputError(_ message: String) {
        editorView.showInputError(message)
    }

    func loadActivePage(_ url: URL) {
        // Rejected schemes funnel through load(_:), which surfaces the
        // navigation error instead of reaching the web view.
        activePage()?.load(url)
    }

    func openExternalURL(_ url: URL) {
        var targetURL = url
        if url.scheme?.lowercased() == "outerview" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryURL = components.queryItems?.first(where: { $0.name == "url" })?.value,
               let parsed = URL(string: queryURL)
            {
                targetURL = parsed
            } else {
                let fallbackHost = HostFormatter.host(of: url)
                if !fallbackHost.isEmpty {
                    let fullPath = fallbackHost + url.path()
                    if let parsed = URL(string: "https://" + fullPath) {
                        targetURL = parsed
                    }
                } else {
                    let raw = url.absoluteString.replacingOccurrences(of: "outerview://", with: "")
                    if let parsed = URL(string: "https://" + raw) {
                        targetURL = parsed
                    }
                }
            }
        }
        clearForcedStartPageForSelectedTab()
        loadActivePage(targetURL)
    }

    func cancelPendingSuggestions() {
        suggestionTask?.cancel()
    }

    func scheduleSuggestionRefresh(for text: String) {
        suggestionTask?.cancel()

        let query = text
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Empty input surfaces recent searches. Private mode stays
            // isolated so non-private queries never leak into private sessions.
            let activeIsPrivate = tabs.first(where: { $0.id == selectedTabID })?.isPrivate ?? false
            if activeIsPrivate {
                editorView.setSuggestions([])
                return
            }
            let recentQueries = (recentSearchStore?.fetchRecents() ?? []).map(\.query)
            if recentQueries.isEmpty {
                editorView.setSuggestions([])
            } else {
                let currentURL = peekActivePage()?.snapshot.url
                let emptySuggestions = SuggestionEngine.suggestions(
                    for: query,
                    currentURL: currentURL,
                    recentSearches: recentQueries
                )
                editorView.setSuggestions(emptySuggestions)
            }
            return
        }

        let currentURL = peekActivePage()?.snapshot.url
        let bookmarkSnapshots = (bookmarkStore?.fetchAll() ?? []).map {
            SuggestionBookmark(title: $0.title, url: $0.url, isFavorite: $0.isFavorite)
        }
        let historySnapshots = (historyStore?.fetchAll(limit: 200) ?? []).map {
            SuggestionHistoryItem(title: $0.title, url: $0.url, visitedAt: $0.visitedAt)
        }
        // Suggestions stay mode-isolated: only surface open tabs from the
        // active mode so private titles never leak into normal suggestions.
        let activeIsPrivate = tabs.first(where: { $0.id == selectedTabID })?.isPrivate ?? false
        let tabSnapshots = tabs.filter { $0.isPrivate == activeIsPrivate }.compactMap { tab -> SuggestionTab? in
            guard let url = tab.url else { return nil }
            return SuggestionTab(id: tab.id, title: tab.title ?? "", url: url)
        }

        // 1. Immediately surface local matches (tabs, history, bookmarks, search row) with ZERO latency
        let localSuggestions = SuggestionEngine.suggestions(
            for: query,
            currentURL: currentURL,
            googleSuggestions: [],
            tabs: tabSnapshots,
            bookmarks: bookmarkSnapshots,
            recents: historySnapshots
        )
        editorView.setSuggestions(localSuggestions)

        // 2. Debounced background fetch for per-engine remote suggestions
        let engine = currentSearchEngine()
        suggestionTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }

            let remoteSuggestions = await GoogleSuggestService.shared.fetchSuggestions(for: trimmed, engine: engine)
            guard !Task.isCancelled, !remoteSuggestions.isEmpty else { return }

            let mergedSuggestions = SuggestionEngine.suggestions(
                for: query,
                currentURL: currentURL,
                googleSuggestions: remoteSuggestions,
                tabs: tabSnapshots,
                bookmarks: bookmarkSnapshots,
                recents: historySnapshots
            )
            guard !Task.isCancelled else { return }
            self.editorView.setSuggestions(mergedSuggestions)
        }
    }
}
