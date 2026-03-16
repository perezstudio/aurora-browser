import SwiftUI

struct NavigationBarView: View {
    @Environment(BrowserState.self) private var browserState
    @State private var addressText: String = ""
    @FocusState private var isAddressBarFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Back
            Button {
                browserState.activeWebView()?.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.hoverButton(size: .large))
            .disabled(!browserState.canGoBack)

            // Forward
            Button {
                browserState.activeWebView()?.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.hoverButton(size: .large))
            .disabled(!browserState.canGoForward)

            // Reload / Stop
            Button {
                if browserState.isLoading {
                    browserState.activeWebView()?.stopLoading()
                } else {
                    browserState.activeWebView()?.reload()
                }
            } label: {
                Image(systemName: browserState.isLoading ? "xmark" : "arrow.clockwise")
            }
            .buttonStyle(.hoverButton(size: .large))

            // Address bar
            AddressBarView(text: $addressText, isFocused: $isAddressBarFocused) {
                browserState.navigateToURL(addressText)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .onChange(of: browserState.currentURL) { _, newURL in
            if !isAddressBarFocused {
                addressText = cleanDisplayURL(newURL)
            }
        }
    }

    private func cleanDisplayURL(_ url: String?) -> String {
        guard let url, url != "aurora://newtab" else { return "" }
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
