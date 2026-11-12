// Settings — Preferences, iCloud sync status, plus clearance confirmation UI.

import os
import SwiftUI
import UniformTypeIdentifiers

/// Isolated so section slices read the MainActor view model directly.
@MainActor
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

    private static func formattedSyncDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    var body: some View {
        NavigationStack {
            settingsForm
        }
    }

    /// Single Form composition over small slices keeps each piece checkable.
    private var settingsForm: some View {
        Form {
            iCloudSyncSection
            searchEngineSection
            importSection
            privacySection
            tabsSection
            dataSection
            textZoomSection
            aboutSection
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
            clearHistoryActions
        } message: {
            Text("This removes all browsing history, cookies, and website data.")
        }
        .alert("Clear All Tabs?", isPresented: $showingClearTabsConfirm) {
            clearTabsActions
        } message: {
            Text("This closes all tabs and opens a single empty tab.")
        }
        .alert("Reset All Text Zooms?", isPresented: $showingResetZoomsConfirm) {
            resetZoomsActions
        } message: {
            Text(SettingsViewModel.resetAllTextZoomsConfirmationText)
        }
        .alert("Something Went Wrong", isPresented: actionErrorBinding) {
            actionErrorActions
        } message: {
            actionErrorMessage
        }
    }

    private var iCloudSyncSection: some View {
        Section {
            Toggle("Sync with iCloud", isOn: $viewModel.iCloudSyncEnabled)
            syncStatusRow
            lastSyncCaption
            if viewModel.showsSignInGuidance {
                Text(SettingsViewModel.iCloudSignInGuidanceText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("iCloud Sync")
        } footer: {
            Text(SettingsViewModel.iCloudSyncFooterText)
        }
    }

    private var syncStatusRow: some View {
        HStack {
            Text("Status")
            Spacer()
            Text(viewModel.syncStatusText)
                .foregroundStyle(.secondary)
        }
    }

    private var lastSyncCaption: some View {
        Text(lastSyncText)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var lastSyncText: String {
        viewModel.lastSyncDate.map { "Last synced \(Self.formattedSyncDate($0))" }
            ?? "Last synced never"
    }

    private var searchEngineSection: some View {
        Section("Search Engine") {
            Picker("Search Engine", selection: $viewModel.searchEngine) {
                ForEach(SearchEngine.allCases, id: \.self) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var importSection: some View {
        Section {
            Button("Import Bookmarks…") {
                showingImporter = true
            }
        } footer: {
            Text(SettingsViewModel.safariExportInstructions)
        }
    }

    private var privacySection: some View {
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
    }

    @ViewBuilder
    private var tabsSection: some View {
        if viewModel.isDuoOrPad {
            Section("Tabs") {
                Picker("Portrait Tab Bar Position", selection: $viewModel.portraitTabBarPosition) {
                    ForEach(PortraitTabBarPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
            }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            Button("Clear History and Website Data", role: .destructive) {
                showingClearHistoryConfirm = true
            }
            Button("Clear All Tabs", role: .destructive) {
                showingClearTabsConfirm = true
            }
        }
    }

    private var textZoomSection: some View {
        Section("Text Zoom") {
            Button("Reset All Text Zooms", role: .destructive) {
                showingResetZoomsConfirm = true
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Text(SettingsViewModel.appVersionLabel)
        }
    }

    /// Typed binding pins the error-alert overload so inference stays trivial.
    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { actionError != nil },
            set: {
                if !$0 {
                    actionError = nil
                }
            }
        )
    }

    private var actionErrorMessage: Text {
        Text(actionError ?? "")
    }

    private var actionErrorActions: some View {
        Button("OK", role: .cancel) {
            actionError = nil
        }
    }

    @ViewBuilder
    private var clearHistoryActions: some View {
        Button("Clear", role: .destructive) {
            confirmClearHistory()
        }
        Button("Cancel", role: .cancel) {}
    }

    @ViewBuilder
    private var clearTabsActions: some View {
        Button("Clear", role: .destructive) {
            confirmClearTabs()
        }
        Button("Cancel", role: .cancel) {}
    }

    @ViewBuilder
    private var resetZoomsActions: some View {
        Button("Reset", role: .destructive) {
            viewModel.resetAllTextZooms(siteZoomStore: siteZoomStore)
        }
        Button("Cancel", role: .cancel) {}
    }

    private func confirmClearHistory() {
        Task { @MainActor in
            do {
                try await viewModel.clearHistoryAndWebsiteData(historyStore: historyStore)
                onDidClearHistory?()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func confirmClearTabs() {
        do {
            try viewModel.clearAllTabs(tabStore: tabStore)
            onDidClearTabs?()
        } catch {
            actionError = error.localizedDescription
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
