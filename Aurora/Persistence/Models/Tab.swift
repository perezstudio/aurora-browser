import Foundation
import SwiftData

@Model
final class Tab {
    @Attribute(.unique) var id: UUID
    var url: String
    var title: String
    var faviconData: Data?
    var order: Int
    var createdAt: Date
    var lastVisited: Date

    var space: Space?

    init(
        id: UUID = UUID(),
        url: String = "aurora://newtab",
        title: String = "New Tab",
        faviconData: Data? = nil,
        order: Int = 0,
        createdAt: Date = Date(),
        lastVisited: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.faviconData = faviconData
        self.order = order
        self.createdAt = createdAt
        self.lastVisited = lastVisited
    }
}
