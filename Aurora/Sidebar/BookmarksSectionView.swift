import SwiftUI

struct BookmarksSectionView: View {
    @Environment(BrowserState.self) private var browserState
    let bookmarks: [Bookmark]
    let spaceID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(bookmarks) { bookmark in
                BookmarkRow(bookmark: bookmark, isActive: bookmark.id == browserState.activeTabID)
                    .onTapGesture {
                        browserState.activateContent(
                            id: bookmark.id,
                            url: bookmark.url,
                            spaceID: spaceID
                        )
                    }
            }
        }
    }
}

struct BookmarkRow: View {
    let bookmark: Bookmark
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(bookmark.title)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? .white.opacity(0.1) : .clear)
        )
        .contentShape(Rectangle())
    }
}
