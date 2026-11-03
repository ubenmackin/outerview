//
//  AddressBarView.swift
//  OuterView
//

import UIKit

/// Locked axis for a single pill pan gesture.
enum PillPanAxis: Sendable {
    case horizontal
    case vertical
}

/// Pan lifecycle carrying only the locked-axis value.
enum PillPanEvent: Sendable {
    case began
    case changed(translation: CGFloat, velocity: CGFloat)
    case ended(translation: CGFloat, velocity: CGFloat)
}

/// Single address pill with expanded (44 pt) and minified (30 pt)
/// presentations. Frames stay with the root controller; this view only
/// switches its arranged content via `setAddressState`.
@MainActor
final class AddressBarView: UIView, UIGestureRecognizerDelegate {
    nonisolated static let expandedHeight: CGFloat = 44
    nonisolated static let minifiedHeight: CGFloat = 30
    nonisolated static let placeholder = "Search or Enter Website"

    /// Max width of the minified capsule. The minified pill floats centered
    /// over content, never full width.
    nonisolated static let minifiedMaxWidth: CGFloat = 220
    nonisolated static let minifiedPillMinWidth: CGFloat = 96
    /// Padding added to the measured domain width: 16pt content edge padding
    /// (8pt each side) plus domain stack inset so text never touches the edge.
    nonisolated static let minifiedWidthPadding: CGFloat = 28
    nonisolated static let downloadRingSize: CGFloat = 24
    nonisolated static let horizontalCommitFraction: CGFloat = 0.40
    nonisolated static let verticalCommitFraction: CGFloat = 0.30
    /// First excursion past this locks the pan to the larger-magnitude axis.
    nonisolated static let axisLockThreshold: CGFloat = 8
    /// Reduced travel for clamped edge previews that have no incoming tab.
    nonisolated static let elasticFactor: CGFloat = 0.35
    /// Drag-to-overview card shrink per unit progress and corner radius.
    nonisolated static let overviewCardScaleShrink: CGFloat = 0.12
    nonisolated static let overviewCardRadius: CGFloat = 16

    /// Commits once the horizontal drag reaches 40% of content width.
    nonisolated static func shouldCommitHorizontal(translationX: CGFloat, width: CGFloat) -> Bool {
        guard width > 0 else { return false }
        return abs(translationX) >= width * horizontalCommitFraction
    }

    /// Commits once the upward drag reaches 30% of view height.
    nonisolated static func shouldCommitVertical(translationY: CGFloat, height: CGFloat) -> Bool {
        guard height > 0 else { return false }
        return -translationY >= height * verticalCommitFraction
    }

    /// Shared settle curve: faster flings settle sooner, clamped to 0.12–0.30 s.
    nonisolated static func settleDuration(remaining: CGFloat, velocity: CGFloat) -> TimeInterval {
        min(0.30, max(0.12, remaining / max(abs(velocity), 400)))
    }

    /// Locks to the axis with the larger absolute translation.
    nonisolated static func lockedAxis(tx: CGFloat, ty: CGFloat) -> PillPanAxis {
        abs(tx) >= abs(ty) ? .horizontal : .vertical
    }

    /// Pure geometry so tests and the frame owner share one source of truth.
    nonisolated static func heightForState(_ pill: PillState) -> CGFloat {
        pill == .minified ? minifiedHeight : expandedHeight
    }

    /// Minified capsule width for the given bounds width: a small centered
    /// capsule inset at least 16 pt per side and capped so it never spans
    /// the full width.
    nonisolated static func widthForBounds(_ boundsWidth: CGFloat) -> CGFloat {
        min(minifiedMaxWidth, max(0, boundsWidth - 32))
    }

    /// Host-only display text; scheme, path, and query never reach the pill.
    nonisolated static func displayHost(for url: URL?) -> String {
        HostFormatter.host(of: url)
    }

    /// Snug minified capsule width for the regular top toolbar when a URL is
    /// loaded; falls back to `minifiedMaxWidth` for empty placeholder tabs.
    func preferredMinifiedWidth(minimumWidth: CGFloat = AddressBarView.minifiedPillMinWidth) -> CGFloat {
        let host = Self.displayHost(for: currentURL)
        guard !host.isEmpty else {
            return Self.minifiedMaxWidth
        }
        if let cached = cachedMinifiedWidth,
           cachedMinifiedHost == host,
           cachedMinifiedMinimumWidth == minimumWidth
        {
            return cached
        }
        let fitting = domainStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
        let padded = ceil(fitting) + Self.minifiedWidthPadding
        let result = min(Self.minifiedMaxWidth, max(minimumWidth, padded))
        cachedMinifiedHost = host
        cachedMinifiedMinimumWidth = minimumWidth
        cachedMinifiedWidth = result
        return result
    }

    var onPageMenu: (() -> Void)?
    var pageMenuProvider: (() -> UIMenu)? {
        didSet {
            if let provider = pageMenuProvider {
                pageMenuButton.showsMenuAsPrimaryAction = true
                pageMenuButton.menu = UIMenu(children: [
                    UIDeferredMenuElement.uncached { completion in
                        completion(provider().children)
                    }
                ])
            } else {
                pageMenuButton.showsMenuAsPrimaryAction = false
                pageMenuButton.menu = nil
            }
        }
    }

    var onReload: (() -> Void)?
    var onStop: (() -> Void)?
    var onPillTap: (() -> Void)?
    var onDownloadsTap: (() -> Void)?
    var onHorizontalPan: ((PillPanEvent) -> Void)?
    var onVerticalPan: ((PillPanEvent) -> Void)?

    private var currentPill: PillState = .expanded
    private var currentURL: URL?
    private var isSecure = false
    private var isLoading = false
    private(set) var downloadProgress: Double?
    private var cachedMinifiedWidth: CGFloat?
    private var cachedMinifiedHost: String?
    private var cachedMinifiedMinimumWidth: CGFloat?
    private var lockedPanAxis: PillPanAxis?

    private let backgroundEffectView = UIVisualEffectView(effect: GlassEffect.make())
    private let contentStack = UIStackView()
    private let pageMenuButton = AccessibleButton(type: .system)
    private let domainContainer = DomainPillView()
    private let domainStack = UIStackView()
    private let lockImageView = UIImageView()
    private let domainLabel = UILabel()
    private let actionButton = AccessibleButton(type: .system)
    private let downloadsButton = AccessibleButton(type: .system)
    private let downloadRingView = DownloadProgressRingView()

    var domainAccessibilityLabel: String? {
        domainContainer.accessibilityLabel
    }

    var actionAccessibilityLabel: String? {
        actionButton.accessibilityLabel
    }

    var isDomainAccessibilityElement: Bool {
        domainContainer.isAccessibilityElement
    }

    var isDownloadRingVisible: Bool {
        !downloadsButton.isHidden
    }

    var isActionButtonVisible: Bool {
        !actionButton.isHidden
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = bounds.height / 2
        layer.cornerRadius = radius
        backgroundEffectView.layer.cornerRadius = radius
        backgroundEffectView.clipsToBounds = true
        if #available(iOS 26.0, *) {
            backgroundEffectView.cornerConfiguration = .capsule()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.heightForState(currentPill))
    }

    func setAddressState(_ state: ChromeState) {
        if state.pill == .editing {
            isHidden = true
            return
        }
        isHidden = false
        guard currentPill != state.pill else { return }
        currentPill = state.pill
        updatePresentation()
    }

    func configure(url: URL?, isSecure: Bool, isLoading: Bool) {
        currentURL = url
        self.isSecure = isSecure
        self.isLoading = isLoading
        cachedMinifiedWidth = nil
        updateDomain()
        updateAction()
    }

    func configureDownloadProgress(_ progress: Double?) {
        if let progress {
            downloadProgress = min(max(progress, 0), 1)
        } else {
            downloadProgress = nil
        }
        updateAction()
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .clear
        clipsToBounds = true

        backgroundEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundEffectView)
        NSLayoutConstraint.activate([
            backgroundEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundEffectView.topAnchor.constraint(equalTo: topAnchor),
            backgroundEffectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        pageMenuButton.setImage(
            UIImage(
                systemName: "list.bullet",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
            ),
            for: .normal
        )
        pageMenuButton.tintColor = .label
        pageMenuButton.accessibilityLabel = "Page menu"
        pageMenuButton.addAction(UIAction { [weak self] _ in self?.onPageMenu?() }, for: .touchUpInside)

        actionButton.tintColor = .label
        actionButton.accessibilityLabel = "Reload page"
        actionButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.isLoading {
                self.onStop?()
            } else {
                self.onReload?()
            }
        }, for: .touchUpInside)

        downloadsButton.tintColor = .label
        downloadsButton.accessibilityLabel = "Downloads"
        downloadsButton.isHidden = true
        downloadsButton.addAction(UIAction { [weak self] _ in self?.onDownloadsTap?() }, for: .touchUpInside)
        downloadRingView.translatesAutoresizingMaskIntoConstraints = false
        downloadRingView.isUserInteractionEnabled = false
        downloadsButton.addSubview(downloadRingView)
        NSLayoutConstraint.activate([
            downloadRingView.centerXAnchor.constraint(equalTo: downloadsButton.centerXAnchor),
            downloadRingView.centerYAnchor.constraint(equalTo: downloadsButton.centerYAnchor),
            downloadRingView.widthAnchor.constraint(equalToConstant: Self.downloadRingSize),
            downloadRingView.heightAnchor.constraint(equalToConstant: Self.downloadRingSize)
        ])

        lockImageView.image = UIImage(
            systemName: "lock.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        )
        lockImageView.tintColor = .secondaryLabel
        lockImageView.contentMode = .scaleAspectFit

        domainLabel.font = .preferredFont(forTextStyle: .subheadline)
        domainLabel.adjustsFontForContentSizeCategory = true
        domainLabel.textAlignment = .center
        domainLabel.lineBreakMode = .byTruncatingMiddle
        domainLabel.numberOfLines = 1

        domainContainer.isAccessibilityElement = true
        domainContainer.accessibilityTraits = .button
        domainContainer.accessibilityHint = "Double tap to edit address or search"
        domainContainer.onActivate = { [weak self] in
            self?.onPillTap?()
        }

        domainStack.axis = .horizontal
        domainStack.alignment = .center
        domainStack.spacing = 4
        domainStack.translatesAutoresizingMaskIntoConstraints = false
        domainStack.addArrangedSubview(lockImageView)
        domainStack.addArrangedSubview(domainLabel)
        domainContainer.addSubview(domainStack)
        NSLayoutConstraint.activate([
            domainStack.centerXAnchor.constraint(equalTo: domainContainer.centerXAnchor),
            domainStack.centerYAnchor.constraint(equalTo: domainContainer.centerYAnchor),
            domainStack.leadingAnchor.constraint(greaterThanOrEqualTo: domainContainer.leadingAnchor),
            domainStack.trailingAnchor.constraint(lessThanOrEqualTo: domainContainer.trailingAnchor)
        ])

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(pageMenuButton)
        contentStack.addArrangedSubview(domainContainer)
        contentStack.addArrangedSubview(actionButton)
        contentStack.addArrangedSubview(downloadsButton)
        addSubview(contentStack)
        // Edge case: 999 lets the domain container compress first so the
        // minified capsule hugs its text instead of breaking constraints.
        let stackLeading = contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        let stackTrailing = contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        stackLeading.priority = UILayoutPriority(999)
        stackTrailing.priority = UILayoutPriority(999)
        let menuWidth = pageMenuButton.widthAnchor.constraint(equalToConstant: 36)
        let actionWidth = actionButton.widthAnchor.constraint(equalToConstant: 36)
        let downloadsWidth = downloadsButton.widthAnchor.constraint(equalToConstant: 36)
        menuWidth.priority = UILayoutPriority(999)
        actionWidth.priority = UILayoutPriority(999)
        downloadsWidth.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            stackLeading,
            stackTrailing,
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            menuWidth,
            pageMenuButton.heightAnchor.constraint(equalToConstant: 36),
            actionWidth,
            actionButton.heightAnchor.constraint(equalToConstant: 36),
            downloadsWidth,
            downloadsButton.heightAnchor.constraint(equalToConstant: 36)
        ])
        domainContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        domainContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        setupPillGestures()

        observeContentSizeCategory()
        updatePresentation()
        updateDomain()
        updateAction()
    }

    private func setupPillGestures() {
        // Tap loses to the pan so a drag never fires a restore.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePillPan(_:)))
        pan.cancelsTouchesInView = true
        pan.delegate = self
        let tap = UITapGestureRecognizer(target: self, action: #selector(handlePillTap))
        tap.require(toFail: pan)
        addGestureRecognizer(pan)
        addGestureRecognizer(tap)
    }

    private func observeContentSizeCategory() {
        // Cached width depends on Dynamic Type; refresh it when it changes.
        _ = registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { @MainActor (owner: AddressBarView, previous: UITraitCollection) in
            if previous.preferredContentSizeCategory != owner.traitCollection.preferredContentSizeCategory {
                owner.cachedMinifiedWidth = nil
            }
        }
    }

    private func updatePresentation() {
        let isExpanded = currentPill == .expanded
        pageMenuButton.isHidden = !isExpanded
        updateAction()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func updateDomain() {
        let host = Self.displayHost(for: currentURL)
        if host.isEmpty {
            lockImageView.isHidden = true
            domainLabel.text = Self.placeholder
            domainLabel.textColor = .placeholderText
            domainContainer.accessibilityLabel = Self.placeholder
        } else {
            lockImageView.isHidden = !isSecure
            domainLabel.text = host
            domainLabel.textColor = .label
            let security = isSecure ? "secure" : "not secure"
            domainContainer.accessibilityLabel = "\(host), \(security)"
        }
    }

    private func updateAction() {
        let isExpanded = currentPill == .expanded
        if isLoading {
            actionButton.isHidden = !isExpanded
            downloadsButton.isHidden = true
            actionButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            actionButton.accessibilityLabel = "Stop loading"
            return
        }
        if let progress = downloadProgress {
            actionButton.isHidden = true
            downloadsButton.isHidden = !isExpanded
            downloadRingView.progress = progress
            return
        }
        actionButton.isHidden = !isExpanded
        downloadsButton.isHidden = true
        actionButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        actionButton.accessibilityLabel = "Reload page"
    }

    @objc private func handlePillTap() {
        onPillTap?()
    }

    @objc private func handlePillPan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            lockedPanAxis = nil
        case .changed:
            let translation = pan.translation(in: self)
            let velocity = pan.velocity(in: self)
            if let locked = lockedPanAxis {
                emitPanChanged(locked: locked, translation: translation, velocity: velocity)
            } else {
                // First excursion past the threshold locks to the larger
                // magnitude axis for the rest of the gesture.
                guard max(abs(translation.x), abs(translation.y)) > Self.axisLockThreshold else { return }
                let locked = Self.lockedAxis(tx: translation.x, ty: translation.y)
                lockedPanAxis = locked
                emitPanBeganThenChanged(locked: locked, translation: translation, velocity: velocity)
            }
        case .ended:
            guard let locked = lockedPanAxis else { return }
            lockedPanAxis = nil
            let translation = pan.translation(in: self)
            let velocity = pan.velocity(in: self)
            emitPanEnded(locked: locked, translation: translation, velocity: velocity)
        case .cancelled, .failed:
            // Zeroed end forces a bounce-back with no tab change.
            guard let locked = lockedPanAxis else { return }
            lockedPanAxis = nil
            emitPanEnded(locked: locked, translation: .zero, velocity: .zero)
        default:
            break
        }
    }

    private func emitPanChanged(locked: PillPanAxis, translation: CGPoint, velocity: CGPoint) {
        if locked == .horizontal {
            onHorizontalPan?(.changed(translation: translation.x, velocity: velocity.x))
        } else {
            onVerticalPan?(.changed(translation: translation.y, velocity: velocity.y))
        }
    }

    private func emitPanBeganThenChanged(locked: PillPanAxis, translation: CGPoint, velocity: CGPoint) {
        if locked == .horizontal {
            onHorizontalPan?(.began)
            onHorizontalPan?(.changed(translation: translation.x, velocity: velocity.x))
        } else {
            onVerticalPan?(.began)
            onVerticalPan?(.changed(translation: translation.y, velocity: velocity.y))
        }
    }

    private func emitPanEnded(locked: PillPanAxis, translation: CGPoint, velocity: CGPoint) {
        if locked == .horizontal {
            onHorizontalPan?(.ended(translation: translation.x, velocity: velocity.x))
        } else {
            onVerticalPan?(.ended(translation: translation.y, velocity: velocity.y))
        }
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

// MARK: - Accessible Helpers

@MainActor
final class AccessibleButton: UIButton {
    var minimumHitArea = CGSize(width: 44, height: 44)

    override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
        let dx = max(0, (minimumHitArea.width - bounds.width) / 2)
        let dy = max(0, (minimumHitArea.height - bounds.height) / 2)
        return bounds.insetBy(dx: -dx, dy: -dy).contains(point)
    }
}

@MainActor
final class DomainPillView: UIView {
    var onActivate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

@MainActor
final class DownloadProgressRingView: UIView {
    var progress: Double = 0 {
        didSet { setNeedsLayout() }
    }

    private let trackLayer = CAShapeLayer()
    private let valueLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    private func setupLayers() {
        isOpaque = false
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.tertiaryLabel.cgColor
        trackLayer.lineWidth = 2.5
        valueLayer.fillColor = UIColor.clear.cgColor
        valueLayer.strokeColor = UIColor.label.cgColor
        valueLayer.lineWidth = 2.5
        valueLayer.lineCap = .round
        layer.addSublayer(trackLayer)
        layer.addSublayer(valueLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = valueLayer.lineWidth / 2 + 1
        let rect = bounds.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return }
        let path = UIBezierPath(ovalIn: rect).cgPath
        trackLayer.frame = bounds
        trackLayer.path = path
        valueLayer.frame = bounds
        valueLayer.path = path
        let clamped = min(max(progress, 0), 1)
        valueLayer.strokeStart = 0
        valueLayer.strokeEnd = CGFloat(clamped)
        valueLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
    }
}
