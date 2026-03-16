import SwiftUI
import SwiftData

@main
struct AuroraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        PersistenceController.shared.container
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandMenu("Developer") {
                Button("Toggle Web Inspector") {
                    NotificationCenter.default.post(name: .toggleInspector, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.option, .command])
            }
        }
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
}
