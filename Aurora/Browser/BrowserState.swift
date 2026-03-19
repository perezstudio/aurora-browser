import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class BrowserState {
    static let shared = BrowserState()

    // Profile & space state (loaded from SwiftData on launch)
    var profiles: [Profile] = []
    var spaces: [Space] = []       // ALL spaces across ALL profiles
    var activeSpaceID: UUID?
    var activeTabID: UUID?

    // Bookmark visibility per space
    var bookmarksVisiblePerSpace: [UUID: Bool] = [:]

    // UI state
    var isCommandBarVisible: Bool = false
    var isSidebarCollapsed: Bool = false

    private init() {}

    // MARK: - Initialization

    func loadFromStore(_ modelContext: ModelContext) {
        let profileDescriptor = FetchDescriptor<Profile>()
        profiles = (try? modelContext.fetch(profileDescriptor)) ?? []

        spaces = profiles.flatMap(\.spaces).sorted { $0.order < $1.order }

        if let first = spaces.first {
            activeSpaceID = first.id
            if let firstTab = first.tabs.sorted(by: { $0.order < $1.order }).first {
                activeTabID = firstTab.id
            }
        }
    }

    func reloadSpaces() {
        spaces = profiles.flatMap(\.spaces).sorted { $0.order < $1.order }
    }

    // MARK: - Derived State (all from Tab → Space → Profile)

    var activeTab: Tab? {
        activeSpace?.tabs.first { $0.id == activeTabID }
    }

    var activeSpace: Space? {
        spaces.first { $0.id == activeSpaceID }
    }

    var activeProfile: Profile? {
        activeSpace?.profile
    }

    var activeProfileID: UUID? {
        activeProfile?.id
    }

    /// Returns the active tab's WebView if it exists in the pool.
    func activeWebView() -> AuroraWebView? {
        guard let tabID = activeTabID else { return nil }
        guard WebViewPool.shared.webViewExists(for: tabID) else { return nil }
        guard let profileID = activeTab?.space?.profile?.id else { return nil }
        return WebViewPool.shared.webView(for: tabID, profileID: profileID)
    }

    // MARK: - Selection

    func selectSpace(_ space: Space) {
        activeSpaceID = space.id
        if let firstTab = space.tabs.sorted(by: { $0.order < $1.order }).first {
            activeTabID = firstTab.id
        } else {
            activeTabID = nil
        }
    }

    func selectTab(_ tab: Tab) {
        activeTabID = tab.id
        ExtensionManager.shared.activateTab(tab.id)
    }

    // MARK: - Bookmark / Pin Activation

    func activateBookmarkOrPin(url: String, in spaceID: UUID) {
        activeSpaceID = spaceID
        guard let space = activeSpace else { return }

        if let existing = space.tabs.first(where: { $0.url == url }) {
            activeTabID = existing.id
            return
        }

        let modelContext = PersistenceController.shared.container.mainContext
        let maxOrder = space.tabs.map(\.order).max() ?? -1
        let tab = Tab(url: url, title: url, order: maxOrder + 1)
        tab.space = space
        space.tabs.append(tab)
        modelContext.insert(tab)
        PersistenceController.shared.save()

        activeTabID = tab.id

        guard let profileID = tab.space?.profile?.id else { return }
        let webView = WebViewPool.shared.webView(for: tab.id, profileID: profileID)
        webView.navigationDelegate = self
        let resolved = URLResolver.resolve(url)
        if resolved.scheme == "aurora" && resolved.host == "newtab" {
            webView.loadHTML(NewTabPageHTML.generate())
        } else {
            webView.load(url: resolved)
        }
    }

    // MARK: - Tab Management

    func addTab(in modelContext: ModelContext) {
        guard let space = activeSpace else { return }
        let maxOrder = space.tabs.map(\.order).max() ?? -1
        let tab = Tab(url: "aurora://newtab", title: "New Tab", order: maxOrder + 1)
        tab.space = space
        space.tabs.append(tab)
        modelContext.insert(tab)
        try? modelContext.save()

        activeTabID = tab.id
    }

    func closeTab(_ tab: Tab, in modelContext: ModelContext) {
        guard let space = activeSpace else { return }
        let tabID = tab.id

        WebViewPool.shared.removeWebView(for: tabID)
        NotificationCenter.default.post(name: .tabClosed, object: tabID)

        space.tabs.removeAll { $0.id == tabID }
        modelContext.delete(tab)
        try? modelContext.save()

        if activeTabID == tabID {
            if let next = space.tabs.sorted(by: { $0.order < $1.order }).first {
                activeTabID = next.id
            } else {
                addTab(in: modelContext)
                return
            }
        }
    }

    func closeActiveTab(in modelContext: ModelContext) {
        guard let tab = activeTab else { return }
        closeTab(tab, in: modelContext)
    }

    // MARK: - Workspace Management

    func createSpace(name: String, colorHex: String, iconName: String, in modelContext: ModelContext) {
        let profile = activeProfile ?? profiles.first
        guard let profile else { return }
        let maxOrder = spaces.map(\.order).max() ?? -1
        let space = Space(name: name, colorHex: colorHex, iconName: iconName, order: maxOrder + 1)
        space.profile = profile
        let tab = Tab(url: "aurora://newtab", title: "New Tab", order: 0)
        tab.space = space
        space.tabs.append(tab)
        profile.spaces.append(space)
        modelContext.insert(space)
        try? modelContext.save()

        reloadSpaces()
        selectSpace(space)
    }

    // MARK: - Bookmark Visibility

    func isBookmarksVisible(for spaceID: UUID) -> Bool {
        bookmarksVisiblePerSpace[spaceID] ?? true
    }

    func toggleBookmarksVisibility(for spaceID: UUID) {
        bookmarksVisiblePerSpace[spaceID] = !(bookmarksVisiblePerSpace[spaceID] ?? true)
    }

    // MARK: - Navigation

    func navigateToURL(_ input: String) {
        guard let tab = activeTab else { return }
        let url = URLResolver.resolve(input)

        tab.url = url.absoluteString
        tab.lastVisited = Date()
        PersistenceController.shared.save()

        guard let profileID = tab.space?.profile?.id else { return }
        let webView = WebViewPool.shared.webView(for: tab.id, profileID: profileID)

        if url.scheme == "aurora" && url.host == "newtab" {
            webView.loadHTML(NewTabPageHTML.generate())
        } else {
            webView.load(url: url)
        }
    }

    // MARK: - Tab Lookup

    /// Find a tab by ID across all spaces.
    func tab(for tabID: UUID) -> Tab? {
        spaces.flatMap(\.tabs).first { $0.id == tabID }
    }
}

// MARK: - AuroraWebViewNavigationDelegate

extension BrowserState: AuroraWebViewNavigationDelegate {
    nonisolated func webView(_ webView: AuroraWebView, didUpdateURL url: String?) {
        MainActor.assumeIsolated {
            guard let tab = activeTab, isActiveWebView(webView) else { return }
            if let url, !url.isEmpty {
                tab.url = url
                tab.lastVisited = Date()
                PersistenceController.shared.save()

                // Update extension tab state
                if let tabID = activeTabID {
                    ExtensionManager.shared.updateTabURL(tabID, url: url)
                }
            }
        }
    }

    nonisolated func webView(_ webView: AuroraWebView, didUpdateTitle title: String?) {
        MainActor.assumeIsolated {
            guard let tab = activeTab, isActiveWebView(webView) else { return }
            if let title, !title.isEmpty {
                tab.title = title
                PersistenceController.shared.save()

                // Update extension tab state
                if let tabID = activeTabID {
                    ExtensionManager.shared.updateTabTitle(tabID, title: title)
                }
            }
        }
    }

    nonisolated func webView(_ webView: AuroraWebView, didUpdateLoading isLoading: Bool) {
        MainActor.assumeIsolated {
            guard let tab = activeTab, isActiveWebView(webView) else { return }
            tab.isLoading = isLoading

            // Update extension tab state
            if let tabID = activeTabID {
                ExtensionManager.shared.updateTabLoading(tabID, isLoading: isLoading)
            }
        }
    }

    nonisolated func webView(_ webView: AuroraWebView, didUpdateProgress progress: Double) {
        MainActor.assumeIsolated {
            guard let tab = activeTab, isActiveWebView(webView) else { return }
            tab.estimatedProgress = progress
        }
    }

    nonisolated func webView(_ webView: AuroraWebView, didUpdateCanGoBack canGoBack: Bool) {
        MainActor.assumeIsolated {
            guard let tab = activeTab, isActiveWebView(webView) else { return }
            tab.canGoBack = canGoBack
        }
    }

    nonisolated func webView(_ webView: AuroraWebView, didUpdateCanGoForward canGoForward: Bool) {
        MainActor.assumeIsolated {
            guard let tab = activeTab, isActiveWebView(webView) else { return }
            tab.canGoForward = canGoForward
        }
    }

    private func isActiveWebView(_ webView: AuroraWebView) -> Bool {
        guard let tabID = activeTabID else { return false }
        guard WebViewPool.shared.webViewExists(for: tabID) else { return false }
        guard let profileID = activeTab?.space?.profile?.id else { return false }
        return WebViewPool.shared.webView(for: tabID, profileID: profileID) === webView
    }
}
