import SwiftUI
import SwiftData

struct ExtensionsSettingsView: View {
    @Environment(BrowserState.self) private var browserState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedExtensionID: UUID?
    @State private var selectedProfileID: UUID?
    @State private var discoveredExtensions: [ExtensionDiscovery.DiscoveredExtension] = []
    @State private var isScanning: Bool = false

    private var currentProfileID: UUID? {
        selectedProfileID ?? browserState.activeProfileID ?? browserState.profiles.first?.id
    }

    private var extensions: [InstalledExtension] {
        guard let profileID = currentProfileID else { return [] }
        var descriptor = FetchDescriptor<InstalledExtension>(
            predicate: #Predicate { $0.profileID == profileID }
        )
        descriptor.sortBy = [SortDescriptor(\.installedAt)]
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Discovered extensions not yet installed for this profile
    private var availableExtensions: [ExtensionDiscovery.DiscoveredExtension] {
        let installedBundleIDs = Set(extensions.map(\.bundleIdentifier))
        return discoveredExtensions.filter { !installedBundleIDs.contains($0.bundleIdentifier) }
    }

    var body: some View {
        HSplitView {
            // Left: extension list
            VStack(spacing: 0) {
                // Profile selector
                if browserState.profiles.count > 1 {
                    Picker("Profile", selection: Binding(
                        get: { currentProfileID ?? UUID() },
                        set: { selectedProfileID = $0; selectedExtensionID = nil }
                    )) {
                        ForEach(browserState.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(8)

                    Divider()
                }

                if extensions.isEmpty && availableExtensions.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("No extensions found")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text("Install Safari extensions from\nthe Mac App Store, then scan.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(selection: $selectedExtensionID) {
                        if !extensions.isEmpty {
                            Section("Enabled") {
                                ForEach(extensions) { ext in
                                    HStack(spacing: 8) {
                                        extensionIcon(for: ext)
                                            .frame(width: 24, height: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ext.name)
                                                .font(.system(size: 13))
                                            Text("v\(ext.version)")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                        Toggle("", isOn: Binding(
                                            get: { ext.isEnabled },
                                            set: { newValue in
                                                guard let profileID = currentProfileID else { return }
                                                ExtensionManager.shared.setEnabled(
                                                    ext.bundleIdentifier,
                                                    profileID: profileID,
                                                    enabled: newValue,
                                                    modelContext: modelContext
                                                )
                                            }
                                        ))
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                        .controlSize(.mini)
                                    }
                                    .tag(ext.id)
                                }
                            }
                        }

                        if !availableExtensions.isEmpty {
                            Section("Available") {
                                ForEach(availableExtensions) { ext in
                                    HStack(spacing: 8) {
                                        if let data = ext.iconData, let nsImage = NSImage(data: data) {
                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .frame(width: 24, height: 24)
                                        } else {
                                            Image(systemName: "puzzlepiece.extension")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 24, height: 24)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ext.displayName)
                                                .font(.system(size: 13))
                                            Text(ext.appName)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                        Button("Add") {
                                            addExtension(ext)
                                        }
                                        .controlSize(.small)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }

                Divider()

                HStack(spacing: 4) {
                    Button {
                        removeSelectedExtension()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedExtensionID == nil)

                    Spacer()

                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    }

                    Button("Scan") {
                        scanForExtensions()
                    }
                    .controlSize(.small)
                    .disabled(isScanning)
                }
                .padding(8)
            }
            .frame(minWidth: 200, maxWidth: 280)

            // Right: extension detail
            if let ext = extensions.first(where: { $0.id == selectedExtensionID }) {
                ExtensionDetailView(extension: ext)
            } else {
                VStack {
                    Spacer()
                    Text("Select an extension")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if selectedProfileID == nil {
                selectedProfileID = browserState.activeProfileID ?? browserState.profiles.first?.id
            }
            scanForExtensions()
        }
    }

    private func scanForExtensions() {
        isScanning = true
        Task {
            discoveredExtensions = await ExtensionDiscovery.scan()
            isScanning = false
        }
    }

    private func addExtension(_ ext: ExtensionDiscovery.DiscoveredExtension) {
        guard let profileID = currentProfileID else { return }
        ExtensionManager.shared.loadExtension(
            appexPath: ext.appexPath,
            profileID: profileID,
            modelContext: modelContext
        )
    }

    private func removeSelectedExtension() {
        guard let extID = selectedExtensionID,
              let ext = extensions.first(where: { $0.id == extID }) else { return }
        guard let profileID = currentProfileID else { return }

        ExtensionManager.shared.unloadExtension(
            bundleIdentifier: ext.bundleIdentifier,
            profileID: profileID,
            modelContext: modelContext
        )
        selectedExtensionID = nil
    }

    @ViewBuilder
    private func extensionIcon(for ext: InstalledExtension) -> some View {
        if let data = ext.iconData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

struct ExtensionDetailView: View {
    let `extension`: InstalledExtension

    var body: some View {
        Form {
            Section("Extension") {
                LabeledContent("Name") {
                    Text(`extension`.name)
                        .foregroundStyle(.primary)
                }

                LabeledContent("Version") {
                    Text(`extension`.version)
                        .foregroundStyle(.secondary)
                }

                if !`extension`.extensionDescription.isEmpty {
                    LabeledContent("Description") {
                        Text(`extension`.extensionDescription)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Bundle ID") {
                    Text(`extension`.bundleIdentifier)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }

                LabeledContent("Installed") {
                    Text(`extension`.installedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }

                if !`extension`.grantedPermissions.isEmpty {
                    LabeledContent("Permissions") {
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(`extension`.grantedPermissions, id: \.self) { permission in
                                Text(permission)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
