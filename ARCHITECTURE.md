# Aurora Browser — Architecture & Planning Document

> A full-featured macOS browser built on WebKit2, AppKit, and SwiftData.
> Direct distribution. Arc-inspired. No App Store constraints.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Technical Decisions](#2-technical-decisions)
3. [WebKit Integration](#3-webkit-integration)
4. [Application Architecture](#4-application-architecture)
5. [Data Layer](#5-data-layer)
6. [UI Architecture](#6-ui-architecture)
7. [Web Inspector Integration](#7-web-inspector-integration)
8. [Distribution & Signing](#8-distribution--signing)
9. [Auto-Update (Sparkle)](#9-auto-update-sparkle)
10. [CI/CD Pipeline](#10-cicd-pipeline)
11. [Project File Structure](#11-project-file-structure)
12. [Milestones](#12-milestones)
13. [Open Questions & Future Work](#13-open-questions--future-work)

---

## 1. Project Overview

Aurora is a native macOS web browser targeting macOS 13 (Ventura) and later. It is
distributed directly — outside the Mac App Store — which allows use of private/SPI
WebKit APIs that are unavailable to sandboxed App Store builds.

### Design inspiration

Arc Browser by The Browser Company. Key traits carried over:

- **Vertical sidebar** as the primary navigation surface, not a tab bar
- **Spaces** — isolated tab groups with their own color, icon, and process
- **Command bar** (⌘T) as the universal search / navigate / action surface
- **Pinned tabs** (favorites) permanently docked above the tab list
- **Chromeless feel** — the web content fills the window; chrome steps aside

### Core technology choices at a glance

| Concern | Choice | Rationale |
|---|---|---|
| Browser engine | WebKit2 C API (system WebKit.framework) | No source build needed; ships with macOS; SPI access; same engine as Safari |
| UI framework | AppKit + SwiftUI (hybrid) | AppKit for window chrome and NSView hosting; SwiftUI for sidebar, command bar, overlays |
| State management | Swift `@Observable` stores | No third-party reactive framework; native Observation framework (iOS 17 / macOS 14) |
| Persistence | SwiftData | Native, Swift-native ORM; replaces CoreData boilerplate; schema migration built-in |
| Distribution | Developer ID + Notarization | Direct .dmg download; no App Store review; SPI entitlements available |
| Updates | Sparkle 2 | Industry standard for direct-distribution macOS apps; Ed25519 signed appcast |

---

## 2. Technical Decisions

### 2.1 WebKit2 C API over WKWebView

`WKWebView` is a high-level Objective-C wrapper Apple introduced in macOS 10.10. It is
the App Store–safe surface. We explicitly **do not use it**.

Instead, Aurora uses the underlying **WebKit2 C API** exposed at:

```
/System/Library/Frameworks/WebKit.framework/PrivateHeaders/
```

Key headers: `WKContext.h`, `WKPage.h`, `WKView.h`, `WKInspector.h`, `WKInspectorPrivateMac.h`

**Why this matters:**

- `WKViewRef` is a true `NSView` subclass — embed it like any view, no bridging ceremony
- `WKContextRef` maps 1:1 to a web content process — one per Space = true process isolation
- `WKInspectorRef` gives full programmatic control over the Web Inspector including docked mode
- C function pointer delegates (`WKPageNavigationClient`, `WKPageUIClient`) give finer control
  than `WKNavigationDelegate` without the Objective-C overhead

**The tradeoff:** Swift cannot call C function pointer APIs directly. A thin C shim
(`AuroraWebKitBridge.h` / `.c`) bridges Swift closures into the C struct delegates.

### 2.2 Process isolation per Space

Each Space gets its own `WKContextRef` (process pool). This means:

- Cookies, cache, localStorage, and session data are siloed per Space
- A crash in one Space's web content process does not affect others
- Memory can be reclaimed per-Space when backgrounded

This mirrors how Arc separates Spaces and how Orion handles profiles. It is only
achievable via the C API — `WKWebView`'s `WKProcessPool` does not offer the same
deterministic isolation.

### 2.3 AppKit + SwiftUI hybrid

Pure SwiftUI on macOS still has rough edges around window management, toolbar
customization, and `NSView` hosting. The hybrid approach:

- **AppKit owns:** `NSWindow`, `NSSplitViewController` backbone, `NSWindowController`
- **SwiftUI owns:** Sidebar, command bar, preference panels, update UI, overlays
- **NSViewRepresentable bridges:** `AuroraWebViewContainer` hosts the `WKViewRef`-backed
  `AuroraWebView` (an `NSView` subclass) inside SwiftUI's layout system

### 2.4 SwiftData over CoreData

SwiftData was chosen for persistence because:

- Pure Swift API — no `NSManagedObject` subclasses, no `.xcdatamodeld` files
- `@Model` macro generates everything at compile time
- Integrates naturally with SwiftUI's `@Query` and `@Environment(\.modelContext)`
- Schema migrations are handled declaratively with `VersionedSchema`

Models: `Space`, `Tab`, `PinnedTab`, `HistoryEntry`, `Bookmark`

### 2.5 Direct distribution

Distributing outside the App Store was a requirement from the start. Consequences:

- **Entitlements** are enforced by the OS signature check, not a provisioning profile
- `com.apple.developer.web-inspector` entitlement unlocks `WKInspectorAttach` (docked mode)
- `com.apple.developer.web-browser-engine.*` entitlements unlock the multi-process model
- `com.apple.security.cs.disable-library-validation` is required for WebKit's XPC services
  to load inside the app bundle
- The app must be **notarized** — Apple scans it for malware and staples a ticket;
  Gatekeeper will pass on first launch without any user override prompt

---

## 3. WebKit Integration

### 3.1 Layer diagram

```
Swift (AuroraWebView.swift)
        │  Public API: load(url:), goBack(), goForward(), reload(),
        │              showInspector(), toggleInspector()
        ▼
BridgingHeader.h
        │  Imports WebKit C headers + AuroraWebKitBridge.h
        ▼
AuroraWebKitBridge.h / .c   ← thin C shim
        │  aurora_load_url()         → WKPageLoadURL()
        │  aurora_go_back()          → WKPageGoBack()
        │  aurora_show_inspector()   → WKInspectorShow()
        │  aurora_attach_inspector() → WKInspectorAttach()  [SPI]
        │  Installs WKPageNavigationClientV3 struct with C callbacks
        ▼
WebKit.framework  (system, /System/Library/Frameworks/)
        │
        ▼
WebContent XPC process  (com.apple.WebKit.WebContent)
        │  One process per WKContextRef = one per Space
```

### 3.2 AuroraWebView

`AuroraWebView` is an `NSView` subclass. Internally it holds:

- `pageRef: WKPageRef` — the WebKit2 page
- `viewRef: WKViewRef` — the actual `NSView` (a WebKit internal class)
- KVO-friendly `@objc dynamic` properties mirroring page state:
  `estimatedProgress`, `isLoading`, `title`, `url`, `canGoBack`, `canGoForward`

The C callbacks installed via `aurora_install_navigation_client()` fire into static
functions which use the `clientInfo` pointer to recover `self` and post back to the
main actor.

### 3.3 WebViewPool

`WebViewPool` is a singleton that manages two dictionaries:

- `pools: [UUID: WKContextRef]` — one context per Space UUID
- `webViews: [UUID: AuroraWebView]` — one view per Tab UUID

Views are **never destroyed on tab switch** — they are detached from the view hierarchy
and re-attached when the tab becomes active. This preserves page state (scroll position,
form input, back/forward list) identically to Safari and Arc.

Memory pressure handling: `purgeInactiveTabs(keeping:)` tears down web views for tabs
that have not been visible for a configurable interval.

---

## 4. Application Architecture

### 4.1 State management

A single `@Observable @MainActor` class, `BrowserState`, is the source of truth for
all runtime state. It is not a SwiftData model — it is ephemeral, reconstructed from
SwiftData on launch.

```
BrowserState (singleton, @Observable)
├── spaces: [Space]              ← loaded from SwiftData on launch
├── activeSpaceID: UUID?
├── activeTabID: UUID?
├── currentURL / currentTitle    ← synced from active AuroraWebView
├── isLoading / estimatedProgress
├── canGoBack / canGoForward
├── isCommandBarVisible: Bool
└── isSidebarCollapsed: Bool
```

`BrowserState` also conforms to `AuroraWebViewNavigationDelegate`, so it receives
all navigation callbacks from the active web view and updates its own properties,
which SwiftUI observes automatically.

### 4.2 Notification bus

Some actions originate from `NSMenu` commands (which don't have a SwiftUI binding
path). These use `NotificationCenter` as a lightweight bus:

| Notification | Trigger | Handler |
|---|---|---|
| `.newTab` | ⌘T | `BrowserState.addTab()` |
| `.openCommandBar` | ⌘⇧T | `BrowserState.isCommandBarVisible.toggle()` |
| `.closeTab` | ⌘W | `BrowserState.closeActiveTab()` |
| `.navigateBack` | ⌘[ | `activeWebView()?.goBack()` |
| `.navigateForward` | ⌘] | `activeWebView()?.goForward()` |
| `.reload` | ⌘R | `activeWebView()?.reload()` |
| `.activeTabChanged` | internal | `WebContentView` re-attaches web view |

---

## 5. Data Layer

### 5.1 SwiftData models

```
Space
├── id: UUID
├── name: String
├── colorHex: String          "#7C6AF7"
├── iconName: String          SF Symbol name
├── order: Int
├── createdAt: Date
├── tabs: [Tab]               cascade delete
└── pinnedTabs: [PinnedTab]   cascade delete

Tab
├── id: UUID
├── url: String
├── title: String
├── faviconData: Data?
├── order: Int
├── createdAt: Date
├── lastVisited: Date
└── space: Space?             back-reference

PinnedTab
├── id: UUID
├── url: String
├── title: String
├── faviconData: Data?
├── order: Int
└── space: Space?

HistoryEntry
├── id: UUID
├── url: String
├── title: String
├── visitedAt: Date
└── visitCount: Int

Bookmark
├── id: UUID
├── url: String
├── title: String
├── folderName: String?
└── createdAt: Date
```

### 5.2 PersistenceController

`PersistenceController.shared` owns the `ModelContainer`. It seeds three default
Spaces ("Personal", "Work", "Research") with one empty tab each if the store is empty.

History deduplication: `recordVisit(url:title:)` upserts — if a `HistoryEntry`
already exists for the URL it increments `visitCount` and updates `visitedAt` rather
than creating a duplicate row.

### 5.3 URL handling

`URLResolver` normalizes the address bar input before any navigation:

1. Full URL with scheme → pass through
2. Contains `.` and no spaces → prepend `https://`
3. Anything else → Google search query
4. `aurora://newtab` → load the built-in new tab page (HTML string, no server needed)

---

## 6. UI Architecture

### 6.1 Window layout

```
NSWindow (hiddenTitleBar, unifiedCompact toolbar)
└── ContentView (SwiftUI root)
    ├── BrowserSplitView
    │   ├── SidebarView (240pt fixed width, collapsible)
    │   │   ├── SpaceSwitcherView       — row of Space chips
    │   │   ├── PinnedTabsView          — horizontal scroll of favorites
    │   │   ├── ScrollView > TabRowView — one row per tab in active Space
    │   │   └── SidebarBottomBarView    — new tab + collapse toggle
    │   └── VStack
    │       ├── NavigationBarView (48pt)
    │       │   ├── Back / Forward / Reload buttons
    │       │   └── AddressBarView      — smart URL/search field
    │       ├── ProgressBarView (2pt)   — animated load indicator
    │       └── WebContentView          — NSViewRepresentable host
    └── CommandBarOverlay (conditional, .animation spring)
        └── CommandBarPanel
            ├── Search TextField
            └── CommandResultRow list   — history + bookmarks + navigate
```

### 6.2 Web content hosting

`WebContentView` is a SwiftUI `View` that renders `ActiveWebViewRepresentable`
keyed on the active tab's `UUID`.

`ActiveWebViewRepresentable` is an `NSViewRepresentable` wrapping
`AuroraWebViewContainer` — a plain `NSView` that:
1. Fetches the `AuroraWebView` for the tab from `WebViewPool`
2. `addSubview`s it and sets `autoresizingMask = [.width, .height]`
3. On `dismantleNSView`, calls `removeFromSuperview()` but does **not** release the
   view — it stays alive in the pool

SwiftUI re-creates `ActiveWebViewRepresentable` for each `.id(tab.id)` change, but
the underlying `AuroraWebView` is the same object retrieved from the pool, so page
state is fully preserved.

### 6.3 Command bar

The command bar is a modal overlay (`.ultraThinMaterial` + drop shadow) centered in
the window. It is not a sheet or popover — it renders as a `ZStack` layer in
`ContentView` with a backdrop tap-to-dismiss.

Result ranking order:
1. URL-like query (contains `.`, no spaces) → direct navigate option
2. History matches (by URL + title substring)
3. Bookmark matches
4. Google search fallback (always last)

Keyboard navigation: `↑`/`↓` move the selection; `↩` commits; `Esc` dismisses.

---

## 7. Web Inspector Integration

### 7.1 API surface

Two tiers of WebKit inspector API are used:

| API | Header | Mode | App Store safe? |
|---|---|---|---|
| `WKInspectorShow` / `WKInspectorClose` | `WKInspector.h` (public) | Detached window | Yes |
| `WKInspectorAttach` / `WKInspectorDetach` | `WKInspectorPrivateMac.h` (SPI) | Docked panel | No — requires `com.apple.developer.web-inspector` entitlement |

Since Aurora is direct distribution, both tiers are available. Docked mode (attached
to the browser window) is the default, matching the Chrome DevTools UX.

### 7.2 Docked inspector layout

When the inspector is docked, `BrowserSplitView` adds a horizontal split below
`WebContentView`:

```
VStack
├── NavigationBarView
├── ProgressBarView
├── WebContentView          ← flex height
└── InspectorPanelView      ← fixed or resizable height, shown when docked
```

The inspector panel height is persisted to `UserDefaults` so it restores across
launches.

### 7.3 Keyboard shortcut

`⌥⌘I` — standard across Safari, Chrome, Firefox. Toggles between:
- Hidden → Docked
- Docked → Detached window
- Detached window → Hidden

The C shim exposes:

```c
void       aurora_show_inspector(WKPageRef)
void       aurora_close_inspector(WKPageRef)
void       aurora_attach_inspector(WKPageRef)   // SPI
void       aurora_detach_inspector(WKPageRef)   // SPI
bool       aurora_inspector_is_shown(WKPageRef)
bool       aurora_inspector_is_attached(WKPageRef)
```

---

## 8. Distribution & Signing

### 8.1 Certificate chain

```
Apple Root CA
└── Developer ID Certification Authority
    └── Developer ID Application: <Your Name> (TEAMID)
        └── Aurora.app  (signed with hardened runtime)
            ├── Aurora   (main binary)
            ├── Frameworks/Sparkle.framework
            └── XPCServices/
                ├── org.sparkle-project.InstallerLauncher.xpc
                └── org.sparkle-project.Downloader.xpc
```

Every component in the bundle must be signed with the same Developer ID certificate.
Unsigned XPC services will be killed by the OS.

### 8.2 Entitlements

| Entitlement | Reason |
|---|---|
| `com.apple.security.cs.allow-jit` | WebKit JS engine requires JIT memory |
| `com.apple.security.cs.allow-unsigned-executable-memory` | WebKit internal |
| `com.apple.security.cs.disable-library-validation` | WebKit XPC services must load |
| `com.apple.security.network.client` | All network requests |
| `com.apple.developer.web-inspector` | `WKInspectorAttach` SPI (docked inspector) |
| `com.apple.developer.web-browser-engine.rendering` | Multi-process WebKit rendering |
| `com.apple.developer.web-browser-engine.networking` | WebKit network process |
| `com.apple.developer.web-browser-engine.webcontent` | WebKit content process |
| `com.apple.security.files.downloads.read-write` | Save page / file downloads |
| `com.apple.security.files.user-selected.read-write` | file:// URLs, save dialogs |

### 8.3 Notarization flow

```
xcodebuild archive
    → xcodebuild -exportArchive (method: developer-id)
    → xcrun notarytool submit --wait
    → xcrun stapler staple
    → create-dmg
    → codesign DMG
    → xcrun notarytool submit DMG --wait
    → xcrun stapler staple DMG
```

The stapled ticket means Gatekeeper can verify the app without a network call on
first launch, which matters for users with strict firewall rules or offline installs.

---

## 9. Auto-Update (Sparkle)

### 9.1 Sparkle 2 overview

Sparkle 2 ships two XPC services that do the actual work outside the app process:

- **InstallerLauncher.xpc** — escalates privileges to install the update
- **Downloader.xpc** — downloads the update file in a sandboxed process

This means even if Aurora itself doesn't have broad file-system access, updates still
install correctly.

### 9.2 Security model

Every release artifact (`.dmg` and `.delta`) is signed with an **Ed25519 private key**
that never leaves the developer's machine (stored in macOS Keychain). The corresponding
public key is embedded in `Info.plist` under `SUPublicEDKey`.

Sparkle verifies the signature before installing. A compromised CDN or MITM cannot
deliver a malicious update because they don't have the private key.

### 9.3 Appcast

`appcast.xml` is a standard RSS feed with Sparkle-specific namespace extensions.
It is hosted at the URL in `SUFeedURL` (Info.plist).

Each `<item>` contains:
- `sparkle:version` — integer build number (must be strictly increasing)
- `sparkle:shortVersionString` — human-readable version shown in UI
- `<enclosure>` — full DMG URL + Ed25519 signature + byte length
- `<sparkle:deltas>` — optional delta `.delta` files per source version
- `<description>` — HTML release notes shown in the update prompt

### 9.4 Delta updates

Binary delta files contain only the diff between two `.app` versions. For typical
point releases this reduces download size by ~85–95%. Generated with:

```bash
./bin/BinaryDelta create OldAurora.app NewAurora.app Aurora-1.0-1.1.delta
```

### 9.5 In-app update UI

Three SwiftUI components:

| Component | Location | Purpose |
|---|---|---|
| `UpdaterMenuButton` | App menu | "Check for Updates…" with live status |
| `UpdatePreferencesSection` | Preferences window | Auto-update toggle, last-checked date, manual check |
| `UpdateNotificationBanner` | `BrowserSplitView` overlay | Non-intrusive banner when update available |

`UpdaterManager` is an `@Observable` singleton wrapping `SPUStandardUpdaterController`.
It exposes `updateState: UpdateState` (an enum covering idle / checking / available /
downloading / readyToInstall / upToDate / error).

---

## 10. CI/CD Pipeline

### 10.1 Workflow trigger

The GitHub Actions workflow (`release.yml`) triggers on:
- `git push` of a `v*.*.*` tag (e.g. `v1.1.0`)
- Manual `workflow_dispatch` from the Actions tab

### 10.2 Steps

```
1. Checkout
2. Select Xcode 16 (macos-14 runner = Apple Silicon)
3. Import Developer ID cert from secret → temp keychain
4. xcodebuild -resolvePackageDependencies  (Sparkle SPM)
5. xcodebuild archive
6. xcodebuild -exportArchive  (method: developer-id)
7. xcrun notarytool submit app zip → wait
8. xcrun stapler staple app
9. create-dmg  (with background image, icon placement)
10. codesign DMG
11. xcrun notarytool submit DMG → wait
12. xcrun stapler staple DMG
13. sign_update DMG  (Sparkle Ed25519 signature)
14. actions/upload-artifact  (DMG)
15. softprops/action-gh-release  (GitHub Release with DMG attached)
```

### 10.3 Required secrets

| Secret | Content |
|---|---|
| `DEVELOPER_ID_APPLICATION_CERT_P12` | Base64-encoded .p12 certificate |
| `DEVELOPER_ID_APPLICATION_CERT_PWD` | .p12 export password |
| `KEYCHAIN_PASSWORD` | Any string — temp keychain password for this job |
| `NOTARIZATION_APPLE_ID` | Apple ID email |
| `NOTARIZATION_PASSWORD` | App-specific password (not Apple ID password) |
| `NOTARIZATION_TEAM_ID` | 10-character Apple Developer team ID |
| `SPARKLE_PRIVATE_KEY` | Ed25519 private key (from Keychain via `generate_keys`) |

---

## 11. Project File Structure

```
Aurora/
├── .github/
│   └── workflows/
│       └── release.yml               CI build + notarize + release
│
├── ARCHITECTURE.md                   ← this file
├── DISTRIBUTION.md                   step-by-step setup guide
│
└── Aurora/                           Xcode target root
    ├── App/
    │   ├── AuroraApp.swift           @main, SwiftUI App, notification names
    │   ├── AppDelegate.swift         NSApplicationDelegate, appearance setup
    │   └── ContentView.swift         SwiftUI root, model container injection
    │
    ├── Browser/
    │   ├── BrowserState.swift        @Observable state store + nav delegate
    │   ├── BrowserSplitView.swift    top-level HStack layout
    │   ├── NavigationBarView.swift   URL bar, back/forward/reload, progress
    │   └── WebContentView.swift      NSViewRepresentable + container NSView
    │
    ├── Sidebar/
    │   └── SidebarView.swift         spaces, tabs, pinned tabs, bottom bar
    │
    ├── CommandBar/
    │   └── CommandBarView.swift      overlay panel, result model, row views
    │
    ├── WebKit/
    │   ├── AuroraWebView.swift       NSView subclass, KVO props, nav delegate
    │   ├── WebViewPool.swift         WKContext + view lifecycle manager
    │   ├── URLResolver.swift         address bar input → URL normalization
    │   ├── NewTabPageHTML.swift      built-in new tab page generator
    │   ├── AuroraWebKitBridge.h      C API declarations (Swift-visible)
    │   └── AuroraWebKitBridge.c      C shim: function pointers → Swift closures
    │
    ├── Persistence/
    │   ├── PersistenceController.swift   ModelContainer, seeding, helpers
    │   └── Models/
    │       ├── Space.swift
    │       ├── Tab.swift
    │       └── HistoryEntry.swift        also contains Bookmark, PinnedTab
    │
    ├── UI/
    │   └── Updates/
    │       ├── UpdaterManager.swift      @Observable SPUUpdater wrapper
    │       └── UpdaterViews.swift        menu button, prefs section, banner
    │
    └── Distribution/
        ├── Aurora.entitlements           signed entitlements plist
        ├── ExportOptions.plist           xcodebuild export config
        ├── InfoPlist-additions.plist     Sparkle keys, URL schemes, engine decl.
        └── appcast.xml                   template — host this on your server
```

---

## 12. Milestones

### M1 — Skeleton (working window + WebKit)
- [ ] Xcode project created with AppKit lifecycle
- [ ] `AuroraWebKitBridge.c` compiles and links against system WebKit
- [ ] `AuroraWebView` loads a URL and renders it in a window
- [ ] `WebViewPool` manages one context per Space UUID
- [ ] SwiftData container initializes with seeded Spaces

### M2 — Core browser UX
- [ ] Sidebar renders Spaces, tabs, pinned tabs
- [ ] Tab switching re-attaches web views without reloading
- [ ] Navigation bar: back, forward, reload, address bar
- [ ] URL resolver handles search vs URL inputs
- [ ] New tab page renders with clock

### M3 — Command bar + history
- [ ] Command bar overlay (⌘⇧T) with keyboard nav
- [ ] History written on every page finish
- [ ] History + bookmarks surfaced in command bar results
- [ ] History deduplication (upsert by URL)

### M4 — Web Inspector
- [ ] Detached inspector (public API) via ⌥⌘I
- [ ] Docked inspector (SPI) with split layout
- [ ] Inspector panel height persisted to UserDefaults

### M5 — Distribution
- [ ] Entitlements file configured and signed
- [ ] App notarizes cleanly
- [ ] DMG created with background + drag-to-Applications layout
- [ ] Stapled ticket passes `spctl --assess`

### M6 — Sparkle updates
- [ ] Ed25519 key pair generated; public key in Info.plist
- [ ] `appcast.xml` hosted and reachable
- [ ] `UpdaterManager` connects to feed
- [ ] In-app banner appears when update available
- [ ] CI signs DMG and prints `edSignature` in release notes

### M7 — Polish
- [ ] Space color tints sidebar background
- [ ] Favicon loading and caching
- [ ] Tab drag-to-reorder in sidebar
- [ ] Preferences window (general, updates, spaces)
- [ ] Set as default browser via `LSSetDefaultHandlerForURLScheme`

---

## 13. Open Questions & Future Work

### Resolved decisions
- **WKWebView vs C API** → C API (for SPI access and process isolation control)
- **App Store vs direct** → Direct distribution
- **Updater** → Sparkle 2 with Ed25519 appcast
- **Persistence** → SwiftData
- **UI framework** → AppKit + SwiftUI hybrid

### Open questions

**Content blocking**
Should Aurora ship a built-in ad/tracker blocker? Options:
- WebKit content rules (`WKContentRuleList`) — declarative JSON, fast, but limited
- `WKUserScript` injection — flexible but runs in-page JS
- Network-layer proxy (like Little Snitch model) — most powerful, most complex

**Default search engine**
Currently hardcoded to Google. Should be user-configurable (DuckDuckGo, Brave Search, etc.).

**Sync**
Arc syncs across devices via their own backend. Aurora options:
- CloudKit (free, Apple-native, private) — good fit given SwiftData
- iCloud Drive (JSON export/import) — simpler but not real-time
- No sync (v1 scope)

**Extensions**
WebKit supports `WKUserScript` and `WKContentRuleList` for basic extension-like
functionality. Full Safari-style Web Extensions (`.appex` bundles) require the
App Store. A custom extension model (similar to Orion's) is possible but significant
scope.

**Reader mode**
WebKit has an internal reader mode API accessible via SPI. Lower priority but high
user value.

**Downloads manager**
`WKDownload` (macOS 11.3+) is the public API. A downloads panel in the sidebar would
complete the browsing experience.

**iOS / iPadOS companion**
The WebKit2 C API is macOS-only. An iOS companion would need `WKWebView`. A shared
SwiftData CloudKit store could sync history and bookmarks between platforms while the
WebKit layer diverges.
