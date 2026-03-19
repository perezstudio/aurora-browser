import SwiftUI
import SwiftData

struct NavigationBarView: View {
    @Environment(BrowserState.self) private var browserState

    var body: some View {
        if let tab = browserState.activeTab {
            NavigationBarContent(tab: tab)
        } else {
            HStack { Spacer() }
                .frame(height: 48)
        }
    }
}

// MARK: - Content (uses @Bindable for reactive Tab properties)

private struct NavigationBarContent: View {
    @Bindable var tab: Tab
    @Environment(BrowserState.self) private var browserState
    @State private var addressText: String = ""
    @FocusState private var isAddressBarFocused: Bool
    @State private var showExtensionsPopover: Bool = false

    private var isDevMode: Bool {
        tab.url.contains("localhost") || tab.url.contains("127.0.0.1")
    }

    private var hasActiveExtensions: Bool {
        guard let profileID = browserState.activeProfileID else { return false }
        return ExtensionManager.shared.enabledExtensionCount(for: profileID) > 0
    }

    var body: some View {
        HStack(spacing: 8) {
            // Back
            Button {
                browserState.activeWebView()?.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.hoverButton(size: .large))
            .disabled(!tab.canGoBack)

            // Forward
            Button {
                browserState.activeWebView()?.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.hoverButton(size: .large))
            .disabled(!tab.canGoForward)

            // Reload / Stop
            Button {
                if tab.isLoading {
                    browserState.activeWebView()?.stopLoading()
                } else {
                    browserState.activeWebView()?.reload()
                }
            } label: {
                Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
            }
            .buttonStyle(.hoverButton(size: .large))

            // Address bar
            AddressBarView(text: $addressText, isFocused: $isAddressBarFocused) {
                browserState.navigateToURL(addressText)
            }

            // Copy URL
            Button {
                if !tab.url.isEmpty, tab.url != "aurora://newtab" {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tab.url, forType: .string)
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.hoverButton(size: .large))
            .help("Copy URL")

            // Developer mode buttons (visible for localhost URLs)
            if isDevMode {
                Button {
                    browserState.activeWebView()?.toggleInspector()
                } label: {
                    Image(systemName: "hammer")
                }
                .buttonStyle(.hoverButton(size: .large))
                .help("Web Inspector")

                Button {
                    browserState.activeWebView()?.showInspector()
                } label: {
                    Image(systemName: "network")
                }
                .buttonStyle(.hoverButton(size: .large))
                .help("Network")

                Button {
                    browserState.activeWebView()?.showInspector()
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.hoverButton(size: .large))
                .help("Console")
            }

            // Extensions
            if hasActiveExtensions {
                Button {
                    showExtensionsPopover.toggle()
                } label: {
                    Image(systemName: "puzzlepiece.extension")
                }
                .buttonStyle(.hoverButton(size: .large))
                .help("Extensions")
                .popover(isPresented: $showExtensionsPopover, arrowEdge: .bottom) {
                    ExtensionsPopoverView()
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .onAppear {
            addressText = cleanDisplayURL(tab.url)
        }
        .onChange(of: tab.url) { _, newURL in
            if !isAddressBarFocused {
                addressText = cleanDisplayURL(newURL)
            }
        }
    }

    private func cleanDisplayURL(_ url: String) -> String {
        guard url != "aurora://newtab" else { return "" }
        return url
    }
}

// MARK: - Address Bar

struct AddressBarView: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onCommit: () -> Void

    var body: some View {
        TextField("Search or enter URL", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
            )
            .focused(isFocused)
            .onSubmit {
                onCommit()
            }
    }
}

// MARK: - Extensions Popover

struct ExtensionsPopoverView: View {
    @Environment(BrowserState.self) private var browserState
    @Environment(\.modelContext) private var modelContext
    @State private var hoveredID: UUID?

    private var extensions: [InstalledExtension] {
        guard let profileID = browserState.activeProfileID else { return [] }
        var descriptor = FetchDescriptor<InstalledExtension>(
            predicate: #Predicate { $0.profileID == profileID && $0.isEnabled == true }
        )
        descriptor.sortBy = [SortDescriptor(\.name)]
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Extensions")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            if extensions.isEmpty {
                Text("No extensions enabled")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(extensions) { ext in
                    Button {
                        triggerExtension(ext)
                    } label: {
                        HStack(spacing: 8) {
                            if let data = ext.iconData, let nsImage = NSImage(data: data) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                            } else {
                                extensionPlaceholderIcon
                            }

                            Text(ext.name)
                                .font(.system(size: 13))
                                .lineLimit(1)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(hoveredID == ext.id ? Color.white.opacity(0.1) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        hoveredID = isHovered ? ext.id : nil
                    }
                }
            }
        }
        .frame(width: 220)
        .padding(.vertical, 4)
    }

    private func triggerExtension(_ ext: InstalledExtension) {
        guard let profileID = browserState.activeProfileID else { return }
        let tabID = browserState.activeTabID
        ExtensionManager.shared.performAction(
            bundleIdentifier: ext.bundleIdentifier,
            profileID: profileID,
            tabID: tabID
        )
    }

    private var extensionPlaceholderIcon: some View {
        Image(systemName: "puzzlepiece.extension")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
    }
}
