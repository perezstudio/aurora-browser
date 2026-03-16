import SwiftUI

/// A single workspace page showing pinned tabs, bookmarks, and regular tabs.
struct WorkspacePageView: View {
    @Environment(BrowserState.self) private var browserState
    let space: Space

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Pinned tabs grid (from profile, shared across workspaces)
            if let profile = browserState.activeProfile,
               !profile.pinnedTabs.isEmpty {
                PinnedTabGridView(
                    pinnedTabs: profile.pinnedTabs,
                    spaceID: space.id
                )
            }

            // Workspace header with bookmark toggle
            WorkspaceHeaderView(space: space)

            // Bookmarks section (toggleable)
            if browserState.isBookmarksVisible(for: space.id),
               !space.bookmarks.isEmpty {
                BookmarksSectionView(
                    bookmarks: space.bookmarks,
                    spaceID: space.id
                )
            }

            // Divider before tabs
            if !space.tabs.isEmpty {
                Divider()
                    .padding(.vertical, 4)
            }

            // Normal tabs list
            ForEach(space.tabs.sorted(by: { $0.order < $1.order })) { tab in
                TabRowView(tab: tab)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Workspace Header

struct WorkspaceHeaderView: View {
    @Environment(BrowserState.self) private var browserState
    let space: Space

    var body: some View {
        Button {
            browserState.toggleBookmarksVisibility(for: space.id)
        } label: {
            HStack(spacing: 6) {
                Text(space.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Image(systemName: browserState.isBookmarksVisible(for: space.id)
                      ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
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
