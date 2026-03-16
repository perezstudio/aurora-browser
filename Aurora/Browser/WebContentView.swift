import SwiftUI
import AppKit

struct ActiveWebViewRepresentable: NSViewRepresentable {
    let tabID: UUID
    let profileID: UUID

    func makeNSView(context: Context) -> AuroraWebViewContainer {
        let container = AuroraWebViewContainer()
        container.attachWebView(tabID: tabID, profileID: profileID)
        return container
    }

    func updateNSView(_ nsView: AuroraWebViewContainer, context: Context) {
        // Tab changes are handled by .id(tabID) causing a full recreate
    }

    static func dismantleNSView(_ nsView: AuroraWebViewContainer, coordinator: ()) {
        nsView.detachWebView()
    }
}

// MARK: - Container NSView

final class AuroraWebViewContainer: NSView {
    private var currentWebView: AuroraWebView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    func attachWebView(tabID: UUID, profileID: UUID) {
        let webView = WebViewPool.shared.webView(for: tabID, profileID: profileID)
        webView.navigationDelegate = BrowserState.shared
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
        currentWebView = webView

        // If the web view has no URL loaded yet, show the new tab page
        if webView.currentURL == nil || webView.currentURL?.isEmpty == true {
            webView.loadHTML(NewTabPageHTML.generate())
        }
    }

    func detachWebView() {
        currentWebView?.removeFromSuperview()
        currentWebView = nil
    }

    override func layout() {
        super.layout()
        currentWebView?.frame = bounds
    }
}
