# Aurora Browser — Claude Instructions

## Project Overview

Aurora is a native macOS web browser (macOS 13+) built on **WebKit2 C API** (via ObjC runtime), **AppKit + SwiftUI hybrid**, and **SwiftData**. It is distributed directly (not App Store) via signed + notarized `.dmg`. Design inspiration: Arc Browser. Edge-to-edge dark UI with custom toolbars — no liquid glass.

## Key Architectural Decisions

- **WebKit2 via ObjC runtime, not WKWebView imports.** A thin ObjC bridge (`AuroraWebKitBridge.h/.m`) uses `objc_getClass` and `objc_msgSend` to create WKWebView at runtime without importing WebKit. Page operations go through `_pageRefForTransitionToWKWebView` and dlsym-resolved C API functions. **Never** `import WebKit` in Swift.
- **One `WKContextRef` per Space** for full cookie/cache/process isolation.
- **Pure AppKit lifecycle** (`@NSApplicationMain` on AppDelegate). No SwiftUI `App`/`Scene`/`WindowGroup`.
- **NSSplitViewController** owns the window layout (sidebar + content panes). SwiftUI views are hosted via `NSHostingController`.
- **NSPageController** for horizontal workspace paging in the sidebar.
- **SwiftData** for persistence — `@Model` macros. Models: `Profile`, `Space`, `Tab`, `PinnedTab`, `HistoryEntry`, `Bookmark`.
- **Profile model** owns pinned tabs (shared across all workspaces in the profile) and groups spaces.
- **`BrowserState`** is a single `@Observable @MainActor` class — the runtime source of truth, reconstructed from SwiftData on launch.
- **Web views are pooled, never destroyed on tab switch.** `WebViewPool` detaches/reattaches views. Pinned tabs and bookmarks can also have pooled WebViews (lazy init on click).
- **Direct distribution** with Developer ID signing. Hardened runtime disabled for Debug.

## Code Conventions

- Swift for all application code; ObjC only for the WebKit bridge shim
- `@Observable` (Observation framework) for state — no Combine, no third-party reactive libs
- `NotificationCenter` as lightweight bus for `NSMenu` → SwiftUI action bridging
- Menus built programmatically via `NSMenu` in AppDelegate
- `URLResolver` normalizes all address bar input before navigation
- History uses upsert pattern (deduplicate by URL, increment `visitCount`)
- Edge-to-edge dark styling: solid backgrounds (#141414 sidebar, #1a1a1a content), no vibrancy/materials

## Project Structure

```
Aurora/
├── App/            — AppDelegate (@NSApplicationMain), notification names
├── Browser/        — BrowserWindowController (NSSplitViewController), BrowserState,
│                     ContentPaneView, NavigationBarView, WebContentView
├── Sidebar/        — SidebarView, WorkspacePagerController (NSPageController),
│                     WorkspacePageView, PinnedTabGridView, BookmarksSectionView,
│                     WorkspaceDockView
├── CommandBar/     — CommandBarOverlay and result ranking
├── WebKit/         — AuroraWebView, WebViewPool, URLResolver, C bridge (ObjC)
├── Persistence/    — PersistenceController, SwiftData models (Profile, Space, Tab, etc.)
├── UI/Utilities/   — ColorExtensions
└── Distribution/   — Entitlements, ExportOptions
```

## Build & Distribution

- Xcode project with PBXFileSystemSynchronizedRootGroup (Xcode 16+ auto-discovers files)
- Bridging header at `Aurora/WebKit/Aurora-Bridging-Header.h`
- Debug: hardened runtime OFF, automatic signing
- Release: hardened runtime ON, automatic signing
- Both: app sandbox OFF

## When Working on This Project

- **Never import WebKit in Swift** — all WebKit access through the ObjC bridge
- Keep the C/ObjC bridge layer minimal — only what's needed to expose WebKit functions to Swift
- Respect the hybrid split: AppKit for window-level concerns (NSSplitViewController, NSWindowController, NSPageController), SwiftUI for UI content within panes
- All runtime state flows through `BrowserState` — don't create parallel state stores
- No liquid glass, no vibrancy materials, no SwiftUI default macOS styling — edge-to-edge dark custom UI
- **Always build the app before declaring changes are done.** Run `xcodebuild build` and verify zero errors.
