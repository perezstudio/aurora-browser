import SwiftUI
import SwiftData

/// A single workspace page showing pinned tabs, bookmarks, and regular tabs.
struct WorkspacePageView: View {
    @Environment(BrowserState.self) private var browserState
    let space: Space

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Pinned tabs grid (from this space's profile)
            if let profile = space.profile,
               !profile.pinnedTabs.isEmpty {
                PinnedTabGridView(
                    pinnedTabs: profile.pinnedTabs,
                    spaceID: space.id
                )
                .padding(.bottom, 4)
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
                TabRowView(tab: tab, spaceID: space.id)
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

    @State private var isHovered = false

    private var isExpanded: Bool {
        browserState.isBookmarksVisible(for: space.id)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Folder icon with animated transition
            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: space.colorHex) ?? .blue)
                .frame(width: 18)

            Text(space.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .padding(.leading, 6)

            Spacer()
        }
        .frame(height: 32)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            browserState.toggleBookmarksVisibility(for: space.id)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Tab Row

struct TabRowView: View {
    @Environment(BrowserState.self) private var browserState
    let tab: Tab
    let spaceID: UUID

    @State private var isHovered = false

    private var isActive: Bool {
        tab.id == browserState.activeTabID
    }

    var body: some View {
        HStack(spacing: 0) {
            // Favicon placeholder
            Image(systemName: "globe")
                .font(.system(size: 13))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 16)

            // Page title
            Text(tab.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .padding(.leading, 6)

            Spacer(minLength: 0)

            // Close button on hover
            if isHovered {
                Button {
                    let modelContext = PersistenceController.shared.container.mainContext
                    browserState.closeTab(tab, in: modelContext)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.hoverButton(size: .small))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(.bar)
                .opacity(isActive ? 1 : 0)
        }
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.08))
                .opacity(!isActive && isHovered ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            browserState.selectTab(tab)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
