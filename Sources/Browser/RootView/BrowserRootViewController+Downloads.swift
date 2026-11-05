//
//  BrowserRootViewController+Downloads.swift
//  OuterView
//

import os
import SwiftUI
import UIKit

extension BrowserRootViewController {
    // MARK: - Downloads sheet

    /// Single owner for the split: service owns transfers, manager owns rows.
    func wireDownloadSplit() {
        BackgroundDownloadService.shared.manager = downloadsManager
        BackgroundDownloadService.shared.adoptFallbackRows(into: downloadsManager)
        downloadsManager.backgroundService = BackgroundDownloadService.shared
    }

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
        let isPhone = interfaceMode == .nonDuoPhone
        let sheet = DownloadsSheetView(
            manager: downloadsManager,
            inlineCommands: chromePlacement == .regular || isPhone,
            onOpenFiles: { [weak self] in self?.presentDownloadsFilesPicker() },
            onClearAll: { [weak self] in self?.downloadsManager.deleteAll() },
            onDone: { [weak self] in self?.dismissDownloadsSheet() }
        )
        let hosting = UIHostingController(rootView: sheet)
        downloadsHosting = hosting
        isDownloadsVisible = true
        if isPhone {
            hosting.modalPresentationStyle = .pageSheet
            hosting.presentationController?.delegate = self
            if let sheetController = hosting.sheetPresentationController {
                sheetController.prefersGrabberVisible = true
            }
            if view.window != nil {
                present(hosting, animated: shouldAnimateModalSheets)
            }
        } else {
            presentOverlay(downloadsOverlay, newHosting: hosting, currentHosting: nil, container: downloadsContainer)
        }
        bringChromeToFront()
        updateRailItems()
        applyRailViews(animated: true)
    }

    func dismissDownloadsSheet() {
        isDownloadsVisible = false
        if let hosting = downloadsHosting {
            if hosting.presentingViewController != nil {
                hosting.dismiss(animated: shouldAnimateModalSheets)
            }
            dismissOverlay(downloadsOverlay, hosting: hosting, container: downloadsContainer)
            downloadsHosting = nil
        }
        updateRailItems()
        applyRailViews(animated: true)
    }

    /// Presented destructive prompt; tests drive confirm/cancel through it.
    var clearAllConfirmationAlert: UIAlertController? {
        var current: UIViewController? = self
        while let vc = current {
            if let alert = vc.presentedViewController as? UIAlertController,
               alert.title == "Clear All Downloads?"
            {
                return alert
            }
            current = vc.presentedViewController
        }
        return nil
    }

    /// Simulates tapping the prompt destructive button; needs the prompt visible.
    func confirmPresentedClearAllDownloads() {
        guard clearAllConfirmationAlert != nil else { return }
        downloadsManager.deleteAll()
        updateRailItems()
        clearAllConfirmationAlert?.dismiss(animated: false)
    }

    /// Simulates tapping the prompt cancel button; rows are never touched here.
    func cancelPresentedClearAllDownloads() {
        guard let alert = clearAllConfirmationAlert else { return }
        alert.dismiss(animated: false)
    }

    func promptClearAllDownloads() {
        var presenter: UIViewController = self
        while let next = presenter.presentedViewController {
            presenter = next
        }
        let sheet = UIAlertController(
            title: "Clear All Downloads?",
            message: "This deletes all downloads and their files.",
            preferredStyle: .actionSheet
        )
        sheet.view.accessibilityIdentifier = "ClearAllDownloadsConfirm"
        sheet.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
            self?.downloadsManager.deleteAll()
            self?.updateRailItems()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(sheet, animated: shouldAnimateModalSheets)
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
                .error("createDirectory failed: \(error.localizedDescription, privacy: .private)")
        }
        let picker = downloadsManager.makeFilesPicker()
        presentedDownloadsPicker = picker
        // Tests host no Files UI; recording the picker keeps the seam
        // observable without stalling the suite on a modal presentation.
        guard !AppEnvironment.isTestHost else { return }
        // A windowless presentation never appears; log instead of dropping silently.
        guard view.window != nil else {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Downloads")
                .error("presentDownloadsFilesPicker without window")
            assertionFailure("presentDownloadsFilesPicker without window")
            return
        }
        present(picker, animated: true)
    }

    func presentDownloadsFromMenu() {
        presentDownloadsSheet()
    }
}
