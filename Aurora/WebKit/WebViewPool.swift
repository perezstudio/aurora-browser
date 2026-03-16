import Foundation

@MainActor
final class WebViewPool {
    static let shared = WebViewPool()

    /// One WKContextRef per Profile — all spaces in a profile share cookies/cache
    private var contexts: [UUID: WKContextRef] = [:]
    private var webViews: [UUID: AuroraWebView] = [:]
    private var lastAccessed: [UUID: Date] = [:]

    private init() {}

    // MARK: - Context Management

    func context(for profileID: UUID) -> WKContextRef {
        if let existing = contexts[profileID] {
            return existing
        }
        guard let ctx = aurora_context_create() else {
            fatalError("[WebViewPool] Failed to create WKContext for profile \(profileID)")
        }
        contexts[profileID] = ctx
        return ctx
    }

    func removeContext(for profileID: UUID) {
        if let ctx = contexts.removeValue(forKey: profileID) {
            aurora_context_release(ctx)
        }
    }

    // MARK: - WebView Management

    func webView(for tabID: UUID, profileID: UUID) -> AuroraWebView {
        if let existing = webViews[tabID] {
            lastAccessed[tabID] = Date()
            return existing
        }
        let ctx = context(for: profileID)
        let view = AuroraWebView(contextRef: ctx)
        webViews[tabID] = view
        lastAccessed[tabID] = Date()
        return view
    }

    func removeWebView(for tabID: UUID) {
        webViews.removeValue(forKey: tabID)
        lastAccessed.removeValue(forKey: tabID)
    }

    func webViewExists(for tabID: UUID) -> Bool {
        webViews[tabID] != nil
    }

    // MARK: - Memory Pressure

    func purgeInactiveTabs(keeping activeTabIDs: Set<UUID>, olderThan interval: TimeInterval = 300) {
        let cutoff = Date().addingTimeInterval(-interval)

        for (tabID, accessed) in lastAccessed {
            if !activeTabIDs.contains(tabID) && accessed < cutoff {
                removeWebView(for: tabID)
            }
        }
    }
}
