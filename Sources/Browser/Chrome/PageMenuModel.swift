// Chrome — Safari page-menu state plus toggle labels.

import Foundation

/// Pure state model for the Safari-style address bar page menu.
struct PageMenuModel: Equatable, Sendable {
    let canGoBack: Bool
    let canGoForward: Bool
    let canReload: Bool
    let canShare: Bool
    let canSave: Bool
    let canFind: Bool
    let isFavorite: Bool
    let canAddToReadingList: Bool
    let isInReadingList: Bool
    let isReaderActive: Bool
    let isReaderAvailable: Bool
    let textZoom: Double
    let canOpenDownloads: Bool
    let isDesktopMode: Bool
    let canToggleDesktopMode: Bool
    let canPrint: Bool
    /// PDF export writes page content to a file, so private scope disables it
    /// even though printing (which keeps content in the print pipeline) remains.
    let canSavePDF: Bool
    let canEditWebsiteSettings: Bool

    init(
        url: URL?,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        isFavorite: Bool = false,
        canAddToReadingList: Bool = false,
        isInReadingList: Bool = false,
        isReaderActive: Bool = false,
        isReaderAvailable: Bool = false,
        textZoom: Double = 1.0,
        canOpenDownloads: Bool = false,
        isDesktopMode: Bool = false,
        canToggleDesktopMode: Bool = false,
        canPrint: Bool = true,
        isPrivateScope: Bool = false,
        canEditWebsiteSettings: Bool = false
    ) {
        let hasLoadableURL: Bool = if let url {
            URLNormalizer.isLoadable(url)
        } else {
            false
        }
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.canReload = hasLoadableURL
        self.canShare = hasLoadableURL
        // Private scope never persists: save rows stay disabled even with a
        // loadable page, so no store write is reachable from the menu.
        self.canSave = hasLoadableURL && !isPrivateScope
        self.canFind = hasLoadableURL
        self.isFavorite = isFavorite
        self.canAddToReadingList = canAddToReadingList && !isPrivateScope
        self.isInReadingList = isInReadingList
        self.isReaderActive = isReaderActive
        self.isReaderAvailable = isReaderAvailable
        self.textZoom = textZoom
        self.canOpenDownloads = canOpenDownloads
        self.isDesktopMode = isDesktopMode
        self.canToggleDesktopMode = canToggleDesktopMode && hasLoadableURL
        // Print stays disabled without a loadable URL even if requested.
        let printable = canPrint && hasLoadableURL
        self.canPrint = printable
        self.canSavePDF = printable && !isPrivateScope
        self.canEditWebsiteSettings = canEditWebsiteSettings && hasLoadableURL
    }

    /// Toggle label for the reading-list row, flipping with membership.
    var readingListTitle: String {
        isInReadingList ? "Remove from Reading List" : "Add to Reading List"
    }

    /// Toggle label for the desktop mode row, flipping with active mode.
    var desktopModeTitle: String {
        isDesktopMode ? "Request Mobile Website" : "Request Desktop Website"
    }

    /// Toggle label for the reader row, flipping with reader state.
    var readerTitle: String {
        isReaderActive ? "Hide Reader" : "Show Reader"
    }

    /// The reader row is only offered when the active page can provide it.
    var showsReaderItem: Bool {
        isReaderAvailable
    }
}
