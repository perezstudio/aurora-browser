import SwiftUI
import AppKit

struct ActiveWebViewRepresentable: NSViewRepresentable {
    let activeTabID: UUID?

    func makeNSView(context: Context) -> AuroraWebViewContainer {
        let container = AuroraWebViewContainer()
        container.showWebView(for: activeTabID)
        return container
    }

    func updateNSView(_ nsView: AuroraWebViewContainer, context: Context) {
        nsView.showWebView(for: activeTabID)
    }

    static func dismantleNSView(_ nsView: AuroraWebViewContainer, coordinator: ()) {
        nsView.detachAllWebViews()
    }
}

// MARK: - Container NSView

/// Hosts all visited WebViews as hidden subviews.
/// Only the active tab's WebView is visible — switching tabs toggles isHidden.
/// The Tab model is the source of truth: Tab → Space → Profile determines
/// which WebKit context and data store a WebView is created with.
final class AuroraWebViewContainer: NSView {
    private var attachedWebViews: [UUID: AuroraWebView] = [:]
    private var currentTabID: UUID?

    private var tabClosedObserver: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        tabClosedObserver = NotificationCenter.default.addObserver(
            forName: .tabClosed, object: nil, queue: .main
        ) { [weak self] notification in
            guard let tabID = notification.object as? UUID else { return }
            self?.onTabClosed(tabID)
        }
    }

    deinit {
        if let observer = tabClosedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func onTabClosed(_ tabID: UUID) {
        if let view = attachedWebViews.removeValue(forKey: tabID) {
            view.removeFromSuperview()
        }
    }

    // MARK: - Show / Hide

    @MainActor
    func showWebView(for tabID: UUID?) {
        guard let tabID else {
            hideAll()
            currentTabID = nil
            return
        }

        // Check if the cached WebView was invalidated (profile reassignment
        // destroyed it in the pool). The pool is the source of truth.
        var needsRecreate = false
        if let cached = attachedWebViews[tabID],
           !WebViewPool.shared.webViewExists(for: tabID) {
            cached.removeFromSuperview()
            attachedWebViews.removeValue(forKey: tabID)
            needsRecreate = true
        }

        guard tabID != currentTabID || needsRecreate else { return }

        // Hide the previously visible WebView
        if let oldID = currentTabID, let oldView = attachedWebViews[oldID] {
            oldView.isHidden = true
        }

        currentTabID = tabID

        // Already attached and valid — just unhide
        if let existing = attachedWebViews[tabID] {
            existing.isHidden = false
            existing.frame = bounds
            return
        }

        // Resolve profile from the Tab's model relationships: Tab → Space → Profile
        guard let profileID = resolveProfileID(for: tabID) else { return }

        // Create WebView from pool with the correct profile context
        let webView = WebViewPool.shared.webView(for: tabID, profileID: profileID)
        webView.navigationDelegate = BrowserState.shared
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
        attachedWebViews[tabID] = webView

        if webView.currentURL == nil || webView.currentURL?.isEmpty == true {
            loadPersistedURL(for: tabID, into: webView)
        }
    }

    // MARK: - Model Resolution

    @MainActor
    private func resolveProfileID(for tabID: UUID) -> UUID? {
        let tab = BrowserState.shared.spaces
            .flatMap(\.tabs)
            .first { $0.id == tabID }
        return tab?.space?.profile?.id
    }

    @MainActor
    private func loadPersistedURL(for tabID: UUID, into webView: AuroraWebView) {
        let tab = BrowserState.shared.spaces
            .flatMap(\.tabs)
            .first { $0.id == tabID }

        let storedURL = tab?.url
        if let storedURL, !storedURL.isEmpty, storedURL != "aurora://newtab" {
            let resolved = URLResolver.resolve(storedURL)
            webView.load(url: resolved)
        } else {
            webView.loadHTML(NewTabPageHTML.generate())
        }
    }

    // MARK: - Helpers

    private func hideAll() {
        for (_, webView) in attachedWebViews {
            webView.isHidden = true
        }
    }

    func detachAllWebViews() {
        for (_, webView) in attachedWebViews {
            webView.removeFromSuperview()
        }
        attachedWebViews.removeAll()
        currentTabID = nil
    }

    override func layout() {
        super.layout()
        if let tabID = currentTabID, let webView = attachedWebViews[tabID] {
            webView.frame = bounds
        }
    }
}
