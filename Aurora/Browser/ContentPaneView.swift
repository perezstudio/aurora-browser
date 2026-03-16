import SwiftUI

struct ContentPaneView: View {
    @Environment(BrowserState.self) private var browserState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                NavigationBarView()
                    .frame(height: 48)

                ProgressBarView()

                if let tabID = browserState.activeTabID,
                   let profileID = browserState.activeProfileID {
                    ActiveWebViewRepresentable(tabID: tabID, profileID: profileID)
                        .id(tabID)
                } else {
                    EmptyContentView()
                }
            }
            .background(VisualEffectBackground(material: .contentBackground))

            if browserState.isCommandBarVisible {
                CommandBarOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(duration: 0.2), value: browserState.isCommandBarVisible)
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Progress Bar

struct ProgressBarView: View {
    @Environment(BrowserState.self) private var browserState

    var body: some View {
        GeometryReader { geometry in
            if browserState.isLoading {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * browserState.estimatedProgress)
                    .animation(.linear(duration: 0.2), value: browserState.estimatedProgress)
            }
        }
        .frame(height: 2)
    }
}

// MARK: - Empty State

struct EmptyContentView: View {
    var body: some View {
        Color.clear
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Select a tab to start browsing")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
    }
}
