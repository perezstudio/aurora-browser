import Foundation

@MainActor
final class WebViewPool {
    static let shared = WebViewPool()

    private var contexts: [UUID: WKContextRef] = [:]
    private var webViews: [UUID: AuroraWebView] = [:]
    private var lastAccessed: [UUID: Date] = [:]

    private init() {}

    // MARK: - Context Management

    func context(for spaceID: UUID) -> WKContextRef {
        if let existing = contexts[spaceID] {
            return existing
        }
        guard let ctx = aurora_context_create() else {
            fatalError("[WebViewPool] Failed to create WKContext for space \(spaceID)")
        }
        contexts[spaceID] = ctx
        return ctx
    }

    func removeContext(for spaceID: UUID) {
        if let ctx = contexts.removeValue(forKey: spaceID) {
            aurora_context_release(ctx)
        }
    }

    // MARK: - WebView Management

    func webView(for tabID: UUID, spaceID: UUID) -> AuroraWebView {
        if let existing = webViews[tabID] {
            lastAccessed[tabID] = Date()
            return existing
        }
        let ctx = context(for: spaceID)
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
