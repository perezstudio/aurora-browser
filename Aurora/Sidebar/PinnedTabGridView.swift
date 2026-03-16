import SwiftUI

struct PinnedTabGridView: View {
    @Environment(BrowserState.self) private var browserState
    let pinnedTabs: [PinnedTab]
    let spaceID: UUID

    var body: some View {
        GeometryReader { geometry in
            let maxColumns = geometry.size.width >= 280 ? 3 : 2
            let columns = optimalColumnCount(itemCount: pinnedTabs.count, maxColumns: maxColumns)
            let spacing: CGFloat = 6
            let totalSpacing = spacing * CGFloat(columns - 1)
            let itemWidth = (geometry.size.width - totalSpacing) / CGFloat(columns)
            let sorted = pinnedTabs.sorted { $0.order < $1.order }

            let rows = stride(from: 0, to: sorted.count, by: columns).map { start in
                Array(sorted[start..<min(start + columns, sorted.count)])
            }

            VStack(spacing: spacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: spacing) {
                        ForEach(row) { pinnedTab in
                            PinnedTabCell(
                                pinnedTab: pinnedTab,
                                isActive: browserState.activeTab?.url == pinnedTab.url && browserState.activeSpaceID == spaceID,
                                onTap: {
                                    browserState.activateBookmarkOrPin(
                                        url: pinnedTab.url,
                                        in: spaceID
                                    )
                                }
                            )
                            .frame(width: row.count < columns ? itemWidth : nil)
                            .frame(maxWidth: row.count < columns ? nil : .infinity)
                        }
                    }
                }
            }
            .frame(width: geometry.size.width)
        }
        .frame(height: gridHeight)
    }

    private var gridHeight: CGFloat {
        let maxColumns = 3
        let columns = optimalColumnCount(itemCount: pinnedTabs.count, maxColumns: maxColumns)
        let rowCount = pinnedTabs.isEmpty ? 0 : Int(ceil(Double(pinnedTabs.count) / Double(columns)))
        let tabHeight: CGFloat = 36
        let spacing: CGFloat = 6
        return CGFloat(rowCount) * tabHeight + CGFloat(max(0, rowCount - 1)) * spacing
    }

    private func optimalColumnCount(itemCount: Int, maxColumns: Int) -> Int {
        guard itemCount > 0 else { return maxColumns }
        if itemCount < maxColumns { return itemCount }

        let candidates = Array(2...max(2, min(maxColumns + 1, itemCount)))
        var bestCols = maxColumns
        var bestRemainder = Int.max

        for cols in candidates {
            let remainder = itemCount % cols
            if remainder == 0 {
                if bestRemainder != 0 || cols <= bestCols {
                    bestCols = cols
                    bestRemainder = 0
                }
            } else {
                let emptySlots = cols - remainder
                let bestEmpty = bestRemainder == 0 ? 0 : bestCols - bestRemainder
                if emptySlots < bestEmpty || (emptySlots == bestEmpty && cols <= bestCols) {
                    bestCols = cols
                    bestRemainder = remainder
                }
            }
        }

        return bestCols
    }
}

// MARK: - Pinned Tab Cell

struct PinnedTabCell: View {
    let pinnedTab: PinnedTab
    let isActive: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    private var tabColor: Color {
        Color.blue
    }

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? tabColor : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive
                              ? tabColor.opacity(0.12)
                              : Color.primary.opacity(isHovered ? 0.08 : 0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isActive ? tabColor.opacity(0.3) : Color.primary.opacity(0.06),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
