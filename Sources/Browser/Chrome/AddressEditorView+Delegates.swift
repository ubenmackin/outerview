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
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: SuggestionCell.reuseIdentifier,
            for: indexPath
        ) as? SuggestionCell else {
            return UITableViewCell(style: .default, reuseIdentifier: nil)
        }
        guard let suggestion = suggestion(at: indexPath) else { return cell }
        cell.configure(for: suggestion, engine: searchEngine, isPrivate: isPrivateMode)
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

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        let currentLength = (textField.text as NSString?)?.length ?? 0
        if string.isEmpty {
            clearInlineCompletionState()
        } else if range.location + range.length != currentLength {
            clearInlineCompletionState()
        }
        return true
    }

    func textFieldDidChangeSelection(_: UITextField) {
        didChangeFieldSelection()
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        textField.text = ""
        clearInlineCompletionState()
        clearInputError()
        isTypingMode = false
        updateRegularLeadingIcon()
        updateVisibleContent()
        onTextChanged?("")
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        clearInlineCompletionState()
        onSubmit?(textField.text ?? "")
        return true
    }
}
