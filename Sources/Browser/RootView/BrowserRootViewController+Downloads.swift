//
//  BrowserRootViewController+Downloads.swift
//  OuterView
//

import Combine
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
        downloadProgressCancellable = downloadsManager.$rows.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDownloadProgress()
            }
        }
    }

    func presentDownloadsSheet() {
        let hosting = UIHostingController(rootView: DownloadsSheetView(manager: downloadsManager))
        downloadsHosting?.view.removeFromSuperview()
        downloadsHosting?.removeFromParent()
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        downloadsContainer.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: downloadsContainer.leadingAnchor),
            hosting.view.topAnchor.constraint(equalTo: downloadsContainer.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: downloadsContainer.bottomAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: downloadsContainer.safeAreaLayoutGuide.trailingAnchor)
        ])
        hosting.didMove(toParent: self)
        downloadsHosting = hosting
        isDownloadsVisible = true
        downloadsContainer.isHidden = false
        bringChromeToFront()
        updateRailItems()
        applyRailViews(animated: true)
    }

    func dismissDownloadsSheet() {
        isDownloadsVisible = false
        downloadsContainer.isHidden = true
        downloadsHosting?.view.removeFromSuperview()
        downloadsHosting?.removeFromParent()
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
