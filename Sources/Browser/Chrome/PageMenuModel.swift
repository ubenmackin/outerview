//
//  PageMenuModel.swift
//  OuterView
//

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

    init(
        url: URL?,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        isFavorite: Bool = false
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
        self.canSave = hasLoadableURL
        self.canFind = hasLoadableURL
        self.isFavorite = isFavorite
    }
}
