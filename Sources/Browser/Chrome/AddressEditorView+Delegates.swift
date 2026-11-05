// Chrome — Address editor table, collection, and text-field delegate conformance.

import UIKit

// MARK: - UITableViewDataSource, UITableViewDelegate

extension AddressEditorView: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in _: UITableView) -> Int {
        if !suggestionSections.isEmpty {
            return suggestionSections.count
        }
        return suggestions.isEmpty ? 0 : 1
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        if !suggestionSections.isEmpty {
            guard section < suggestionSections.count else { return 0 }
            return suggestionSections[section].items.count
        }
        return suggestions.count
    }

    func tableView(_: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard !suggestionSections.isEmpty, section < suggestionSections.count else { return nil }
        let headerView = UIView()
        headerView.backgroundColor = .clear

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = suggestionSections[section].title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        headerView.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -4)
        ])
        return headerView
    }

    func tableView(_: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard !suggestionSections.isEmpty, section < suggestionSections.count else { return 0 }
        return 32
    }

    private func suggestion(at indexPath: IndexPath) -> Suggestion? {
        if !suggestionSections.isEmpty {
            guard indexPath.section < suggestionSections.count,
                  indexPath.row < suggestionSections[indexPath.section].items.count
            else {
                return nil
            }
            return suggestionSections[indexPath.section].items[indexPath.row]
        }
        guard indexPath.row < suggestions.count else { return nil }
        return suggestions[indexPath.row]
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SuggestionCell", for: indexPath)
        guard let suggestion = suggestion(at: indexPath) else { return cell }
        let viewModel = SuggestionRowViewModel.make(for: suggestion, engine: searchEngine)
        var content = UIListContentConfiguration.subtitleCell()
        content.image = UIImage(systemName: viewModel.systemImageName)
        content.imageProperties.tintColor = .secondaryLabel
        content.text = viewModel.primary
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.textProperties.color = .label
        let isGoogleSuggest = if case .googleSuggest = suggestion.kind {
            true
        } else {
            false
        }
        if !isGoogleSuggest, !viewModel.secondary.isEmpty {
            content.secondaryText = viewModel.secondary
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
            content.secondaryTextProperties.color = .secondaryLabel
            content.textToSecondaryTextVerticalPadding = 2
        } else {
            content.secondaryText = nil
        }
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        cell.accessibilityTraits = .button
        cell.accessibilityHint = "Double tap to select suggestion"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let suggestion = suggestion(at: indexPath) else { return }
        onSelectSuggestion?(suggestion)
    }
}

// MARK: - UICollectionViewDataSource, UICollectionViewDelegate

extension AddressEditorView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        favorites.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: FavoriteTileCell.reuseIdentifier,
            for: indexPath
        ) as? FavoriteTileCell
        else {
            return UICollectionViewCell()
        }
        let bookmark = favorites[indexPath.item]
        cell.configure(with: bookmark)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let bookmark = favorites[indexPath.item]
        onSelectFavorite?(bookmark.url)
    }
}

// MARK: - UITextFieldDelegate

extension AddressEditorView: UITextFieldDelegate {
    func textFieldDidBeginEditing(_: UITextField) {
        updateVisibleContent()
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        textField.text = ""
        clearInputError()
        isTypingMode = false
        updateRegularLeadingIcon()
        updateVisibleContent()
        onTextChanged?("")
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onSubmit?(textField.text ?? "")
        return true
    }
}
