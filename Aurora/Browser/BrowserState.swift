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

    /// Derived from the active space's owning profile — no manual tracking needed
    var activeProfileID: UUID? {
        activeSpace?.profile?.id
    }

    // Bookmark visibility per space
    var bookmarksVisiblePerSpace: [UUID: Bool] = [:]

    // Current page state (synced from active AuroraWebView)
    var currentURL: String?
    var currentTitle: String?
    var isLoading: Bool = false
    var estimatedProgress: Double = 0.0
    var canGoBack: Bool = false
    var canGoForward: Bool = false

    // UI state
    var isCommandBarVisible: Bool = false
    var isSidebarCollapsed: Bool = false

    private init() {}

    // MARK: - Initialization

    func loadFromStore(_ modelContext: ModelContext) {
        let profileDescriptor = FetchDescriptor<Profile>()
        profiles = (try? modelContext.fetch(profileDescriptor)) ?? []

        // Load ALL spaces from ALL profiles
        spaces = profiles.flatMap(\.spaces).sorted { $0.order < $1.order }

        // Restore active space and first tab
        if let first = spaces.first {
            activeSpaceID = first.id
            if let firstTab = first.tabs.sorted(by: { $0.order < $1.order }).first {
                activeTabID = firstTab.id
            }
        }
    }

    /// Rebuild the spaces array from all profiles (call after adding/removing spaces)
    func reloadSpaces() {
        spaces = profiles.flatMap(\.spaces).sorted { $0.order < $1.order }
    }

    // MARK: - Active Profile / Space / Tab

    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }

    var activeSpace: Space? {
        spaces.first { $0.id == activeSpaceID }
    }

    var activeTab: Tab? {
        activeSpace?.tabs.first { $0.id == activeTabID }
    }

    func selectSpace(_ space: Space) {
        activeSpaceID = space.id
        if let firstTab = space.tabs.sorted(by: { $0.order < $1.order }).first {
            activeTabID = firstTab.id
        } else {
            activeTabID = nil
        }
        syncWebViewState()
        NotificationCenter.default.post(name: .activeTabChanged, object: nil)
    }

    func selectTab(_ tab: Tab) {
        activeTabID = tab.id
        syncWebViewState()
        NotificationCenter.default.post(name: .activeTabChanged, object: nil)
    }

    // MARK: - Bookmark / Pin Activation

    /// Opens a bookmark or pinned tab. Finds an existing tab with that URL
    /// in the current space, or creates a new tab and navigates to it.
    func activateBookmarkOrPin(url: String, in spaceID: UUID) {
        activeSpaceID = spaceID
        guard let space = activeSpace, let profileID = activeProfileID else { return }

        // Check if there's already a tab with this URL in this space
        if let existing = space.tabs.first(where: { $0.url == url }) {
            activeTabID = existing.id
            syncWebViewState()
            NotificationCenter.default.post(name: .activeTabChanged, object: nil)
            return
        }

        // Create a new tab for this content
        let modelContext = PersistenceController.shared.container.mainContext
        let maxOrder = space.tabs.map(\.order).max() ?? -1
        let tab = Tab(url: url, title: url, order: maxOrder + 1)
        tab.space = space
        space.tabs.append(tab)
        modelContext.insert(tab)
        PersistenceController.shared.save()

        activeTabID = tab.id

        // Create and navigate the web view
        let webView = WebViewPool.shared.webView(for: tab.id, profileID: profileID)
        webView.navigationDelegate = self
        let resolved = URLResolver.resolve(url)
        if resolved.scheme == "aurora" && resolved.host == "newtab" {
            webView.loadHTML(NewTabPageHTML.generate())
        } else {
            webView.load(url: resolved)
        }

        syncWebViewState()
        NotificationCenter.default.post(name: .activeTabChanged, object: nil)
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
        NotificationCenter.default.post(name: .activeTabChanged, object: nil)
    }

    func closeTab(_ tab: Tab, in modelContext: ModelContext) {
        guard let space = activeSpace else { return }
        let tabID = tab.id

        // Remove web view from pool and notify container to detach the subview
        WebViewPool.shared.removeWebView(for: tabID)
        NotificationCenter.default.post(name: .tabClosed, object: tabID)

        // Remove from space
        space.tabs.removeAll { $0.id == tabID }
        modelContext.delete(tab)
        try? modelContext.save()

        // Select another tab
        if activeTabID == tabID {
            if let next = space.tabs.sorted(by: { $0.order < $1.order }).first {
                activeTabID = next.id
            } else {
                // Last tab closed — create a new one
                addTab(in: modelContext)
                return
            }
        }
        NotificationCenter.default.post(name: .activeTabChanged, object: nil)
    }

    func closeActiveTab(in modelContext: ModelContext) {
        guard let tab = activeTab else { return }
        closeTab(tab, in: modelContext)
    }

    // MARK: - Workspace Management

    func createSpace(name: String, colorHex: String, iconName: String, in modelContext: ModelContext) {
        // Attach to the active space's profile, or fall back to first profile
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
        guard let tab = activeTab, let profileID = activeProfileID else { return }
        let url = URLResolver.resolve(input)

        tab.url = url.absoluteString
        tab.lastVisited = Date()
        PersistenceController.shared.save()

        let webView = WebViewPool.shared.webView(for: tab.id, profileID: profileID)

        if url.scheme == "aurora" && url.host == "newtab" {
            webView.loadHTML(NewTabPageHTML.generate())
        } else {
            webView.load(url: url)
        }
    }

    // MARK: - Web View State Sync

    func activeWebView() -> AuroraWebView? {
        guard let tabID = activeTabID, let profileID = activeProfileID else { return nil }
        guard WebViewPool.shared.webViewExists(for: tabID) else { return nil }
        return WebViewPool.shared.webView(for: tabID, profileID: profileID)
    }

    private func syncWebViewState() {
        guard let webView = activeWebView() else {
            currentURL = nil
            currentTitle = nil
            isLoading = false
            estimatedProgress = 0
            canGoBack = false
            canGoForward = false
            return
        }

        currentURL = webView.currentURL
        currentTitle = webView.currentTitle
        isLoading = webView.isPageLoading
        estimatedProgress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

// MARK: - AuroraWebViewNavigationDelegate

extension BrowserState: AuroraWebViewNavigationDelegate {
    nonisolated func webView(_ webView: AuroraWebView, didUpdateURL url: String?) {
        MainActor.assumeIsolated {
            currentURL = url
            // Persist URL to SwiftData
            if let tab = activeTab, let url, !url.isEmpty {
                tab.url = url
                tab.lastVisited = Date()
                PersistenceController.shared.save()
            }
        }
    }

    nonisolated func webView(_ webView: AuroraWebView, didUpdateTitle title: String?) {
        MainActor.assumeIsolated {
            currentTitle = title
            if let tab = activeTab, let title, !title.isEmpty {
                tab.title = title
                PersistenceController.shared.save()
            }
        }
    }

    nonisolated func webView(_ webView: AuroraWebView, didUpdateLoading isLoading: Bool) {
        MainActor.assumeIsolated {
            self.isLoading = isLoading
        }
    }

    nonisolated func webView(_ webView: AuroraWebView, didUpdateProgress progress: Double) {
        MainActor.assumeIsolated {
            estimatedProgress = progress
        }
    }

    nonisolated func webView(_ webView: AuroraWebView, didUpdateCanGoBack canGoBack: Bool) {
        MainActor.assumeIsolated {
            self.canGoBack = canGoBack
        }
    }

    nonisolated func webView(_ webView: AuroraWebView, didUpdateCanGoForward canGoForward: Bool) {
        MainActor.assumeIsolated {
            self.canGoForward = canGoForward
        }
    }
}
