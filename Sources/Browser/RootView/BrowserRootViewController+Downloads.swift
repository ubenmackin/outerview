//
//  BrowserRootViewController+Downloads.swift
//  OuterView
//

import os
import SwiftUI
import UIKit

extension BrowserRootViewController {
    // MARK: - Downloads sheet

    func setupDownloads() {
        downloadsContainer.translatesAutoresizingMaskIntoConstraints = false
        downloadsContainer.backgroundColor = .systemBackground
        downloadsContainer.isHidden = true
        view.addSubview(downloadsContainer)
        NSLayoutConstraint.activate([
            downloadsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            downloadsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            downloadsContainer.topAnchor.constraint(equalTo: view.topAnchor),
            downloadsContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func updateDownloadProgress() {
        pillView.configureDownloadProgress(downloadsManager.overallProgress)
    }

    func subscribeToDownloadProgress() {
        downloadsManager.onProgressChange = { [weak self] in
            self?.updateDownloadProgress()
        }
    }

    func presentDownloadsSheet() {
        let sheet = DownloadsSheetView(
            manager: downloadsManager,
            inlineCommands: chromePlacement == .regular,
            onDone: { [weak self] in self?.dismissDownloadsSheet() }
        )
        let hosting = UIHostingController(rootView: sheet)
        presentOverlay(downloadsOverlay, newHosting: hosting, currentHosting: downloadsHosting, container: downloadsContainer)
        downloadsHosting = hosting
        isDownloadsVisible = true
        bringChromeToFront()
        updateRailItems()
        applyRailViews(animated: true)
    }

    func dismissDownloadsSheet() {
        isDownloadsVisible = false
        dismissOverlay(downloadsOverlay, hosting: downloadsHosting, container: downloadsContainer)
        downloadsHosting = nil
        updateRailItems()
        applyRailViews(animated: true)
    }

    func presentDownloadsFilesPicker() {
        // The folder can disappear when the user clears it from Files, so recreate
        // it before exporting to keep the picker URL valid.
        do {
            try FileManager.default.createDirectory(
                at: downloadsManager.directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Downloads")
                .error("createDirectory failed: \(error.localizedDescription, privacy: .public)")
        }
        let picker = downloadsManager.makeFilesPicker()
        presentedDownloadsPicker = picker
        present(picker, animated: true)
    }

    func presentDownloadsFromMenu() {
        presentDownloadsSheet()
    }
}
