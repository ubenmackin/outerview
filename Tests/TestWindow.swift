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
        let window = UIWindow(frame: frame)
        window.addSubview(view)
        view.layoutIfNeeded()
        retained.append(window)
        return window
    }

    @discardableResult
    static func attach(_ viewController: UIViewController, frame: CGRect = defaultFrame) -> UIWindow {
        viewController.loadViewIfNeeded()
        let window = UIWindow(frame: frame)
        window.addSubview(viewController.view)
        viewController.view.layoutIfNeeded()
        retained.append(window)
        return window
    }
}
