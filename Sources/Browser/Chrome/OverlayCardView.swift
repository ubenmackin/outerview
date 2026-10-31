//
//  OverlayCardView.swift
//  OuterView
//

import UIKit

// Shared Contract SHEET-FIT: regular card content insets 16 on all sides;
// dim is heavy blur with black 0.2 overlay; Library header shows trailing Done
// plus per-tab inline controls on regular only through callbacks onInlineAddFolder,
// onInlineToggleEdit, onInlineClearHistory, onInlineDelete, inlineMenu, and
// onDone/onInlineDone wired by the root to the existing rail handlers.

@MainActor
final class OverlayCardView: UIView, ChromePlacementDriven {
    nonisolated static let maxWidth: CGFloat = 560
    nonisolated static let cornerRadius: CGFloat = 16
    nonisolated static var dimAlpha: CGFloat {
        SheetDim.alpha
    }

    nonisolated static let contentPadding: CGFloat = 16

    var chromePlacement: ChromePlacement = .compact {
        didSet {
            if oldValue != chromePlacement {
                applyPlacement()
            }
        }
    }

    let dimView = UIView()
    let dimBlurView = UIVisualEffectView(effect: GlassEffect.make())
    let dimOverlayView = UIView()
    let cardView = UIView()
    private(set) var hostedContent: UIView?

    private(set) var compactConstraints: [NSLayoutConstraint] = []
    private(set) var regularConstraints: [NSLayoutConstraint] = []
    private var contentConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func applyPlacement() {
        let isRegular = chromePlacement == .regular
        NSLayoutConstraint.deactivate(isRegular ? compactConstraints : regularConstraints)
        NSLayoutConstraint.activate(isRegular ? regularConstraints : compactConstraints)
        dimView.isHidden = !isRegular
        cardView.layer.cornerRadius = isRegular ? Self.cornerRadius : 0
        updateContentPadding()
        setNeedsLayout()
    }

    func setContent(_ view: UIView) {
        if hostedContent === view, view.superview === cardView {
            updateContentPadding()
            return
        }
        clearContent()
        view.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(view)
        contentConstraints = [
            view.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            view.topAnchor.constraint(equalTo: cardView.topAnchor),
            view.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
        ]
        NSLayoutConstraint.activate(contentConstraints)
        hostedContent = view
        updateContentPadding()
    }

    func updateContentPadding() {
        let pad = chromePlacement == .regular ? Self.contentPadding : 0
        for constraint in contentConstraints {
            switch constraint.firstAttribute {
            case .leading, .top:
                constraint.constant = pad
            case .trailing, .bottom:
                constraint.constant = -pad
            default:
                break
            }
        }
    }

    func clearContent() {
        guard let hosted = hostedContent else { return }
        NSLayoutConstraint.deactivate(contentConstraints)
        hosted.removeFromSuperview()
        hostedContent = nil
        contentConstraints = []
    }

    private func setup() {
        backgroundColor = .clear

        dimView.translatesAutoresizingMaskIntoConstraints = false
        dimView.backgroundColor = .clear
        dimView.isHidden = true
        dimView.isUserInteractionEnabled = false
        addSubview(dimView)

        dimBlurView.translatesAutoresizingMaskIntoConstraints = false
        dimBlurView.isUserInteractionEnabled = false
        dimView.addSubview(dimBlurView)

        dimOverlayView.translatesAutoresizingMaskIntoConstraints = false
        dimOverlayView.backgroundColor = UIColor.black.withAlphaComponent(Self.dimAlpha)
        dimOverlayView.isUserInteractionEnabled = false
        dimView.addSubview(dimOverlayView)

        NSLayoutConstraint.activate([
            dimBlurView.leadingAnchor.constraint(equalTo: dimView.leadingAnchor),
            dimBlurView.trailingAnchor.constraint(equalTo: dimView.trailingAnchor),
            dimBlurView.topAnchor.constraint(equalTo: dimView.topAnchor),
            dimBlurView.bottomAnchor.constraint(equalTo: dimView.bottomAnchor),
            dimOverlayView.leadingAnchor.constraint(equalTo: dimView.leadingAnchor),
            dimOverlayView.trailingAnchor.constraint(equalTo: dimView.trailingAnchor),
            dimOverlayView.topAnchor.constraint(equalTo: dimView.topAnchor),
            dimOverlayView.bottomAnchor.constraint(equalTo: dimView.bottomAnchor)
        ])

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .systemBackground
        cardView.clipsToBounds = true
        cardView.layer.cornerRadius = 0
        addSubview(cardView)

        NSLayoutConstraint.activate([
            dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimView.topAnchor.constraint(equalTo: topAnchor),
            dimView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let compactLeading = cardView.leadingAnchor.constraint(equalTo: leadingAnchor)
        let compactTrailing = cardView.trailingAnchor.constraint(equalTo: trailingAnchor)
        let compactTop = cardView.topAnchor.constraint(equalTo: topAnchor)
        let compactBottom = cardView.bottomAnchor.constraint(equalTo: bottomAnchor)
        compactConstraints = [compactLeading, compactTrailing, compactTop, compactBottom]

        let centerX = cardView.centerXAnchor.constraint(equalTo: centerXAnchor)
        let centerY = cardView.centerYAnchor.constraint(equalTo: centerYAnchor)
        let widthCap = cardView.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxWidth)
        let widthMatch = cardView.widthAnchor.constraint(equalTo: widthAnchor, constant: -48)
        widthMatch.priority = .defaultHigh
        let heightMatch = cardView.heightAnchor.constraint(equalTo: heightAnchor, constant: -48)
        heightMatch.priority = .defaultHigh
        let minLeading = cardView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16)
        let maxTrailing = cardView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        let minTop = cardView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 16)
        let maxBottom = cardView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16)
        regularConstraints = [
            centerX, centerY, widthCap, widthMatch, heightMatch,
            minLeading, maxTrailing, minTop, maxBottom
        ]

        NSLayoutConstraint.activate(compactConstraints)
    }
}
