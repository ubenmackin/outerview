// Bookmarks — Canonical builder for bookmark folder context menus shared by Bookmarks and Start Page.

import UIKit

/// Action set driving the folder context menu on bookmarks and start page.
@MainActor
struct BookmarkFolderContextActions {
    let onOpenInNewTab: @MainActor (URL) -> Void
    let onOpenURLsInBackground: @MainActor ([URL]) -> Void
    let onOpenURLsInTabGroup: @MainActor ([URL], TabGroup) -> Void
    let onOpenURLsInNewTabGroup: @MainActor ([URL], String) -> Void
    let onRequestEdit: @MainActor (BookmarkFolder) -> Void
    let onDelete: @MainActor (BookmarkFolder) -> Void
    let presentNewTabGroupPrompt: @MainActor (_ defaultTitle: String, _ onSave: @MainActor @escaping (String) -> Void) -> Void
}

/// Canonical builder for bookmark folder context menus.
@MainActor
enum BookmarkFolderContextMenu {
    static func build(
        for folder: BookmarkFolder,
        urls: [URL],
        tabGroups: [TabGroup],
        actions: BookmarkFolderContextActions
    ) -> UIMenu {
        let hasBookmarks = !urls.isEmpty
        let openAction = UIAction(
            title: "Open",
            image: UIImage(systemName: "safari"),
            attributes: hasBookmarks ? [] : [.disabled]
        ) { _ in
            guard !urls.isEmpty else { return }
            for url in urls {
                actions.onOpenInNewTab(url)
            }
        }
        let openBackgroundAction = UIAction(
            title: "Open in Background",
            image: UIImage(systemName: "plus.square.on.square"),
            attributes: hasBookmarks ? [] : [.disabled]
        ) { _ in
            guard !urls.isEmpty else { return }
            actions.onOpenURLsInBackground(urls)
        }
        let tabGroupElement = folderTabGroupElement(
            for: folder,
            urls: urls,
            tabGroups: tabGroups,
            actions: actions
        )
        let editAction = UIAction(
            title: "Edit…",
            image: UIImage(systemName: "pencil")
        ) { _ in
            actions.onRequestEdit(folder)
        }
        let deleteAction = UIAction(
            title: "Delete",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { _ in
            actions.onDelete(folder)
        }
        return UIMenu(children: [openAction, openBackgroundAction, tabGroupElement, editAction, deleteAction])
    }

    private static func folderTabGroupElement(
        for folder: BookmarkFolder,
        urls: [URL],
        tabGroups: [TabGroup],
        actions: BookmarkFolderContextActions
    ) -> UIMenuElement {
        guard !urls.isEmpty else {
            return UIAction(
                title: "Open in Tab Group",
                image: UIImage(systemName: "square.grid.2x2"),
                attributes: [.disabled]
            ) { _ in }
        }
        var groupElements: [UIMenuElement] = []
        let newGroupAction = UIAction(
            title: "New Tab Group…",
            image: UIImage(systemName: "plus")
        ) { _ in
            guard !urls.isEmpty else { return }
            let prefill = String(folder.title.prefix(TabGroup.maxNameLength))
            actions.presentNewTabGroupPrompt(prefill) { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let name = String(trimmed.prefix(TabGroup.maxNameLength))
                actions.onOpenURLsInNewTabGroup(urls, name)
            }
        }
        groupElements.append(newGroupAction)
        let existingGroups = tabGroups.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        for group in existingGroups {
            let groupAction = UIAction(
                title: group.name,
                image: UIImage(systemName: "square.on.square")
            ) { _ in
                guard !urls.isEmpty else { return }
                actions.onOpenURLsInTabGroup(urls, group)
            }
            groupElements.append(groupAction)
        }
        return UIMenu(
            title: "Open in Tab Group",
            image: UIImage(systemName: "square.grid.2x2"),
            children: groupElements
        )
    }

    static func presentNewTabGroupAlert(
        from window: UIWindow?,
        defaultTitle: String,
        onSave: @MainActor @escaping (String) -> Void
    ) {
        guard let windowScene = window?.windowScene,
              let rootVC = windowScene.keyWindow?.rootViewController
              ?? window?.rootViewController
              ?? windowScene.windows.first(where: \.isKeyWindow)?.rootViewController
        else {
            return
        }
        var presenter = rootVC
        while let next = presenter.presentedViewController {
            presenter = next
        }
        let alert = UIAlertController(
            title: "New Tab Group",
            message: "Enter a name for this tab group.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Group Name"
            field.text = defaultTitle
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak alert] _ in
            guard let raw = alert?.textFields?.first?.text, !raw.isEmpty else { return }
            onSave(raw)
        })
        presenter.present(alert, animated: true)
    }
}
