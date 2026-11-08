// Settings — Preferences, tabs position picker, and clearance confirmation UI.

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
    var inlineCommands = false
    var onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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
        siteZoomStore: SiteZoomStore = SiteZoomStore(),
        inlineCommands: Bool = false,
        onDone: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.bookmarkStore = bookmarkStore
        self.historyStore = historyStore
        self.tabStore = tabStore
        self.siteZoomStore = siteZoomStore
        self.inlineCommands = inlineCommands
        self.onDone = onDone
    }

    init(
        database: OuterViewDatabase,
        viewModel: SettingsViewModel = SettingsViewModel(),
        siteZoomStore: SiteZoomStore = SiteZoomStore(),
        inlineCommands: Bool = false,
        onDone: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.bookmarkStore = BookmarkStore(database: database)
        self.historyStore = HistoryStore(database: database)
        self.tabStore = TabStore(database: database)
        self.siteZoomStore = siteZoomStore
        self.inlineCommands = inlineCommands
        self.onDone = onDone
    }

    var showsInlineDone: Bool {
        inlineCommands
    }

    func performInlineDone() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
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

                Section("Privacy & Security") {
                    Toggle("Face ID for Private Tabs", isOn: $viewModel.requireBiometricsForPrivateTabs)
                    Toggle("Block Trackers & Ads", isOn: $viewModel.blockTrackersAndAds)
                }
                .onChange(of: viewModel.blockTrackersAndAds) { _, enabled in
                    // Live toggle: root applies rules to shared plus live controllers with no restart.
                    NotificationCenter.default.post(
                        name: .outerViewContentBlockerChanged,
                        object: nil,
                        userInfo: ["enabled": enabled]
                    )
                }

                if viewModel.isDuoOrPad {
                    Section("Tabs") {
                        Picker("Portrait Tab Bar Position", selection: $viewModel.portraitTabBarPosition) {
                            ForEach(PortraitTabBarPosition.allCases) { position in
                                Text(position.displayName).tag(position)
                            }
                        }
                    }
                }

                Section("Data") {
                    Button("Clear History and Website Data", role: .destructive) {
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
            .onAppear {
                viewModel.refreshDuoOrPad()
            }
            .onChange(of: horizontalSizeClass) { _, _ in
                viewModel.refreshDuoOrPad()
            }
            .onChange(of: verticalSizeClass) { _, _ in
                viewModel.refreshDuoOrPad()
            }
            .toolbar {
                if inlineCommands {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            performInlineDone()
                        }
                    }
                }
            }
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
            .alert("Clear History and Website Data?", isPresented: $showingClearHistoryConfirm) {
                Button("Clear", role: .destructive) {
                    Task { @MainActor in
                        do {
                            try await viewModel.clearHistoryAndWebsiteData(historyStore: historyStore)
                            onDidClearHistory?()
                        } catch {
                            actionError = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all browsing history, cookies, and website data.")
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
            guard let data = await BookmarkImportWorker.shared.readFile(at: url) else {
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
