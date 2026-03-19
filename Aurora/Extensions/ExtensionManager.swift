import AppKit
import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class ExtensionManager {
    static let shared = ExtensionManager()

    /// Per-profile extension controllers (WKWebExtensionController* via bridge)
    private var controllers: [UUID: UnsafeMutableRawPointer] = [:]

    /// Per-profile loaded extension contexts (WKWebExtensionContext* via bridge)
    /// [profileID: [bundleIdentifier: contextPtr]]
    private var contexts: [UUID: [String: UnsafeMutableRawPointer]] = [:]

    /// Tab tracking: tabID → AuroraExtensionTab ObjC object pointer
    private var extensionTabs: [UUID: UnsafeMutableRawPointer] = [:]

    /// Which profile each tab belongs to
    private var tabProfiles: [UUID: UUID] = [:]

    /// Window tracking — single window for now
    private var extensionWindow: UnsafeMutableRawPointer?

    /// Whether Safari Web Extension APIs are available
    var isAvailable: Bool { aurora_ext_is_available() }

    /// Currently visible popup panel
    private var popupPanel: NSPanel?

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AuroraExtensionPopupReady"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let webView = notification.userInfo?["webView"] as? NSView else { return }
            Task { @MainActor in
                self?.presentPopup(webView: webView)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AuroraExtensionOpenNewTab"),
            object: nil,
            queue: .main
        ) { notification in
            let urlString = notification.userInfo?["url"] as? String ?? ""
            Task { @MainActor in
                // Post a notification that BrowserState can handle to create a real tab
                NotificationCenter.default.post(
                    name: NSNotification.Name("AuroraCreateTab"),
                    object: nil,
                    userInfo: ["url": urlString]
                )
            }
        }
    }

    private func presentPopup(webView: NSView) {
        // Close existing popup
        popupPanel?.close()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
        panel.isMovableByWindowBackground = true
        panel.level = .floating

        webView.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        webView.autoresizingMask = [.width, .height]
        panel.contentView = webView

        // Position near the mouse/toolbar
        if let mainWindow = NSApp.mainWindow {
            let windowFrame = mainWindow.frame
            let panelX = windowFrame.maxX - 420
            let panelY = windowFrame.maxY - 540
            panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
        }

        panel.makeKeyAndOrderFront(nil)
        popupPanel = panel
    }

    // MARK: - Controller Lifecycle

    func createController(for profileID: UUID) {
        guard isAvailable else { return }
        guard controllers[profileID] == nil else { return }

        guard let ctrl = aurora_ext_controller_create() else {
            print("[ExtensionManager] Failed to create extension controller for profile \(profileID)")
            return
        }

        controllers[profileID] = ctrl
        contexts[profileID] = [:]

        // Create window if needed and register it with this controller
        if extensionWindow == nil {
            extensionWindow = aurora_ext_window_create()
        }
        if let window = extensionWindow {
            aurora_ext_controller_did_open_window(ctrl, window)
            aurora_ext_controller_did_focus_window(ctrl, window)
        }
    }

    func removeController(for profileID: UUID) {
        // Unload all extensions for this profile
        if let profileContexts = contexts[profileID] {
            let ctrl = controllers[profileID]
            for (_, ctxPtr) in profileContexts {
                if let ctrl {
                    aurora_ext_unload_extension(ctrl, ctxPtr)
                }
            }
        }
        contexts.removeValue(forKey: profileID)

        if let ctrl = controllers.removeValue(forKey: profileID) {
            aurora_ext_controller_release(ctrl)
        }
    }

    func controller(for profileID: UUID) -> UnsafeMutableRawPointer? {
        controllers[profileID]
    }

    // MARK: - Extension Lifecycle

    func loadExtension(appexPath: String, profileID: UUID, modelContext: ModelContext) {
        guard isAvailable else { return }

        // Ensure controller exists
        if controllers[profileID] == nil {
            createController(for: profileID)
        }
        guard let ctrl = controllers[profileID] else { return }

        // Check if already loaded
        let bundle = Bundle(path: appexPath)
        let bundleID = bundle?.bundleIdentifier ?? appexPath
        if contexts[profileID]?[bundleID] != nil { return }

        // Load via bridge
        guard let ctxPtr = aurora_ext_load_extension(ctrl, appexPath) else {
            print("[ExtensionManager] Failed to load extension at \(appexPath)")
            return
        }

        contexts[profileID]?[bundleID] = ctxPtr

        // Get metadata for SwiftData record
        let displayName: String
        if let namePtr = aurora_ext_get_display_name(appexPath) {
            displayName = String(cString: namePtr)
            free(UnsafeMutablePointer(mutating: namePtr))
        } else {
            displayName = bundle?.infoDictionary?["CFBundleDisplayName"] as? String ?? "Extension"
        }

        let version: String
        if let verPtr = aurora_ext_get_version(appexPath) {
            version = String(cString: verPtr)
            free(UnsafeMutablePointer(mutating: verPtr))
        } else {
            version = "1.0"
        }

        let description: String
        if let descPtr = aurora_ext_get_description(appexPath) {
            description = String(cString: descPtr)
            free(UnsafeMutablePointer(mutating: descPtr))
        } else {
            description = ""
        }

        // Get icon
        var iconData: Data?
        if let iconPtr = aurora_ext_get_icon(appexPath, 64) {
            let image = Unmanaged<NSImage>.fromOpaque(iconPtr).takeRetainedValue()
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff) {
                iconData = bitmap.representation(using: .png, properties: [:])
            }
        }

        // Get permissions
        var permissions: [String] = []
        if let permsPtr = aurora_ext_get_permissions(appexPath) {
            let permsStr = String(cString: permsPtr)
            free(UnsafeMutablePointer(mutating: permsPtr))
            if let data = permsStr.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                permissions = arr
            }
        }

        // Auto-grant requested permissions
        if !permissions.isEmpty,
           let permsJSON = try? JSONSerialization.data(withJSONObject: permissions),
           let permsString = String(data: permsJSON, encoding: .utf8) {
            aurora_ext_grant_permissions(ctxPtr, permsString)
        }

        // Check if record already exists
        let existingDescriptor = FetchDescriptor<InstalledExtension>(
            predicate: #Predicate { $0.bundleIdentifier == bundleID && $0.profileID == profileID }
        )
        if let existing = try? modelContext.fetch(existingDescriptor).first {
            existing.isEnabled = true
            existing.appexPath = appexPath
            existing.version = version
        } else {
            let record = InstalledExtension(
                bundleIdentifier: bundleID,
                appexPath: appexPath,
                name: displayName,
                version: version,
                extensionDescription: description,
                profileID: profileID,
                grantedPermissions: permissions,
                iconData: iconData
            )
            modelContext.insert(record)
        }
        try? modelContext.save()
    }

    func unloadExtension(bundleIdentifier: String, profileID: UUID, modelContext: ModelContext) {
        guard let ctrl = controllers[profileID],
              let ctxPtr = contexts[profileID]?.removeValue(forKey: bundleIdentifier) else { return }

        aurora_ext_unload_extension(ctrl, ctxPtr)

        // Remove SwiftData record
        var descriptor = FetchDescriptor<InstalledExtension>(
            predicate: #Predicate { $0.bundleIdentifier == bundleIdentifier && $0.profileID == profileID }
        )
        descriptor.fetchLimit = 1
        if let record = try? modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try? modelContext.save()
        }
    }

    func setEnabled(_ bundleIdentifier: String, profileID: UUID, enabled: Bool, modelContext: ModelContext) {
        // Update SwiftData
        var descriptor = FetchDescriptor<InstalledExtension>(
            predicate: #Predicate { $0.bundleIdentifier == bundleIdentifier && $0.profileID == profileID }
        )
        descriptor.fetchLimit = 1
        guard let record = try? modelContext.fetch(descriptor).first else { return }

        if enabled && contexts[profileID]?[bundleIdentifier] == nil {
            // Re-load the extension
            record.isEnabled = true
            try? modelContext.save()
            loadExtension(appexPath: record.appexPath, profileID: profileID, modelContext: modelContext)
        } else if !enabled, let ctrl = controllers[profileID],
                  let ctxPtr = contexts[profileID]?.removeValue(forKey: bundleIdentifier) {
            // Unload but keep the record
            aurora_ext_unload_extension(ctrl, ctxPtr)
            record.isEnabled = false
            try? modelContext.save()
        }
    }

    func loadEnabledExtensions(for profileID: UUID, modelContext: ModelContext) {
        guard isAvailable else { return }

        var descriptor = FetchDescriptor<InstalledExtension>(
            predicate: #Predicate { $0.profileID == profileID && $0.isEnabled == true }
        )
        descriptor.sortBy = [SortDescriptor(\.installedAt)]

        guard let installed = try? modelContext.fetch(descriptor) else { return }

        for ext in installed {
            // Verify the .appex still exists on disk
            if FileManager.default.fileExists(atPath: ext.appexPath) {
                loadExtension(appexPath: ext.appexPath, profileID: profileID, modelContext: modelContext)
            }
        }
    }

    // MARK: - Tab/Window State Sync

    func registerTab(_ tabID: UUID, webView: AuroraWebView, profileID: UUID) {
        guard isAvailable, let ptr = webView.viewPointer else { return }
        guard let ctrl = controllers[profileID] else { return }

        let tabRef = aurora_ext_tab_create(ptr)
        guard let tabRef else { return }

        extensionTabs[tabID] = tabRef
        tabProfiles[tabID] = profileID

        // Add to window
        if let window = extensionWindow {
            aurora_ext_window_add_tab(window, tabRef)
        }

        // Notify controller
        aurora_ext_controller_did_open_tab(ctrl, tabRef)
    }

    func unregisterTab(_ tabID: UUID) {
        guard let tabRef = extensionTabs.removeValue(forKey: tabID) else { return }
        let profileID = tabProfiles.removeValue(forKey: tabID)

        // Remove from window
        if let window = extensionWindow {
            aurora_ext_window_remove_tab(window, tabRef)
        }

        // Notify controller
        if let profileID, let ctrl = controllers[profileID] {
            aurora_ext_controller_did_close_tab(ctrl, tabRef)
        }

        aurora_ext_tab_release(tabRef)
    }

    func updateTabURL(_ tabID: UUID, url: String?) {
        guard let tabRef = extensionTabs[tabID] else { return }
        aurora_ext_tab_set_url(tabRef, url)
    }

    func updateTabTitle(_ tabID: UUID, title: String?) {
        guard let tabRef = extensionTabs[tabID] else { return }
        aurora_ext_tab_set_title(tabRef, title)
    }

    func updateTabLoading(_ tabID: UUID, isLoading: Bool) {
        guard let tabRef = extensionTabs[tabID] else { return }
        aurora_ext_tab_set_loading(tabRef, isLoading)
    }

    func activateTab(_ tabID: UUID) {
        guard let tabRef = extensionTabs[tabID] else { return }
        let profileID = tabProfiles[tabID]

        // Deactivate all other tabs
        for (id, ref) in extensionTabs where id != tabID {
            aurora_ext_tab_set_active(ref, false)
        }

        aurora_ext_tab_set_active(tabRef, true)

        // Update window's active tab
        if let window = extensionWindow {
            aurora_ext_window_set_active_tab(window, tabRef)
        }

        // Notify controller
        if let profileID, let ctrl = controllers[profileID] {
            aurora_ext_controller_did_activate_tab(ctrl, tabRef)
        }
    }

    // MARK: - Extension Actions

    func performAction(bundleIdentifier: String, profileID: UUID, tabID: UUID?) {
        print("[ExtensionManager] performAction: bundle=\(bundleIdentifier) profile=\(profileID) tabID=\(String(describing: tabID))")
        print("[ExtensionManager] contexts for profile: \(contexts[profileID]?.keys.joined(separator: ", ") ?? "none")")

        guard let ctxPtr = contexts[profileID]?[bundleIdentifier] else {
            print("[ExtensionManager] No context found for \(bundleIdentifier)")
            return
        }

        let tabPtr: UnsafeMutableRawPointer? = tabID.flatMap { extensionTabs[$0] }
        print("[ExtensionManager] Calling aurora_ext_perform_action, tabPtr=\(String(describing: tabPtr))")
        aurora_ext_perform_action(ctxPtr, tabPtr)
    }

    // MARK: - Querying

    func enabledExtensionCount(for profileID: UUID) -> Int {
        contexts[profileID]?.count ?? 0
    }

    func isExtensionLoaded(_ bundleIdentifier: String, profileID: UUID) -> Bool {
        contexts[profileID]?[bundleIdentifier] != nil
    }

    func loadedBundleIdentifiers(for profileID: UUID) -> [String] {
        Array(contexts[profileID]?.keys ?? [:].keys)
    }
}
