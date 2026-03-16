import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the WebKit bridge
        if !aurora_bridge_init() {
            NSLog("[Aurora] WARNING: WebKit2 C API bridge initialization failed — some features may be unavailable")
        }

        // Set appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Disable window restoration to avoid class-not-found crashes
        UserDefaults.standard.set(true, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
