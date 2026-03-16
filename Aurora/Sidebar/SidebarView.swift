import SwiftUI

struct SidebarView: View {
    @Environment(BrowserState.self) private var browserState
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            SpaceSwitcherView()
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if let space = browserState.activeSpace {
                PinnedTabsView(pinnedTabs: space.pinnedTabs)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                Divider()
                    .padding(.vertical, 8)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(space.tabs.sorted(by: { $0.order < $1.order })) { tab in
                            TabRowView(tab: tab)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            Spacer()

            SidebarBottomBar()
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Space Switcher

struct SpaceSwitcherView: View {
    @Environment(BrowserState.self) private var browserState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(browserState.spaces) { space in
                SpaceChip(space: space, isActive: space.id == browserState.activeSpaceID)
                    .onTapGesture {
                        browserState.selectSpace(space)
                    }
            }
            Spacer()
        }
    }
}

struct SpaceChip: View {
    let space: Space
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: space.iconName)
                .font(.system(size: 11))
            Text(space.name)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(hex: space.colorHex).opacity(0.3) : Color.clear)
        )
        .foregroundStyle(isActive ? Color(hex: space.colorHex) : .secondary)
    }
}

// MARK: - Pinned Tabs

struct PinnedTabsView: View {
    let pinnedTabs: [PinnedTab]

    var body: some View {
        if !pinnedTabs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pinnedTabs.sorted(by: { $0.order < $1.order })) { tab in
                        VStack(spacing: 2) {
                            Image(systemName: "globe")
                                .font(.system(size: 16))
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.quaternary)
                                )
                            Text(tab.title)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .frame(maxWidth: 48)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Tab Row

struct TabRowView: View {
    @Environment(BrowserState.self) private var browserState
    let tab: Tab

    private var isActive: Bool {
        tab.id == browserState.activeTabID
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? .white.opacity(0.1) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            browserState.selectTab(tab)
        }
    }
}

// MARK: - Bottom Bar

struct SidebarBottomBar: View {
    @Environment(BrowserState.self) private var browserState
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack {
            Button {
                browserState.addTab(in: modelContext)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                browserState.isSidebarCollapsed.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }
}
