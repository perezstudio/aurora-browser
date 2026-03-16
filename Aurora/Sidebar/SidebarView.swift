import SwiftUI

struct SidebarView: View {
    @Environment(BrowserState.self) private var browserState

    var body: some View {
        VStack(spacing: 0) {
            // Sidebar toolbar with collapse toggle
            SidebarToolbarView()
                .frame(height: 52)

            // Workspace pages (swipe horizontally to switch)
            WorkspacePagerView()

            Divider()

            // Footer with workspace dot indicators
            WorkspaceFooterView()
                .frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground(material: .sidebar))
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Sidebar Toolbar

struct SidebarToolbarView: View {
    var body: some View {
        HStack {
            Spacer()

            Button {
                NotificationCenter.default.post(name: .toggleSidebar, object: nil)
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .buttonStyle(.hoverButton(size: .large))
        }
        .padding(.horizontal, 12)
    }
}
