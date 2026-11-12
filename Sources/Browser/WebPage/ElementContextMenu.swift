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
    let openLink: (URL) -> Void
    let openInNewTab: (URL) -> Void
    let tabGroups: [TabGroup]
    let openInTabGroup: (URL, TabGroup) -> Void
    let openInNewTabGroup: (URL, String) -> Void
    let downloadLinkedFile: (URL) -> Void
    let addToReadingList: (URL) -> Void
    let copyLink: (URL) -> Void
    let share: (URL) -> Void
    let saveToPhotos: (URL) -> Void
    let copyImage: (URL) -> Void

    init(
        openLink: @escaping (URL) -> Void = { _ in },
        openInNewTab: @escaping (URL) -> Void,
        tabGroups: [TabGroup] = [],
        openInTabGroup: @escaping (URL, TabGroup) -> Void = { _, _ in },
        openInNewTabGroup: @escaping (URL, String) -> Void = { _, _ in },
        downloadLinkedFile: @escaping (URL) -> Void = { _ in },
        addToReadingList: @escaping (URL) -> Void,
        copyLink: @escaping (URL) -> Void,
        share: @escaping (URL) -> Void,
        saveToPhotos: @escaping (URL) -> Void,
        copyImage: @escaping (URL) -> Void
    ) {
        self.openLink = openLink
        self.openInNewTab = openInNewTab
        self.tabGroups = tabGroups
        self.openInTabGroup = openInTabGroup
        self.openInNewTabGroup = openInNewTabGroup
        self.downloadLinkedFile = downloadLinkedFile
        self.addToReadingList = addToReadingList
        self.copyLink = copyLink
        self.share = share
        self.saveToPhotos = saveToPhotos
        self.copyImage = copyImage
    }
}

/// Canonical owner of the element context menu item list. Links carry the
/// reading-list entry; images swap it for the Photos save actions.
@MainActor
enum ElementContextMenu {
    static func menu(for kind: ElementContextKind, actions: ElementContextActions) -> UIMenu {
        switch kind {
        case let .link(url):
            let openAction = UIAction(
                title: "Open",
                image: UIImage(systemName: "safari")
            ) { _ in
                actions.openLink(url)
            }
            let backgroundAction = UIAction(
                title: "Open in Background",
                image: UIImage(systemName: "plus.square.on.square")
            ) { _ in
                actions.openInNewTab(url)
            }
            let tabGroupMenu = makeTabGroupSubmenu(url: url, actions: actions)
            let downloadAction = UIAction(
                title: "Download Linked File",
                image: UIImage(systemName: "arrow.down.circle")
            ) { _ in
                actions.downloadLinkedFile(url)
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
                title: "Share…",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                actions.share(url)
            }
            return UIMenu(title: "", children: [
                openAction,
                backgroundAction,
                tabGroupMenu,
                downloadAction,
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

    private static func makeTabGroupSubmenu(url: URL, actions: ElementContextActions) -> UIMenu {
        var children: [UIMenuElement] = []
        let newGroupAction = UIAction(
            title: "New Tab Group",
            image: UIImage(systemName: "plus")
        ) { _ in
            actions.openInNewTabGroup(url, "New Tab Group")
        }
        children.append(newGroupAction)
        for group in actions.tabGroups {
            let groupAction = UIAction(
                title: group.name,
                image: UIImage(systemName: "square.on.square")
            ) { _ in
                actions.openInTabGroup(url, group)
            }
            children.append(groupAction)
        }
        return UIMenu(
            title: "Open in Tab Group",
            image: UIImage(systemName: "arrow.up.right.square"),
            children: children
        )
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
