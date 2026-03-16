import SwiftUI

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

    private var isDevMode: Bool {
        tab.url.contains("localhost") || tab.url.contains("127.0.0.1")
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
