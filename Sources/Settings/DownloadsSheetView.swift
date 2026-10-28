//
//  DownloadsSheetView.swift
//  OuterView
//

import SwiftUI
import UIKit

struct DownloadsSheetView: View {
    @ObservedObject var manager: DownloadsManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingFilesPicker = false

    init(manager: DownloadsManager) {
        self.manager = manager
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Open Files") {
                        showingFilesPicker = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingFilesPicker) {
                DownloadsFilesPicker(manager: manager)
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

private struct DownloadsFilesPicker: UIViewControllerRepresentable {
    let manager: DownloadsManager

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = manager.makeFilesPicker()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt _: [URL]) {
            controller.dismiss(animated: true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            controller.dismiss(animated: true)
        }
    }
}
