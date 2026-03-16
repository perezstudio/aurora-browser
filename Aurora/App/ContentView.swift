import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var browserState = BrowserState.shared

    var body: some View {
        ZStack {
            BrowserSplitView()
                .environment(browserState)

            if browserState.isCommandBarVisible {
                CommandBarOverlay()
                    .environment(browserState)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(duration: 0.2), value: browserState.isCommandBarVisible)
        .onAppear {
            PersistenceController.shared.seedDefaultSpacesIfNeeded()
            browserState.loadFromStore(modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
            browserState.addTab(in: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
            browserState.closeActiveTab(in: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCommandBar)) { _ in
            browserState.isCommandBarVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateBack)) { _ in
            browserState.activeWebView()?.goBack()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateForward)) { _ in
            browserState.activeWebView()?.goForward()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reloadPage)) { _ in
            browserState.activeWebView()?.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
            browserState.activeWebView()?.toggleInspector()
        }
    }
}
