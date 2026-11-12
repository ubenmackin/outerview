// WebPage — Long-press link preview card for element context menus.
import UIKit
import WebKit

@MainActor
public final class LinkPreviewViewController: UIViewController {
    public static let isPreviewHiddenDefaultsKey = "linkPreviewHidden"

    public static let expandedSize = CGSize(width: 360, height: 420)
    public static let shrunkSize = CGSize(width: 200, height: 230)
    public static let hiddenSize = CGSize(width: 340, height: 110)

    public let url: URL
    public let webViewConfiguration: WKWebViewConfiguration
    public var onOpen: ((URL) -> Void)?

    private let defaults: UserDefaults

    public private(set) var isPreviewHidden: Bool {
        didSet {
            defaults.set(isPreviewHidden, forKey: Self.isPreviewHiddenDefaultsKey)
            updatePreviewMode(animated: true)
        }
    }

    public private(set) var isShrunk = false

    private let headerView = UIView()
    private let domainLabel = UILabel()
    private let hidePreviewButton = UIButton(type: .system)
    private let showPreviewButton = UIButton(type: .system)
    private let separatorView = UIView()

    private let previewContainer = UIView()
    private(set) var webView: WKWebView?
    private var hasLoadedPreview = false

    private let hiddenContainer = UIView()
    private let hiddenDomainLabel = UILabel()
    private let hiddenURLLabel = UILabel()

    public init(
        url: URL,
        configuration: WKWebViewConfiguration = WKWebViewConfiguration(),
        defaults: UserDefaults = .standard,
        onOpen: ((URL) -> Void)? = nil
    ) {
        self.url = url
        self.webViewConfiguration = configuration
        self.defaults = defaults
        self.onOpen = onOpen
        self.isPreviewHidden = defaults.bool(forKey: Self.isPreviewHiddenDefaultsKey)
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = isPreviewHidden ? Self.hiddenSize : Self.expandedSize
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.clipsToBounds = true

        setupHeader()
        setupHiddenContainer()
        setupPreviewContainer()
        setupGestures()

        updatePreviewMode(animated: false)
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = .secondarySystemBackground
        view.addSubview(headerView)

        let host = HostFormatter.host(of: url)
        domainLabel.translatesAutoresizingMaskIntoConstraints = false
        domainLabel.text = host.isEmpty ? url.host ?? "" : host
        domainLabel.font = .preferredFont(forTextStyle: .subheadline)
        domainLabel.textColor = .secondaryLabel
        headerView.addSubview(domainLabel)

        hidePreviewButton.translatesAutoresizingMaskIntoConstraints = false
        hidePreviewButton.setTitle("Hide preview", for: .normal)
        hidePreviewButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        hidePreviewButton.setTitleColor(.secondaryLabel, for: .normal)
        hidePreviewButton.addAction(UIAction { [weak self] _ in
            self?.setPreviewHidden(true)
        }, for: .touchUpInside)
        headerView.addSubview(hidePreviewButton)

        var showConfig = UIButton.Configuration.plain()
        showConfig.image = UIImage(systemName: "safari")
        showConfig.title = "Tap to show preview"
        showConfig.imagePadding = 6
        showConfig.baseForegroundColor = .secondaryLabel
        showConfig.contentInsets = .zero
        showPreviewButton.configuration = showConfig
        showPreviewButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        showPreviewButton.translatesAutoresizingMaskIntoConstraints = false
        showPreviewButton.addAction(UIAction { [weak self] _ in
            self?.setPreviewHidden(false)
        }, for: .touchUpInside)
        headerView.addSubview(showPreviewButton)

        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = .separator
        headerView.addSubview(separatorView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 38),

            domainLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 14),
            domainLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            domainLabel.trailingAnchor.constraint(lessThanOrEqualTo: hidePreviewButton.leadingAnchor, constant: -8),

            hidePreviewButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -14),
            hidePreviewButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            showPreviewButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 14),
            showPreviewButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            separatorView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    private func setupHiddenContainer() {
        hiddenContainer.translatesAutoresizingMaskIntoConstraints = false
        hiddenContainer.backgroundColor = .systemBackground
        view.addSubview(hiddenContainer)

        let host = HostFormatter.host(of: url)
        hiddenDomainLabel.translatesAutoresizingMaskIntoConstraints = false
        hiddenDomainLabel.text = host.isEmpty ? url.host ?? "" : host
        hiddenDomainLabel.font = .preferredFont(forTextStyle: .headline)
        hiddenDomainLabel.textColor = .label
        hiddenContainer.addSubview(hiddenDomainLabel)

        hiddenURLLabel.translatesAutoresizingMaskIntoConstraints = false
        hiddenURLLabel.text = url.absoluteString
        hiddenURLLabel.font = .preferredFont(forTextStyle: .footnote)
        hiddenURLLabel.textColor = .secondaryLabel
        hiddenURLLabel.numberOfLines = 2
        hiddenURLLabel.lineBreakMode = .byCharWrapping
        hiddenContainer.addSubview(hiddenURLLabel)

        NSLayoutConstraint.activate([
            hiddenContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            hiddenContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hiddenContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hiddenContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            hiddenDomainLabel.topAnchor.constraint(equalTo: hiddenContainer.topAnchor, constant: 12),
            hiddenDomainLabel.leadingAnchor.constraint(equalTo: hiddenContainer.leadingAnchor, constant: 16),
            hiddenDomainLabel.trailingAnchor.constraint(equalTo: hiddenContainer.trailingAnchor, constant: -16),

            hiddenURLLabel.topAnchor.constraint(equalTo: hiddenDomainLabel.bottomAnchor, constant: 4),
            hiddenURLLabel.leadingAnchor.constraint(equalTo: hiddenContainer.leadingAnchor, constant: 16),
            hiddenURLLabel.trailingAnchor.constraint(equalTo: hiddenContainer.trailingAnchor, constant: -16)
        ])
    }

    private func setupPreviewContainer() {
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewContainer)

        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupGestures() {
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDown.direction = .down
        view.addGestureRecognizer(swipeDown)

        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp))
        swipeUp.direction = .up
        view.addGestureRecognizer(swipeUp)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)
    }

    public func setPreviewHidden(_ hidden: Bool) {
        guard isPreviewHidden != hidden else { return }
        isPreviewHidden = hidden
    }

    public func shrink() {
        guard !isPreviewHidden, !isShrunk else { return }
        isShrunk = true
        preferredContentSize = Self.shrunkSize
        UIView.animate(withDuration: 0.25) {
            self.previewContainer.transform = CGAffineTransform(scaleX: Self.shrunkSize.width / Self.expandedSize.width, y: Self.shrunkSize.height / Self.expandedSize.height)
        }
    }

    public func expand() {
        guard !isPreviewHidden, isShrunk else { return }
        isShrunk = false
        preferredContentSize = Self.expandedSize
        UIView.animate(withDuration: 0.25) {
            self.previewContainer.transform = .identity
        }
    }

    @objc private func handleSwipeDown() {
        shrink()
    }

    @objc private func handleSwipeUp() {
        expand()
    }

    @objc private func handleTap() {
        onOpen?(url)
    }

    private func updatePreviewMode(animated: Bool) {
        let updateUI = { [weak self] in
            guard let self else { return }
            if self.isPreviewHidden {
                self.domainLabel.isHidden = true
                self.hidePreviewButton.isHidden = true
                self.showPreviewButton.isHidden = false
                self.hiddenContainer.isHidden = false
                self.previewContainer.isHidden = true
                self.isShrunk = false
                self.previewContainer.transform = .identity
                self.preferredContentSize = Self.hiddenSize
            } else {
                self.domainLabel.isHidden = false
                self.hidePreviewButton.isHidden = false
                self.showPreviewButton.isHidden = true
                self.hiddenContainer.isHidden = true
                self.previewContainer.isHidden = false
                self.preferredContentSize = self.isShrunk ? Self.shrunkSize : Self.expandedSize
                self.ensureWebViewLoaded()
            }
        }

        if animated {
            UIView.animate(withDuration: 0.2, animations: updateUI)
        } else {
            updateUI()
        }
    }

    private func ensureWebViewLoaded() {
        guard webView == nil else { return }
        let wv = WKWebView(frame: .zero, configuration: webViewConfiguration)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.scrollView.isScrollEnabled = false
        wv.isUserInteractionEnabled = false
        previewContainer.addSubview(wv)

        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            wv.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor)
        ])

        webView = wv
        wv.load(URLRequest(url: url))
    }
}
