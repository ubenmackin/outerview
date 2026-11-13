// Bookmarks — Native page-sheet host for BookmarksLibraryView on regular width.

import UIKit

/// Presents `BookmarksLibraryView` inside a native `.pageSheet` on regular width
/// so UIKit supplies native dimming, swipe/tap dismissal, and full toolbar visibility behind it.
@MainActor
final class LibrarySheetViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    nonisolated static let preferredSheetCornerRadius: CGFloat = 32

    let libraryView: BookmarksLibraryView
    var onDidDismiss: (@MainActor () -> Void)?

    private var contentConstraints: [NSLayoutConstraint] = []

    init(libraryView: BookmarksLibraryView) {
        self.libraryView = libraryView
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
            sheet.preferredCornerRadius = Self.preferredSheetCornerRadius
        }
        presentationController?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        presentationController?.delegate = self
        if view.window != nil {
            attachLibraryViewIfNeeded()
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        attachLibraryViewIfNeeded()
    }

    func attachLibraryViewIfNeeded() {
        guard isViewLoaded else { return }
        if libraryView.superview === view, !contentConstraints.isEmpty {
            NSLayoutConstraint.activate(contentConstraints)
            libraryView.isHidden = false
            return
        }
        NSLayoutConstraint.deactivate(contentConstraints)
        libraryView.removeFromSuperview()
        libraryView.translatesAutoresizingMaskIntoConstraints = false
        libraryView.isHidden = false
        view.addSubview(libraryView)
        contentConstraints = [
            libraryView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            libraryView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            libraryView.topAnchor.constraint(equalTo: view.topAnchor),
            libraryView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]
        NSLayoutConstraint.activate(contentConstraints)
    }

    func detachLibraryView() {
        guard libraryView.superview === view else { return }
        NSLayoutConstraint.deactivate(contentConstraints)
        contentConstraints = []
        libraryView.removeFromSuperview()
    }

    func presentationControllerDidDismiss(_: UIPresentationController) {
        onDidDismiss?()
    }
}
