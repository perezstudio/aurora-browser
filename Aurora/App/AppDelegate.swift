import AppKit
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: BrowserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app appears in dock and can receive focus
        NSApp.setActivationPolicy(.regular)

        // Initialize the WebKit bridge
        if !aurora_bridge_init() {
            NSLog("[Aurora] WARNING: WebKit2 C API bridge initialization failed — some features may be unavailable")
        }

        // Follow system appearance (light/dark)
        NSApp.appearance = nil

        // Disable window restoration (false = don't keep windows on quit)
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        // Build menus first (before window creation)
        buildMainMenu()

        // Seed default data
        PersistenceController.shared.seedDefaultSpacesIfNeeded()

        // Load browser state from SwiftData
        let modelContext = PersistenceController.shared.container.mainContext
        BrowserState.shared.loadFromStore(modelContext)

        // Create and show the main window
        let wc = BrowserWindowController(
            browserState: BrowserState.shared,
            modelContainer: PersistenceController.shared.container
        )
        windowController = wc
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Register notification handlers
        registerNotificationHandlers()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Notification Handlers

    private func registerNotificationHandlers() {
        let nc = NotificationCenter.default
        let modelContext = PersistenceController.shared.container.mainContext

        nc.addObserver(forName: .newTab, object: nil, queue: .main) { [weak self] _ in
            _ = self
            MainActor.assumeIsolated {
                BrowserState.shared.addTab(in: modelContext)
            }
        }

        nc.addObserver(forName: .closeTab, object: nil, queue: .main) { [weak self] _ in
            _ = self
            MainActor.assumeIsolated {
                BrowserState.shared.closeActiveTab(in: modelContext)
            }
        }

        nc.addObserver(forName: .openCommandBar, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                BrowserState.shared.isCommandBarVisible.toggle()
            }
        }

        nc.addObserver(forName: .navigateBack, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                BrowserState.shared.activeWebView()?.goBack()
            }
        }

        nc.addObserver(forName: .navigateForward, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                BrowserState.shared.activeWebView()?.goForward()
            }
        }

        nc.addObserver(forName: .reloadPage, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                BrowserState.shared.activeWebView()?.reload()
            }
        }

        nc.addObserver(forName: .toggleInspector, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                BrowserState.shared.activeWebView()?.toggleInspector()
            }
        }

        nc.addObserver(forName: .toggleSidebar, object: nil, queue: .main) { [weak self] _ in
            self?.windowController?.splitViewController.toggleSidebarPane()
        }
    }

    // MARK: - Main Menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Aurora", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction(_:)), keyEquivalent: ",")
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Aurora", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newTabAction(_:)), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeTabAction(_:)), keyEquivalent: "w")
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Toggle Sidebar", action: #selector(toggleSidebarAction(_:)), keyEquivalent: "l")
        viewMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(withTitle: "Open Command Bar", action: #selector(openCommandBarAction(_:)), keyEquivalent: "k")
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Developer menu
        let devMenu = NSMenu(title: "Developer")
        let inspectorItem = NSMenuItem(title: "Toggle Web Inspector", action: #selector(toggleInspectorAction(_:)), keyEquivalent: "i")
        inspectorItem.keyEquivalentModifierMask = [.option, .command]
        devMenu.addItem(inspectorItem)
        let devMenuItem = NSMenuItem()
        devMenuItem.submenu = devMenu
        mainMenu.addItem(devMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Actions

    @objc private func newTabAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .newTab, object: nil)
    }

    @objc private func closeTabAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .closeTab, object: nil)
    }

    @objc private func toggleSidebarAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .toggleSidebar, object: nil)
    }

    @objc private func openCommandBarAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .openCommandBar, object: nil)
    }

    @objc private func toggleInspectorAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .toggleInspector, object: nil)
    }

    @objc private func openSettingsAction(_ sender: Any?) {
        SettingsWindowController.showSettings(modelContainer: PersistenceController.shared.container)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newTab = Notification.Name("Aurora.newTab")
    static let closeTab = Notification.Name("Aurora.closeTab")
    static let openCommandBar = Notification.Name("Aurora.openCommandBar")
    static let navigateBack = Notification.Name("Aurora.navigateBack")
    static let navigateForward = Notification.Name("Aurora.navigateForward")
    static let reloadPage = Notification.Name("Aurora.reloadPage")
    static let activeTabChanged = Notification.Name("Aurora.activeTabChanged")
    static let toggleInspector = Notification.Name("Aurora.toggleInspector")
    static let toggleSidebar = Notification.Name("Aurora.toggleSidebar")
    static let tabClosed = Notification.Name("Aurora.tabClosed")
}
