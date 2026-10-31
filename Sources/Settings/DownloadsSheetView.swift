//
//  DownloadsSheetView.swift
//  OuterView
//

import SwiftUI

struct DownloadsSheetView: View {
    @ObservedObject var manager: DownloadsManager
    var inlineCommands = false
    var onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

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
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            performInlineDone()
                        }
                    }
                }
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
