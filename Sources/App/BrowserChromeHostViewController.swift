//
//  BrowserChromeHostViewController.swift
//  OuterView
//

import UIKit

@MainActor
final class BrowserChromeHostViewController: UIViewController {
    let browserRoot: BrowserRootViewController

    init(browserRoot: BrowserRootViewController) {
        self.browserRoot = browserRoot
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(browserRoot)
        browserRoot.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(browserRoot.view)
        NSLayoutConstraint.activate([
            browserRoot.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browserRoot.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            browserRoot.view.topAnchor.constraint(equalTo: view.topAnchor),
            browserRoot.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        browserRoot.didMove(toParent: self)
    }

    /// System queries the SwiftUI-provided root, so forward to the browser root.
    override var childForPreferredVerticalBarBehavior: UIViewController? {
        browserRoot
    }

    override var childForStatusBarHidden: UIViewController? {
        browserRoot
    }

    override var childForStatusBarStyle: UIViewController? {
        browserRoot
    }
}
