//
//  TestWindow.swift
//  OuterView
//

import UIKit

/// Anchors detached views to a dummy window so table layout stays quiet.
///
/// A table that lays out while detached logs a hierarchy warning; adding
/// the host to a window keeps `view.window` non-nil without changing layout.
@MainActor
enum TestWindow {
    static let defaultFrame = CGRect(x: 0, y: 0, width: 466, height: 678)

    private static var retained: [UIWindow] = []

    @discardableResult
    static func attach(_ view: UIView, frame: CGRect = defaultFrame) -> UIWindow {
        let window = makeWindow(frame: frame)
        window.addSubview(view)
        view.layoutIfNeeded()
        retained.append(window)
        return window
    }

    @discardableResult
    static func attach(_ viewController: UIViewController, frame: CGRect = defaultFrame) -> UIWindow {
        viewController.loadViewIfNeeded()
        let window = makeWindow(frame: frame)
        window.addSubview(viewController.view)
        viewController.view.layoutIfNeeded()
        retained.append(window)
        return window
    }

    private static func makeWindow(frame: CGRect) -> UIWindow {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            preconditionFailure("TestWindow requires a connected UIWindowScene from the test host.")
        }
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        return window
    }
}
