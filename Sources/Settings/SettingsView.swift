//
//  SettingsView.swift
//  OuterView
//

import os
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    let bookmarkStore: BookmarkStore
    let historyStore: HistoryStore
    let tabStore: TabStore
    let siteZoomStore: SiteZoomStore
    var onDidClearHistory: (() -> Void)?
    var onDidClearTabs: (() -> Void)?

    @State private var showingImporter = false
    @State private var importSummary: ImportSummary?
    @State private var showingImportResult = false
    @State private var showingClearHistoryConfirm = false
    @State private var showingClearTabsConfirm = false
    @State private var showingResetZoomsConfirm = false
    @State private var actionError: String?

    init(
        viewModel: SettingsViewModel = SettingsViewModel(),
        bookmarkStore: BookmarkStore,
        historyStore: HistoryStore,
        tabStore: TabStore,
        siteZoomStore: SiteZoomStore = SiteZoomStore()
    ) {
        self.viewModel = viewModel
        self.bookmarkStore = bookmarkStore
        self.historyStore = historyStore
        self.tabStore = tabStore
        self.siteZoomStore = siteZoomStore
    }

    init(database: OuterViewDatabase, viewModel: SettingsViewModel = SettingsViewModel(), siteZoomStore: SiteZoomStore = SiteZoomStore()) {
        self.viewModel = viewModel
        self.bookmarkStore = BookmarkStore(database: database)
        self.historyStore = HistoryStore(database: database)
        self.tabStore = TabStore(database: database)
        self.siteZoomStore = siteZoomStore
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Search Engine") {
                    Picker("Search Engine", selection: $viewModel.searchEngine) {
                        ForEach(SearchEngine.allCases, id: \.self) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Section {
                    Button("Import Bookmarks…") {
                        showingImporter = true
                    }
                } footer: {
                    Text(SettingsViewModel.safariExportInstructions)
                }

                Section("Data") {
                    Button("Clear History", role: .destructive) {
                        showingClearHistoryConfirm = true
                    }
                    Button("Clear All Tabs", role: .destructive) {
                        showingClearTabsConfirm = true
                    }
                }

                Section("Text Zoom") {
                    Button("Reset All Text Zooms", role: .destructive) {
                        showingResetZoomsConfirm = true
                    }
                }

                Section("About") {
                    Text(SettingsViewModel.appVersionLabel)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingImporter) {
                BookmarksDocumentPicker(
                    onPick: handlePickedURL,
                    onCancel: { showingImporter = false }
                )
            }
            .alert("Import Complete", isPresented: $showingImportResult, presenting: importSummary) { _ in
                Button("OK", role: .cancel) {}
            } message: { summary in
                Text(SettingsViewModel.formattedSummary(summary))
            }
            .alert("Clear History?", isPresented: $showingClearHistoryConfirm) {
                Button("Clear", role: .destructive) {
                    do {
                        try viewModel.clearHistory(historyStore: historyStore)
                        onDidClearHistory?()
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all browsing history.")
            }
            .alert("Clear All Tabs?", isPresented: $showingClearTabsConfirm) {
                Button("Clear", role: .destructive) {
                    do {
                        try viewModel.clearAllTabs(tabStore: tabStore)
                        onDidClearTabs?()
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This closes all tabs and opens a single empty tab.")
            }
            .alert("Reset All Text Zooms?", isPresented: $showingResetZoomsConfirm) {
                Button("Reset", role: .destructive) {
                    viewModel.resetAllTextZooms(siteZoomStore: siteZoomStore)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(SettingsViewModel.resetAllTextZoomsConfirmationText)
            }
            .alert("Something Went Wrong", isPresented: Binding(
                get: { actionError != nil },
                set: {
                    if !$0 {
                        actionError = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    actionError = nil
                }
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    private func handlePickedURL(_ url: URL) {
        showingImporter = false
        Task { @MainActor in
            // File reads run detached so a large export never stalls the main thread.
            let data: Data? = await Task.detached(priority: .userInitiated) {
                do {
                    return try Data(contentsOf: url)
                } catch {
                    Logger(subsystem: "com.volcrypt.OuterView", category: "Settings")
                        .error("bookmarks file read failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }.value
            guard let data else {
                actionError = "Couldn’t read the exported bookmarks file."
                return
            }
            importSummary = await viewModel.importBookmarks(data, bookmarkStore: bookmarkStore)
            showingImportResult = true
        }
    }
}

private struct BookmarksDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // asCopy stages the file outside the sandbox, so Data(contentsOf:) needs no scope dance.
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.html], asCopy: true)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }

    func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
