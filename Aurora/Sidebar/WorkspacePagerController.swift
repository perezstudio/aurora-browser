import SwiftUI

/// Horizontal paging ScrollView with snap-to-page behavior for workspace switching.
struct WorkspacePagerView: View {
    @Environment(BrowserState.self) private var browserState
    @State private var scrolledSpaceID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(browserState.spaces) { space in
                    WorkspacePageView(space: space)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledSpaceID)
        .onChange(of: scrolledSpaceID) { _, newID in
            guard let newID,
                  newID != browserState.activeSpaceID,
                  let space = browserState.spaces.first(where: { $0.id == newID }) else { return }
            browserState.selectSpace(space)
        }
        .onChange(of: browserState.activeSpaceID) { _, newID in
            guard let newID, newID != scrolledSpaceID else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                scrolledSpaceID = newID
            }
        }
        .onAppear {
            scrolledSpaceID = browserState.activeSpaceID
        }
    }
}
