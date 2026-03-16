import AppKit

protocol AuroraWebViewNavigationDelegate: AnyObject {
    func webView(_ webView: AuroraWebView, didUpdateURL url: String?)
    func webView(_ webView: AuroraWebView, didUpdateTitle title: String?)
    func webView(_ webView: AuroraWebView, didUpdateLoading isLoading: Bool)
    func webView(_ webView: AuroraWebView, didUpdateProgress progress: Double)
    func webView(_ webView: AuroraWebView, didUpdateCanGoBack canGoBack: Bool)
    func webView(_ webView: AuroraWebView, didUpdateCanGoForward canGoForward: Bool)
}

final class AuroraWebView: NSView {
    private var wkViewPtr: UnsafeMutableRawPointer?
    private var wkView: NSView?
    private var pageRef: WKPageRef?
    private var pollTimer: Timer?

    /// Whether we have a valid C API page ref (may be nil if WKWebView SPI doesn't expose it)
    private var hasPageRef: Bool { pageRef != nil }

    weak var navigationDelegate: AuroraWebViewNavigationDelegate?

    // Observable page state
    @objc dynamic var currentURL: String?
    @objc dynamic var currentTitle: String?
    @objc dynamic var isPageLoading: Bool = false
    @objc dynamic var estimatedProgress: Double = 0.0
    @objc dynamic var canGoBack: Bool = false
    @objc dynamic var canGoForward: Bool = false

    init(contextRef: WKContextRef) {
        super.init(frame: .zero)

        wkViewPtr = aurora_view_create_with_context(contextRef)

        guard let wkViewPtr else {
            NSLog("[AuroraWebView] Failed to create WKWebView")
            return
        }

        // Try to get C API page ref (may be nil on some macOS versions)
        pageRef = aurora_view_get_page(wkViewPtr)
        if pageRef == nil {
            NSLog("[AuroraWebView] No WKPageRef available, using ObjC view methods")
        }

        // The wkViewPtr is a retained NSView* — bridge it back
        let view = Unmanaged<NSView>.fromOpaque(wkViewPtr).takeRetainedValue()
        view.autoresizingMask = [.width, .height]
        view.frame = bounds
        addSubview(view)
        wkView = view

        startPollingState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pollTimer?.invalidate()
    }

    override func layout() {
        super.layout()
        wkView?.frame = bounds
    }

    // MARK: - Public API

    func load(url: URL) {
        let urlString = url.absoluteString
        if let pageRef {
            aurora_page_load_url(pageRef, urlString)
        } else if let ptr = viewPtr {
            aurora_view_load_url(ptr, urlString)
        }
    }

    func loadHTML(_ html: String, baseURL: String? = nil) {
        if let pageRef {
            aurora_page_load_html(pageRef, html, baseURL)
        } else if let ptr = viewPtr {
            aurora_view_load_html_string(ptr, html, baseURL)
        }
    }

    func goBack() {
        if let pageRef {
            aurora_page_go_back(pageRef)
        } else if let ptr = viewPtr {
            aurora_view_go_back(ptr)
        }
    }

    func goForward() {
        if let pageRef {
            aurora_page_go_forward(pageRef)
        } else if let ptr = viewPtr {
            aurora_view_go_forward(ptr)
        }
    }

    func reload() {
        if let pageRef {
            aurora_page_reload(pageRef)
        } else if let ptr = viewPtr {
            aurora_view_reload(ptr)
        }
    }

    func stopLoading() {
        if let pageRef {
            aurora_page_stop_loading(pageRef)
        } else if let ptr = viewPtr {
            aurora_view_stop_loading(ptr)
        }
    }

    // MARK: - Inspector

    func showInspector() {
        if let pageRef {
            aurora_inspector_show(pageRef)
        } else if let ptr = viewPtr {
            aurora_view_inspector_show(ptr)
        }
    }

    func closeInspector() {
        if let pageRef {
            aurora_inspector_close(pageRef)
        } else if let ptr = viewPtr {
            aurora_view_inspector_close(ptr)
        }
    }

    func attachInspector() {
        if let pageRef {
            aurora_inspector_attach(pageRef)
        } else if let ptr = viewPtr {
            aurora_view_inspector_attach(ptr)
        }
    }

    func detachInspector() {
        if let pageRef {
            aurora_inspector_detach(pageRef)
        } else if let ptr = viewPtr {
            aurora_view_inspector_detach(ptr)
        }
    }

    func toggleInspector() {
        let visible: Bool
        if let pageRef {
            visible = aurora_inspector_is_visible(pageRef)
        } else if let ptr = viewPtr {
            visible = aurora_view_inspector_is_visible(ptr)
        } else {
            return
        }

        if visible {
            closeInspector()
        } else {
            showInspector()
        }
    }

    // MARK: - Private

    /// Get a non-owning pointer to the underlying WKWebView for ObjC bridge calls
    private var viewPtr: UnsafeMutableRawPointer? {
        guard let wkView else { return nil }
        return Unmanaged.passUnretained(wkView).toOpaque()
    }

    // MARK: - State Polling

    private func startPollingState() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.pollPageState()
        }
    }

    private func pollPageState() {
        guard let ptr = viewPtr else { return }

        // Use ObjC view methods for state (works regardless of WKPageRef availability)
        let newURL: String? = {
            guard let cStr = aurora_view_get_url(ptr) else { return nil }
            let str = String(cString: cStr)
            free(UnsafeMutableRawPointer(mutating: cStr))
            return str
        }()

        let newTitle: String? = {
            guard let cStr = aurora_view_get_title(ptr) else { return nil }
            let str = String(cString: cStr)
            free(UnsafeMutableRawPointer(mutating: cStr))
            return str
        }()

        let newProgress = aurora_view_get_estimated_progress(ptr)
        let newIsLoading = aurora_view_is_loading(ptr)
        let newCanGoBack = aurora_view_can_go_back(ptr)
        let newCanGoForward = aurora_view_can_go_forward(ptr)

        if newURL != currentURL {
            currentURL = newURL
            navigationDelegate?.webView(self, didUpdateURL: newURL)
        }
        if newTitle != currentTitle {
            currentTitle = newTitle
            navigationDelegate?.webView(self, didUpdateTitle: newTitle)
        }
        if newIsLoading != isPageLoading {
            isPageLoading = newIsLoading
            navigationDelegate?.webView(self, didUpdateLoading: newIsLoading)
        }
        if newProgress != estimatedProgress {
            estimatedProgress = newProgress
            navigationDelegate?.webView(self, didUpdateProgress: newProgress)
        }
        if newCanGoBack != canGoBack {
            canGoBack = newCanGoBack
            navigationDelegate?.webView(self, didUpdateCanGoBack: newCanGoBack)
        }
        if newCanGoForward != canGoForward {
            canGoForward = newCanGoForward
            navigationDelegate?.webView(self, didUpdateCanGoForward: newCanGoForward)
        }
    }
}
