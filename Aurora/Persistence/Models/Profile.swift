import Foundation
import SwiftData

@Model
final class Profile {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PinnedTab.profile)
    var pinnedTabs: [PinnedTab] = []

    @Relationship(deleteRule: .nullify, inverse: \Space.profile)
    var spaces: [Space] = []

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
