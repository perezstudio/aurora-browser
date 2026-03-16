import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class BrowserState {
    static let shared = BrowserState()

    // Space & tab state (loaded from SwiftData on launch)
    var spaces: [Space] = []
    var activeSpaceID: UUID?
    var activeTabID: UUID?

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
        let descriptor = FetchDescriptor<Space>(sortBy: [SortDescriptor(\.order)])
        spaces = (try? modelContext.fetch(descriptor)) ?? []

        if activeSpaceID == nil, let first = spaces.first {
            activeSpaceID = first.id
            if let firstTab = first.tabs.sorted(by: { $0.order < $1.order }).first {
                activeTabID = firstTab.id
            }
        }
    }

    // MARK: - Active Space / Tab

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

        // Remove web view from pool
        WebViewPool.shared.removeWebView(for: tabID)

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

    // MARK: - Navigation

    func navigateToURL(_ input: String) {
        guard let tab = activeTab, let space = activeSpace else { return }
        let url = URLResolver.resolve(input)

        tab.url = url.absoluteString
        tab.lastVisited = Date()

        let webView = WebViewPool.shared.webView(for: tab.id, spaceID: space.id)

        if url.scheme == "aurora" && url.host == "newtab" {
            webView.loadHTML(NewTabPageHTML.generate())
        } else {
            webView.load(url: url)
        }
    }

    // MARK: - Web View State Sync

    func activeWebView() -> AuroraWebView? {
        guard let tabID = activeTabID, let spaceID = activeSpaceID else { return nil }
        guard WebViewPool.shared.webViewExists(for: tabID) else { return nil }
        return WebViewPool.shared.webView(for: tabID, spaceID: spaceID)
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
        }
    }

    nonisolated func webView(_ webView: AuroraWebView, didUpdateTitle title: String?) {
        MainActor.assumeIsolated {
            currentTitle = title
            if let tab = activeTab, let title {
                tab.title = title
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
