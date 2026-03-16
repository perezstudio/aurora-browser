import SwiftUI
import SwiftData

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case profiles = "Profiles"
    case spaces = "Spaces"

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .profiles: "person.crop.circle"
        case .spaces: "square.stack"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsTabButton(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .profiles:
                    ProfilesSettingsView()
                case .spaces:
                    SpacesSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12))
                Text(tab.rawValue)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.primary.opacity(0.1) : Color.primary.opacity(isHovered ? 0.05 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("General settings coming soon")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Profiles

struct ProfilesSettingsView: View {
    @Environment(BrowserState.self) private var browserState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedProfileID: UUID?

    var body: some View {
        HSplitView {
            // Left: profile list
            VStack(spacing: 0) {
                List(browserState.profiles, selection: $selectedProfileID) { profile in
                    Label(profile.name, systemImage: "person.crop.circle")
                        .tag(profile.id)
                }
                .listStyle(.sidebar)

                Divider()

                HStack(spacing: 4) {
                    Button {
                        addProfile()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        removeSelectedProfile()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedProfileID == nil || browserState.profiles.count <= 1)

                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 180, maxWidth: 220)

            // Right: profile detail
            if let profile = browserState.profiles.first(where: { $0.id == selectedProfileID }) {
                ProfileDetailView(profile: profile)
            } else {
                VStack {
                    Spacer()
                    Text("Select a profile")
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
        }
    }

    private func addProfile() {
        let profile = Profile(name: "New Profile")
        modelContext.insert(profile)

        // Create a default space for the new profile
        let space = Space(name: "Default", order: 0)
        space.profile = profile
        let tab = Tab(url: "aurora://newtab", title: "New Tab", order: 0)
        tab.space = space
        space.tabs.append(tab)
        profile.spaces.append(space)
        modelContext.insert(space)

        try? modelContext.save()
        browserState.profiles.append(profile)
        browserState.reloadSpaces()
        selectedProfileID = profile.id
    }

    private func removeSelectedProfile() {
        guard let id = selectedProfileID,
              let profile = browserState.profiles.first(where: { $0.id == id }),
              browserState.profiles.count > 1 else { return }

        // Clean up web views for all tabs in this profile's spaces
        for space in profile.spaces {
            for tab in space.tabs {
                WebViewPool.shared.removeWebView(for: tab.id)
            }
        }
        WebViewPool.shared.removeContext(for: id)

        browserState.profiles.removeAll { $0.id == id }
        modelContext.delete(profile)
        try? modelContext.save()

        // Rebuild spaces from remaining profiles
        browserState.reloadSpaces()
        selectedProfileID = browserState.profiles.first?.id

        // If active space belonged to the deleted profile, switch
        if browserState.activeSpace?.profile == nil || browserState.activeProfileID == nil {
            if let first = browserState.spaces.first {
                browserState.selectSpace(first)
            }
        }
    }
}

struct ProfileDetailView: View {
    @Bindable var profile: Profile

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $profile.name)

                LabeledContent("Created") {
                    Text(profile.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Spaces") {
                    Text("\(profile.spaces.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: profile.name) { _, _ in
            PersistenceController.shared.save()
        }
    }
}

// MARK: - Spaces

struct SpacesSettingsView: View {
    @Environment(BrowserState.self) private var browserState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSpaceID: UUID?

    private var allSpaces: [Space] {
        browserState.profiles.flatMap(\.spaces).sorted { $0.order < $1.order }
    }

    var body: some View {
        HSplitView {
            // Left: space list
            VStack(spacing: 0) {
                List(allSpaces, selection: $selectedSpaceID) { space in
                    HStack(spacing: 8) {
                        Image(systemName: space.iconName)
                            .foregroundStyle(Color(hex: space.colorHex))
                            .frame(width: 16)
                        Text(space.name)
                    }
                    .tag(space.id)
                }
                .listStyle(.sidebar)

                Divider()

                HStack(spacing: 4) {
                    Button {
                        addSpace()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        removeSelectedSpace()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedSpaceID == nil || allSpaces.count <= 1)

                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 180, maxWidth: 220)

            // Right: space detail
            if let space = allSpaces.first(where: { $0.id == selectedSpaceID }) {
                SpaceDetailView(space: space, profiles: browserState.profiles)
            } else {
                VStack {
                    Spacer()
                    Text("Select a space")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if selectedSpaceID == nil {
                selectedSpaceID = browserState.activeSpaceID ?? allSpaces.first?.id
            }
        }
    }

    private func addSpace() {
        let profile = browserState.activeProfile ?? browserState.profiles.first
        guard let profile else { return }
        let maxOrder = allSpaces.map(\.order).max() ?? -1
        let space = Space(name: "New Space", colorHex: "#7C6AF7", iconName: "folder.fill", order: maxOrder + 1)
        space.profile = profile
        let tab = Tab(url: "aurora://newtab", title: "New Tab", order: 0)
        tab.space = space
        space.tabs.append(tab)
        profile.spaces.append(space)
        modelContext.insert(space)
        try? modelContext.save()

        browserState.reloadSpaces()
        selectedSpaceID = space.id
    }

    private func removeSelectedSpace() {
        guard let id = selectedSpaceID,
              let space = allSpaces.first(where: { $0.id == id }),
              allSpaces.count > 1 else { return }

        // Clean up web views
        for tab in space.tabs {
            WebViewPool.shared.removeWebView(for: tab.id)
        }

        let ownerProfile = space.profile
        ownerProfile?.spaces.removeAll { $0.id == id }
        modelContext.delete(space)
        try? modelContext.save()

        browserState.reloadSpaces()
        if browserState.activeSpaceID == id {
            if let first = browserState.spaces.first {
                browserState.selectSpace(first)
            }
        }

        selectedSpaceID = allSpaces.first(where: { $0.id != id })?.id
    }
}

struct SpaceDetailView: View {
    @Bindable var space: Space
    let profiles: [Profile]

    private let colorOptions: [(String, String)] = [
        ("#7C6AF7", "Purple"),
        ("#4A9EF7", "Blue"),
        ("#4ABFF7", "Cyan"),
        ("#4AF7A8", "Green"),
        ("#F7A84A", "Orange"),
        ("#F74A4A", "Red"),
        ("#F74AA8", "Pink"),
        ("#A8A8A8", "Gray"),
    ]

    private let iconOptions = [
        "folder.fill", "globe", "briefcase.fill", "book.fill",
        "star.fill", "heart.fill", "house.fill", "desktopcomputer",
        "gamecontroller.fill", "music.note", "cart.fill", "graduationcap.fill",
    ]

    var body: some View {
        Form {
            Section("Space") {
                TextField("Name", text: $space.name)

                LabeledContent("Color") {
                    HStack(spacing: 6) {
                        ForEach(colorOptions, id: \.0) { hex, _ in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 20, height: 20)
                                .overlay {
                                    if space.colorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture {
                                    space.colorHex = hex
                                }
                        }
                    }
                }

                LabeledContent("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 6), spacing: 4) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(space.iconName == icon ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                                )
                                .onTapGesture {
                                    space.iconName = icon
                                }
                        }
                    }
                }

                Picker("Profile", selection: Binding<UUID>(
                    get: { space.profile?.id ?? UUID() },
                    set: { newID in
                        guard let newProfile = profiles.first(where: { $0.id == newID }),
                              space.profile?.id != newID else { return }
                        let oldProfile = space.profile
                        oldProfile?.spaces.removeAll { $0.id == space.id }
                        space.profile = newProfile
                        newProfile.spaces.append(space)
                        PersistenceController.shared.save()

                        // Destroy existing WebViews — they belong to the old profile's
                        // data store. They'll be lazily recreated with the new profile's
                        // context when the container detects the stale reference.
                        for tab in space.tabs {
                            WebViewPool.shared.removeWebView(for: tab.id)
                        }

                        BrowserState.shared.reloadSpaces()

                        // If this is the active space, re-select it to force
                        // the content pane to recreate the WebView with the new profile
                        if BrowserState.shared.activeSpaceID == space.id {
                            BrowserState.shared.selectSpace(space)
                        }
                    }
                )) {
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }

                LabeledContent("Tabs") {
                    Text("\(space.tabs.count)")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Bookmarks") {
                    Text("\(space.bookmarks.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: space.name) { _, _ in
            PersistenceController.shared.save()
        }
        .onChange(of: space.colorHex) { _, _ in
            PersistenceController.shared.save()
        }
        .onChange(of: space.iconName) { _, _ in
            PersistenceController.shared.save()
        }
    }
}
