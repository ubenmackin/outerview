//
//  BookmarkEditorView.swift
//  OuterView
//

import Observation
import SwiftUI

enum BookmarkEditorTarget {
    case addBookmark(title: String, url: URL)
    case editBookmark(Bookmark)
    case editFolder(BookmarkFolder)
}

@MainActor
@Observable
final class BookmarkEditorModel {
    var title: String
    var urlString: String
    var selectedLocation: BookmarkLocation
    var target: BookmarkEditorTarget
    var errorMessage: String?

    init(target: BookmarkEditorTarget) {
        self.target = target
        switch target {
        case let .addBookmark(initialTitle, initialURL):
            self.title = initialTitle
            self.urlString = initialURL.absoluteString
            self.selectedLocation = .root

        case let .editBookmark(bookmark):
            self.title = bookmark.title
            self.urlString = bookmark.url.absoluteString
            if bookmark.isFavorite {
                self.selectedLocation = .favorites
            } else if let fid = bookmark.folderId {
                self.selectedLocation = .folder(fid)
            } else {
                self.selectedLocation = .root
            }

        case let .editFolder(folder):
            self.title = folder.title
            self.urlString = ""
            if let pid = folder.parentId {
                self.selectedLocation = .folder(pid)
            } else {
                self.selectedLocation = .root
            }
        }
    }

    var isFolderMode: Bool {
        if case .editFolder = target {
            return true
        }
        return false
    }

    var isValid: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            return false
        }
        if isFolderMode {
            return true
        }

        guard let parsed = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return URLNormalizer.isLoadable(parsed)
    }

    func save(bookmarkStore: BookmarkStore) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        switch target {
        case let .addBookmark(_, originalUrl):
            let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? originalUrl
            switch selectedLocation {
            case .favorites:
                try bookmarkStore.upsertFavorite(url: url, title: trimmedTitle)
            case .root:
                try bookmarkStore.add(title: trimmedTitle, url: url, isFavorite: false, folderId: nil)
            case let .folder(folderId):
                try bookmarkStore.add(title: trimmedTitle, url: url, isFavorite: false, folderId: folderId)
            }

        case let .editBookmark(bookmark):
            guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            try bookmarkStore.updateBookmark(
                id: bookmark.id,
                title: trimmedTitle,
                url: url,
                location: selectedLocation
            )

        case let .editFolder(folder):
            let parentId: UUID? = switch selectedLocation {
            case let .folder(id):
                id
            default:
                nil
            }
            try bookmarkStore.updateFolder(id: folder.id, title: trimmedTitle, parentId: parentId)
        }
    }
}

@MainActor
struct BookmarkEditorView: View {
    @Bindable var model: BookmarkEditorModel
    let bookmarkStore: BookmarkStore
    var inlineCommands = false
    var onCancel: (() -> Void)?
    var onSave: (() -> Void)?

    @State private var locationOptions: [BookmarkLocationOption] = []

    private var navigationTitle: String {
        switch model.target {
        case .addBookmark:
            "Add Bookmark"
        case .editBookmark:
            "Edit Bookmark"
        case .editFolder:
            "Edit Folder"
        }
    }

    private var selectedLocationTitle: String {
        locationOptions.first { $0.location == model.selectedLocation }?.title ?? "Bookmarks"
    }

    var showsInlineCancel: Bool {
        inlineCommands
    }

    var showsInlineSave: Bool {
        inlineCommands
    }

    func performInlineCancel() {
        onCancel?()
    }

    func performInlineSave() {
        onSave?()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $model.title)
                        .autocorrectionDisabled()

                    if !model.isFolderMode {
                        TextField("Address", text: $model.urlString)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section("Location") {
                    NavigationLink {
                        locationPickerList
                    } label: {
                        HStack {
                            Image(systemName: iconForLocation(model.selectedLocation))
                                .foregroundStyle(model.selectedLocation == .favorites ? .yellow : .blue)
                            Text(selectedLocationTitle)
                        }
                    }
                }

                if let errorMessage = model.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if inlineCommands {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            performInlineCancel()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            performInlineSave()
                        }
                    }
                }
            }
            .onAppear(perform: loadLocationOptions)
        }
    }

    private var locationPickerList: some View {
        List {
            ForEach(locationOptions) { option in
                Button {
                    model.selectedLocation = option.location
                } label: {
                    HStack {
                        if option.depth > 0 {
                            Spacer()
                                .frame(width: CGFloat(option.depth * 20))
                        }
                        Image(systemName: option.iconSystemName)
                            .foregroundStyle(option.location == .favorites ? .yellow : .blue)
                        Text(option.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if model.selectedLocation == option.location {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(model.selectedLocation == option.location ? [.isSelected] : [])
                .accessibilityValue(model.selectedLocation == option.location ? "Selected" : "")
            }
        }
        .navigationTitle("Location")
    }

    private func iconForLocation(_ location: BookmarkLocation) -> String {
        switch location {
        case .favorites:
            "star.fill"
        case .root:
            "book.fill"
        case .folder:
            "folder.fill"
        }
    }

    private func loadLocationOptions() {
        let allFolders = bookmarkStore.fetchFolders(parentId: nil) + allDescendantFolders()
        let uniqueFolders = Dictionary(grouping: allFolders, by: \.id).compactMap(\.value.first)

        if case let .editFolder(folder) = model.target {
            locationOptions = BookmarkLocationTree.optionsForFolder(
                folderId: folder.id,
                folders: uniqueFolders
            )
        } else {
            locationOptions = BookmarkLocationTree.optionsForBookmark(folders: uniqueFolders)
        }
    }

    private func allDescendantFolders() -> [BookmarkFolder] {
        var results: [BookmarkFolder] = []
        var queue = bookmarkStore.fetchFolders(parentId: nil)
        var visited = Set<UUID>()
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if visited.contains(next.id) {
                continue
            }
            visited.insert(next.id)
            results.append(next)
            let children = bookmarkStore.fetchFolders(parentId: next.id)
            queue.append(contentsOf: children)
        }
        return results
    }
}
