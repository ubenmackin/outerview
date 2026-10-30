//
//  SheetCardOverlayView.swift
//  OuterView
//

import UIKit

@MainActor
final class SheetCardOverlayView: UIView {
    nonisolated static let cornerRadius: CGFloat = 16
    nonisolated static let outerMargin: CGFloat = 8
    nonisolated static let grabberTopReserve: CGFloat = 24
    nonisolated static let dimAlpha: CGFloat = 0.4

    nonisolated static func cardFrame(bounds: CGRect, safeArea: UIEdgeInsets) -> CGRect {
        let leading = outerMargin
        let trailing = bounds.width - SideRailView.systemColumnWidth(safeAreaRight: safeArea.right) - outerMargin
        let top = safeArea.top + outerMargin
        let bottom = bounds.height - safeArea.bottom - outerMargin
        return CGRect(
            x: leading,
            y: top,
            width: max(0, trailing - leading),
            height: max(0, bottom - top)
        )
    }

    let dimView = UIView()
    let cardView = UIView()
    let grabberView = UIView()
    private weak var contentView: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setContent(_ view: UIView) {
        if contentView === view {
            return
        }
        contentView?.removeFromSuperview()
        contentView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            view.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Self.grabberTopReserve),
            view.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
        ])
        cardView.bringSubviewToFront(grabberView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimView.frame = bounds
        cardView.frame = Self.cardFrame(bounds: bounds, safeArea: safeAreaInsets)
        let grabberSize = CGSize(width: 36, height: 5)
        grabberView.frame = CGRect(
            x: (cardView.bounds.width - grabberSize.width) / 2,
            y: (Self.grabberTopReserve - grabberSize.height) / 2,
            width: grabberSize.width,
            height: grabberSize.height
        )
    }

    override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
        cardView.frame.contains(point)
    }

    private func setup() {
        backgroundColor = .clear
        isOpaque = false

        dimView.backgroundColor = .black
        dimView.alpha = Self.dimAlpha
        dimView.isUserInteractionEnabled = false
        addSubview(dimView)

        cardView.backgroundColor = .systemBackground
        cardView.layer.cornerRadius = Self.cornerRadius
        cardView.clipsToBounds = true
        addSubview(cardView)

        grabberView.backgroundColor = .systemGray3
        grabberView.layer.cornerRadius = 2.5
        grabberView.isUserInteractionEnabled = false
        cardView.addSubview(grabberView)
    }
}
