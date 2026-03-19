import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            Profile.self,
            Space.self,
            Tab.self,
            PinnedTab.self,
            HistoryEntry.self,
            Bookmark.self,
            InstalledExtension.self,
        ])

        // Store in Application Support/Aurora/Aurora.store
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let auroraDir = appSupport.appendingPathComponent("Aurora", isDirectory: true)
        try? FileManager.default.createDirectory(at: auroraDir, withIntermediateDirectories: true)
        let storeURL = auroraDir.appendingPathComponent("Aurora.store")

        let configuration = ModelConfiguration("Aurora", schema: schema, url: storeURL)

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Schema mismatch — destroy old store and recreate (pre-release only)
            try? FileManager.default.removeItem(at: storeURL)
            // Also remove WAL/SHM files
            let walURL = storeURL.appendingPathExtension("wal")
            let shmURL = storeURL.appendingPathExtension("shm")
            try? FileManager.default.removeItem(at: walURL)
            try? FileManager.default.removeItem(at: shmURL)
            do {
                container = try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
    }

    func seedDefaultSpacesIfNeeded() {
        let context = container.mainContext

        // Check if we already have profiles
        let profileDescriptor = FetchDescriptor<Profile>()
        if let count = try? context.fetchCount(profileDescriptor), count > 0 { return }

        // Create default profile
        let profile = Profile(name: "Personal")

        let spaceDefs: [(String, String, String, Int)] = [
            ("Personal", "#7C6AF7", "person.fill", 0),
            ("Work", "#4A9EF7", "briefcase.fill", 1),
            ("Research", "#F7A84A", "book.fill", 2),
        ]

        for (name, color, icon, order) in spaceDefs {
            let space = Space(name: name, colorHex: color, iconName: icon, order: order)
            space.profile = profile
            let tab = Tab(url: "aurora://newtab", title: "New Tab", order: 0)
            tab.space = space
            space.tabs.append(tab)
            profile.spaces.append(space)
            context.insert(space)
        }

        context.insert(profile)
        try? context.save()
    }

    func recordVisit(url: String, title: String) {
        let context = container.mainContext

        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.url == url }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            existing.visitCount += 1
            existing.visitedAt = Date()
            existing.title = title
        } else {
            let entry = HistoryEntry(url: url, title: title)
            context.insert(entry)
        }

        try? context.save()
    }

    func save() {
        try? container.mainContext.save()
    }
}
