import AppKit
import SwiftUI
import SwiftData

final class SettingsWindowController: NSWindowController {

    private static var shared: SettingsWindowController?

    static func showSettings(modelContainer: ModelContainer) {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = SettingsWindowController(modelContainer: modelContainer)
        shared = controller
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(modelContainer: ModelContainer) {
        let settingsView = SettingsView()
            .environment(BrowserState.shared)
            .modelContainer(modelContainer)

        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.minSize = NSSize(width: 560, height: 380)
        window.contentViewController = hostingController
        window.setFrameAutosaveName("AuroraSettingsWindow")
        window.center()

        super.init(window: window)

        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.shared = nil
    }
}
