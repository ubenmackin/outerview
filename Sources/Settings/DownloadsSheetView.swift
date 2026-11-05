//
//  DownloadsSheetView.swift
//  OuterView
//

import SwiftUI

/// Reference gate so detached copies share one confirmation flag.
@MainActor
final class DownloadsClearAllGate: ObservableObject {
    @Published var isPresented = false
}

struct DownloadsSheetView: View {
    var manager: DownloadsManager
    var inlineCommands = false
    var onOpenFiles: (() -> Void)?
    var onClearAll: (() -> Void)?
    var onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var clearAllGate = DownloadsClearAllGate()

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

    var isShowingClearAllConfirm: Bool {
        clearAllGate.isPresented
    }

    /// Test tap on the toolbar trash; confirm still requires this flag.
    mutating func requestClearAllConfirmation() {
        clearAllGate.isPresented = true
    }

    /// Mirrors the dialog destructive button; inert without a prior request.
    mutating func confirmClearAll() {
        guard clearAllGate.isPresented else { return }
        clearAllGate.isPresented = false
        onClearAll?()
    }

    /// Mirrors the dialog cancel button; rows are never touched here.
    mutating func cancelClearAll() {
        clearAllGate.isPresented = false
    }

    var body: some View {
        NavigationStack {
            Group {
                if manager.rows.isEmpty {
                    ContentUnavailableView(
                        "No Downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("Files you download appear here.")
                    )
                } else {
                    List {
                        ForEach(manager.rows) { row in
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.name)
                                        .lineLimit(1)
                                    switch row.state {
                                    case .inProgress:
                                        ProgressView(value: row.progress)
                                    case .finished:
                                        Text(row.sizeLabel)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    case let .failed(reason):
                                        Text(reason ?? "Download failed")
                                            .font(.footnote)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(row.name), \(accessibilityStatus(for: row))")
                        }
                        .onDelete(perform: deleteRows)
                    }
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if inlineCommands {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 16) {
                            Button {
                                onOpenFiles?()
                            } label: {
                                Image(systemName: "folder")
                            }
                            .accessibilityLabel("Open Downloads Folder")

                            Button {
                                clearAllGate.isPresented = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(manager.rows.isEmpty)
                            .accessibilityLabel("Clear All Downloads")
                            .accessibilityIdentifier("ClearAllDownloadsTrash")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            performInlineDone()
                        }
                    }
                }
            }
            .confirmationDialog(
                "Clear All Downloads?",
                isPresented: $clearAllGate.isPresented,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    onClearAll?()
                }
                .accessibilityIdentifier("ConfirmClearAllDownloads")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("CancelClearAllDownloads")
            } message: {
                Text("This deletes all downloads and their files.")
            }
        }
    }

    private func deleteRows(at offsets: IndexSet) {
        for index in offsets {
            guard manager.rows.indices.contains(index) else { continue }
            manager.delete(id: manager.rows[index].id)
        }
    }

    private func accessibilityStatus(for row: DownloadRow) -> String {
        switch row.state {
        case .inProgress:
            "\(Int(row.progress * 100)) percent downloaded"
        case .finished:
            row.sizeLabel.isEmpty ? "finished" : row.sizeLabel
        case let .failed(reason):
            reason ?? "failed"
        }
    }
}
