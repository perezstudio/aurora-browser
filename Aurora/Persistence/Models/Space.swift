import Foundation
import SwiftData

@Model
final class Space {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var iconName: String
    var order: Int
    var createdAt: Date

    var profile: Profile?

    @Relationship(deleteRule: .cascade, inverse: \Tab.space)
    var tabs: [Tab] = []

    @Relationship(deleteRule: .nullify, inverse: \Bookmark.space)
    var bookmarks: [Bookmark] = []

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#7C6AF7",
        iconName: String = "globe",
        order: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.order = order
        self.createdAt = createdAt
    }
}
