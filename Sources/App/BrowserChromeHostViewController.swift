// App — UIKit host that embeds the browser root and forwards system queries to it.

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
        // Inner-display captures run the regular-width chrome on the
        // compact-sized host window before first layout.
        let isInnerDisplayRun = CommandLine.arguments.contains("-OuterViewInnerDisplay")
            || CommandLine.arguments.contains("-OuterViewInnerPortrait")
            || CommandLine.arguments.contains("-OuterViewInnerLandscape")
        if isInnerDisplayRun {
            browserRoot.traitOverrides.horizontalSizeClass = .regular
        }
        browserRoot.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(browserRoot.view)
        NSLayoutConstraint.activate([
            browserRoot.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browserRoot.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            browserRoot.view.topAnchor.constraint(equalTo: view.topAnchor),
            browserRoot.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        browserRoot.didMove(toParent: self)
        if isInnerDisplayRun {
            browserRoot.applyStructuralLayout()
        }
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
