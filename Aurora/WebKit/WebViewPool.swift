import Foundation

@MainActor
final class WebViewPool {
    static let shared = WebViewPool()

    /// One WKContextRef per Profile — all spaces in a profile share cookies/cache
    private var contexts: [UUID: WKContextRef] = [:]
    private var webViews: [UUID: AuroraWebView] = [:]
    private var lastAccessed: [UUID: Date] = [:]
    /// Track which profile each tab belongs to
    private var tabProfiles: [UUID: UUID] = [:]

    private init() {}

    // MARK: - Context Management

    func context(for profileID: UUID) -> WKContextRef {
        if let existing = contexts[profileID] {
            return existing
        }
        guard let ctx = aurora_context_create() else {
            fatalError("[WebViewPool] Failed to create WKContext for profile \(profileID)")
        }
        let uuidString = profileID.uuidString
        uuidString.withCString { cStr in
            aurora_context_set_profile_uuid(ctx, cStr)
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

        // Use extension-aware view creation if an extension controller exists
        let extController = ExtensionManager.shared.controller(for: profileID)
        let view: AuroraWebView
        if let extController {
            view = AuroraWebView(contextRef: ctx, extensionController: extController)
        } else {
            view = AuroraWebView(contextRef: ctx)
        }

        webViews[tabID] = view
        tabProfiles[tabID] = profileID
        lastAccessed[tabID] = Date()

        // Register tab with extension system
        ExtensionManager.shared.registerTab(tabID, webView: view, profileID: profileID)

        return view
    }

    func removeWebView(for tabID: UUID) {
        // Unregister from extension system
        ExtensionManager.shared.unregisterTab(tabID)

        webViews.removeValue(forKey: tabID)
        lastAccessed.removeValue(forKey: tabID)
        tabProfiles.removeValue(forKey: tabID)
    }

    /// Returns all active web views that belong to a given profile.
    func allWebViews(for profileID: UUID) -> [(tabID: UUID, webView: AuroraWebView)] {
        tabProfiles.compactMap { tabID, pid in
            guard pid == profileID, let view = webViews[tabID] else { return nil }
            return (tabID, view)
        }
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
