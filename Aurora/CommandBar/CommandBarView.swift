import SwiftUI
import SwiftData

struct CommandBarOverlay: View {
    @Environment(BrowserState.self) private var browserState

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    browserState.isCommandBarVisible = false
                }

            CommandBarPanel()
                .frame(maxWidth: 600, maxHeight: 400)
        }
    }
}

struct CommandBarPanel: View {
    @Environment(BrowserState.self) private var browserState
    @Environment(\.modelContext) private var modelContext
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var results: [CommandResult] = []

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search or enter URL", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .onSubmit {
                        commitSelection()
                    }
            }
            .padding(16)

            Divider()

            // Results
            if !results.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            CommandResultRow(result: result, isSelected: index == selectedIndex)
                                .onTapGesture {
                                    selectedIndex = index
                                    commitSelection()
                                }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onChange(of: query) { _, newQuery in
            updateResults(for: newQuery)
            selectedIndex = 0
        }
        .onAppear {
            query = ""
            results = []
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < results.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.escape) {
            browserState.isCommandBarVisible = false
            return .handled
        }
    }

    private func updateResults(for query: String) {
        guard !query.isEmpty else {
            results = []
            return
        }

        var newResults: [CommandResult] = []

        // Direct URL option
        if query.contains(".") && !query.contains(" ") {
            let url = URLResolver.resolve(query)
            newResults.append(CommandResult(title: url.absoluteString, subtitle: "Navigate", icon: "globe", url: url.absoluteString))
        }

        // History matches
        let historyDescriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate {
                $0.url.localizedStandardContains(query) ||
                $0.title.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.visitCount, order: .reverse)]
        )
        if let history = try? modelContext.fetch(historyDescriptor) {
            for entry in history.prefix(5) {
                newResults.append(CommandResult(title: entry.title, subtitle: entry.url, icon: "clock", url: entry.url))
            }
        }

        // Bookmark matches
        let bookmarkDescriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate {
                $0.url.localizedStandardContains(query) ||
                $0.title.localizedStandardContains(query)
            }
        )
        if let bookmarks = try? modelContext.fetch(bookmarkDescriptor) {
            for bookmark in bookmarks.prefix(3) {
                newResults.append(CommandResult(title: bookmark.title, subtitle: bookmark.url, icon: "bookmark", url: bookmark.url))
            }
        }

        // Google search fallback
        let searchURL = URLResolver.resolve(query)
        newResults.append(CommandResult(title: "Search Google for \"\(query)\"", subtitle: "google.com", icon: "magnifyingglass", url: searchURL.absoluteString))

        results = newResults
    }

    private func commitSelection() {
        guard !results.isEmpty, selectedIndex < results.count else { return }
        let result = results[selectedIndex]
        browserState.navigateToURL(result.url)
        browserState.isCommandBarVisible = false
    }
}

// MARK: - Command Result

struct CommandResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let url: String
}

struct CommandResultRow: View {
    let result: CommandResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? .white.opacity(0.1) : .clear)
        )
    }
}
