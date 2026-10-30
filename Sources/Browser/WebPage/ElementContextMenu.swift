//
//  ElementContextMenu.swift
//  OuterView
//

import UIKit

/// Which element a WKWebView long-press resolved to.
enum ElementContextKind: Equatable {
    case link(url: URL)
    case image(url: URL)
}

/// Action set driving the element context menu. The menu builder stays pure,
/// so disconnected pages (and unit tests) can shape menus without a browser
/// root bundling in.
struct ElementContextActions {
    let openInNewTab: (URL) -> Void
    let addToReadingList: (URL) -> Void
    let copyLink: (URL) -> Void
    let share: (URL) -> Void
    let saveToPhotos: (URL) -> Void
    let copyImage: (URL) -> Void
}

/// Canonical owner of the element context menu item list. Links carry the
/// reading-list entry; images swap it for the Photos save actions.
@MainActor
enum ElementContextMenu {
    static func menu(for kind: ElementContextKind, actions: ElementContextActions) -> UIMenu {
        switch kind {
        case let .link(url):
            let openAction = UIAction(
                title: "Open in New Tab",
                image: UIImage(systemName: "plus.square.on.square")
            ) { _ in
                actions.openInNewTab(url)
            }
            let readingListAction = UIAction(
                title: "Add to Reading List",
                image: UIImage(systemName: "eyeglasses")
            ) { _ in
                actions.addToReadingList(url)
            }
            let copyAction = UIAction(
                title: "Copy Link",
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                actions.copyLink(url)
            }
            let shareAction = UIAction(
                title: "Share",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                actions.share(url)
            }
            return UIMenu(title: "", children: [
                openAction,
                readingListAction,
                copyAction,
                shareAction
            ])

        case let .image(url):
            let openAction = UIAction(
                title: "Open in New Tab",
                image: UIImage(systemName: "plus.square.on.square")
            ) { _ in
                actions.openInNewTab(url)
            }
            let saveAction = UIAction(
                title: "Save to Photos",
                image: UIImage(systemName: "square.and.arrow.down")
            ) { _ in
                actions.saveToPhotos(url)
            }
            let copyAction = UIAction(
                title: "Copy Image",
                image: UIImage(systemName: "photo.on.rectangle.angled")
            ) { _ in
                actions.copyImage(url)
            }
            let shareAction = UIAction(
                title: "Share",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                actions.share(url)
            }
            return UIMenu(title: "", children: [
                openAction,
                saveAction,
                copyAction,
                shareAction
            ])
        }
    }

    /// Maps the touched element into the kind enum. A link always wins over a
    /// co-located image so link-wrapped images behave like Safari links.
    /// `imageURLString` is the raw element source attribute; values lacking
    /// their own scheme resolve against `baseURL` (the containing page URL),
    /// which is where relative `src`/`srcset` candidates land.
    static func kind(
        linkURL: URL?,
        imageURLString: String?,
        baseURL: URL?
    ) -> ElementContextKind? {
        if let linkURL {
            guard URLNormalizer.isLoadable(linkURL) else { return nil }
            return .link(url: linkURL)
        }
        guard let imageURLString,
              let url = absoluteURL(for: imageURLString, baseURL: baseURL),
              URLNormalizer.isLoadable(url)
        else { return nil }
        return .image(url: url)
    }

    static func absoluteURL(for source: String, baseURL: URL?) -> URL? {
        guard !source.isEmpty, let parsed = URL(string: source) else { return nil }
        if let scheme = parsed.scheme, !scheme.isEmpty {
            guard URLNormalizer.isLoadable(parsed) else { return nil }
            return parsed
        }
        guard let baseURL,
              let resolved = URL(string: source, relativeTo: baseURL)?.absoluteURL,
              URLNormalizer.isLoadable(resolved)
        else { return nil }
        return resolved
    }
}
