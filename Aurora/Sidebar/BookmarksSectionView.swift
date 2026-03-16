import SwiftUI

struct BookmarksSectionView: View {
    @Environment(BrowserState.self) private var browserState
    let bookmarks: [Bookmark]
    let spaceID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(bookmarks) { bookmark in
                BookmarkRow(
                    bookmark: bookmark,
                    isActive: browserState.activeTab?.url == bookmark.url && browserState.activeSpaceID == spaceID
                )
                .onTapGesture {
                    browserState.activateBookmarkOrPin(
                        url: bookmark.url,
                        in: spaceID
                    )
                }
            }
        }
    }
}

struct BookmarkRow: View {
    let bookmark: Bookmark
    let isActive: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 16)

            Text(bookmark.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .padding(.leading, 6)

            Spacer()
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
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
