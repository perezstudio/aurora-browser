# Aurora Browser — Claude Instructions

## Project Overview

Aurora is a native macOS web browser (macOS 13+) built on **WebKit2 C API**, **AppKit + SwiftUI hybrid**, and **SwiftData**. It is distributed directly (not App Store) via signed + notarized `.dmg` with Sparkle 2 auto-updates. Design inspiration: Arc Browser.

## Key Architectural Decisions

- **WebKit2 C API, not WKWebView.** We use private/SPI headers from `WebKit.framework/PrivateHeaders/` for process isolation and docked Web Inspector. A thin C shim (`AuroraWebKitBridge.h/.c`) bridges C function pointer APIs to Swift.
- **One `WKContextRef` per Space** for full cookie/cache/process isolation.
- **AppKit owns window chrome** (`NSWindow`, `NSSplitViewController`, `NSWindowController`). **SwiftUI owns** sidebar, command bar, preferences, overlays. Bridge via `NSViewRepresentable`.
- **SwiftData** for persistence — `@Model` macros, no CoreData. Models: `Space`, `Tab`, `PinnedTab`, `HistoryEntry`, `Bookmark`.
- **`BrowserState`** is a single `@Observable @MainActor` class — the runtime source of truth, reconstructed from SwiftData on launch. It is NOT a SwiftData model.
- **Web views are pooled, never destroyed on tab switch.** `WebViewPool` detaches/reattaches views to preserve page state.
- **Direct distribution** with Developer ID + Notarization. Requires specific entitlements for WebKit JIT, XPC services, and Web Inspector SPI.

## Code Conventions

- Swift for all application code; C only for the WebKit bridge shim
- `@Observable` (Observation framework) for state — no Combine, no third-party reactive libs
- `NotificationCenter` as lightweight bus for `NSMenu` → SwiftUI action bridging
- KVO-friendly `@objc dynamic` properties on `AuroraWebView` for page state
- `URLResolver` normalizes all address bar input before navigation
- History uses upsert pattern (deduplicate by URL, increment `visitCount`)

## Project Structure

```
Aurora/
├── App/          — @main entry, AppDelegate, ContentView
├── Browser/      — BrowserState, BrowserSplitView, NavigationBar, WebContentView
├── Sidebar/      — SidebarView (spaces, tabs, pinned tabs)
├── CommandBar/   — Command bar overlay and result ranking
├── WebKit/       — AuroraWebView, WebViewPool, URLResolver, C bridge
├── Persistence/  — PersistenceController, SwiftData models
├── UI/Updates/   — Sparkle UpdaterManager and update UI views
└── Distribution/ — Entitlements, ExportOptions, Info.plist additions, appcast
```

## Build & Distribution

- Xcode project with SPM dependency on Sparkle 2
- Bridging header at `Aurora/Distribution/Aurora-Bridging-Header.h`
- Hardened runtime enabled; entitlements in `Aurora/Distribution/Aurora.entitlements`
- CI via GitHub Actions (`release.yml`): archive → notarize → staple → create-dmg → sign with Sparkle Ed25519 → GitHub Release
- Tags matching `v*.*.*` trigger release builds

## Current State

The project is in early development. The Xcode project exists with the default SwiftUI + SwiftData template (AuroraApp.swift, ContentView.swift, Item.swift). The architecture is fully planned in `ARCHITECTURE.md` and distribution setup is documented in `DISTRIBUTION.md`.

## Implementation Plan

### Phase 1 — Foundation
Set up the project skeleton, data layer, and WebKit bridge before any UI work.

- [ ] **1.1 Project structure** — Create folder hierarchy (`App/`, `Browser/`, `Sidebar/`, `CommandBar/`, `WebKit/`, `Persistence/`, `UI/Updates/`, `Distribution/`). Move existing files into `App/`. Update Xcode project groups to match.
- [ ] **1.2 SwiftData models** — Create `Space`, `Tab`, `PinnedTab`, `HistoryEntry`, `Bookmark` as `@Model` classes. Delete template `Item.swift`. See `ARCHITECTURE.md` §5.1 for full schema.
- [ ] **1.3 PersistenceController** — `ModelContainer` setup with all models. Seed three default Spaces ("Personal", "Work", "Research") with one empty tab each. History `recordVisit(url:title:)` upsert helper.
- [ ] **1.4 C bridge shim** — `AuroraWebKitBridge.h/.c` wrapping WebKit2 C API functions (`aurora_load_url`, `aurora_go_back`, `aurora_show_inspector`, etc.). Bridging header importing WebKit C headers + the shim. See `ARCHITECTURE.md` §3.1 for the full API surface.
- [ ] **1.5 URLResolver** — Normalize address bar input: full URL passthrough, add `https://` for domain-like input, Google search fallback, `aurora://newtab` handling.

### Phase 2 — WebKit Layer
Wire up the actual browser engine so we can load and display web pages.

- [ ] **2.1 AuroraWebView** — `NSView` subclass holding `WKPageRef` + `WKViewRef`. KVO-friendly `@objc dynamic` properties: `estimatedProgress`, `isLoading`, `title`, `url`, `canGoBack`, `canGoForward`. C callback → main actor bridge. Public API: `load(url:)`, `goBack()`, `goForward()`, `reload()`, `showInspector()`.
- [ ] **2.2 WebViewPool** — Singleton with `pools: [UUID: WKContextRef]` (one per Space) and `webViews: [UUID: AuroraWebView]` (one per Tab). Views are detached/reattached, never destroyed. `purgeInactiveTabs(keeping:)` for memory pressure.
- [ ] **2.3 NewTabPageHTML** — Static HTML string generator for `aurora://newtab` with a clock display.

### Phase 3 — State & App Lifecycle
Connect the data and WebKit layers through a central state store.

- [ ] **3.1 BrowserState** — `@Observable @MainActor` singleton. Properties: `spaces`, `activeSpaceID`, `activeTabID`, `currentURL`, `currentTitle`, `isLoading`, `estimatedProgress`, `canGoBack`, `canGoForward`, `isCommandBarVisible`, `isSidebarCollapsed`. Conforms to `AuroraWebViewNavigationDelegate`. Reconstructs from SwiftData on launch.
- [ ] **3.2 AppDelegate** — `NSApplicationDelegate` for appearance setup, window configuration (`hiddenTitleBar`, `unifiedCompact` toolbar).
- [ ] **3.3 Refactor AuroraApp.swift** — Replace template code. Wire `@NSApplicationDelegateAdaptor`, inject `ModelContainer`, define `Notification.Name` constants (`.newTab`, `.closeTab`, `.openCommandBar`, `.navigateBack`, `.navigateForward`, `.reload`, `.activeTabChanged`).

### Phase 4 — UI
Build the interface components, from outer shell inward.

- [ ] **4.1 ContentView + BrowserSplitView** — Root `HStack` layout: sidebar (240pt, collapsible) + main content `VStack`. `CommandBarOverlay` as conditional `ZStack` layer.
- [ ] **4.2 SidebarView** — `SpaceSwitcherView` (row of color-tinted chips), `PinnedTabsView` (horizontal scroll), `TabRowView` (scrollable list per active Space), `SidebarBottomBarView` (new tab + collapse toggle).
- [ ] **4.3 NavigationBarView** — Back/forward/reload buttons wired to `BrowserState`. `AddressBarView` — smart text field using `URLResolver`. `ProgressBarView` (2pt animated bar bound to `estimatedProgress`).
- [ ] **4.4 WebContentView** — `NSViewRepresentable` (`ActiveWebViewRepresentable`) keyed on active tab UUID. `AuroraWebViewContainer` fetches view from pool, adds as subview, sets autoresizing mask. `dismantleNSView` removes from superview but does not release.

### Phase 5 — Distribution Setup
Configure signing and entitlements so the app can actually use WebKit SPI.

- [ ] **5.1 Entitlements** — Create `Aurora.entitlements` with all required keys (JIT, unsigned executable memory, disable library validation, network client, web-inspector, browser engine rendering/networking/webcontent, file access). See `ARCHITECTURE.md` §8.2.
- [ ] **5.2 Distribution files** — `ExportOptions.plist` (method: developer-id), `InfoPlist-additions.plist` (Sparkle keys, URL schemes, browser engine declaration).

### Phase 6 — Verify
- [ ] **6.1 Build and launch** — `xcodebuild build` succeeds with zero errors. App launches, displays sidebar with default Spaces, and loads a web page in the content area.

## When Working on This Project

- Always use the WebKit2 C API, never WKWebView
- Keep the C bridge layer minimal — only what's needed to expose WebKit C functions to Swift
- Respect the hybrid split: AppKit for window-level concerns, SwiftUI for UI components
- All runtime state flows through `BrowserState` — don't create parallel state stores
- Test with Developer ID signing in mind — entitlements affect runtime behavior
- Refer to `ARCHITECTURE.md` for detailed design rationale and `DISTRIBUTION.md` for signing/notarization steps
- **Always build the app before declaring changes are done.** Run `xcodebuild build` (or the appropriate scheme build) and verify it succeeds with no errors before considering any task complete.
