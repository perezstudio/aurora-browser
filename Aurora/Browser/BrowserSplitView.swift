import SwiftUI

struct BrowserSplitView: View {
    @Environment(BrowserState.self) private var browserState

    var body: some View {
        HStack(spacing: 0) {
            if !browserState.isSidebarCollapsed {
                SidebarView()
                    .frame(width: 240)
                    .transition(.move(edge: .leading))

                Divider()
            }

            VStack(spacing: 0) {
                NavigationBarView()
                    .frame(height: 48)

                ProgressBarView()

                WebContentView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: browserState.isSidebarCollapsed)
    }
}

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
