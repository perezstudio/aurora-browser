import SwiftUI

/// Footer showing workspace dot indicators. Active workspace shows its icon, others show dots.
struct WorkspaceFooterView: View {
    @Environment(BrowserState.self) private var browserState
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 10) {
            // New tab button
            Button {
                browserState.addTab(in: modelContext)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            // Workspace indicators
            HStack(spacing: 8) {
                ForEach(browserState.spaces) { space in
                    let isActive = space.id == browserState.activeSpaceID
                    Button {
                        browserState.selectSpace(space)
                    } label: {
                        if isActive {
                            // Active workspace: show icon
                            Image(systemName: space.iconName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(hex: space.colorHex))
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .fill(Color(hex: space.colorHex).opacity(0.15))
                                )
                        } else {
                            // Inactive workspace: just a dot
                            Circle()
                                .fill(Color(hex: space.colorHex).opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isActive)
                }
            }

            Spacer()

            // Spacer to balance the plus button
            Color.clear.frame(width: 12, height: 12)
        }
        .padding(.horizontal, 12)
    }
}
