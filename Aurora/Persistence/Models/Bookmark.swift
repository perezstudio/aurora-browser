import Foundation
import SwiftData

@Model
final class Bookmark {
    @Attribute(.unique) var id: UUID
    var url: String
    var title: String
    var folderName: String?
    var createdAt: Date

    var space: Space?

    init(
        id: UUID = UUID(),
        url: String,
        title: String,
        folderName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.folderName = folderName
        self.createdAt = createdAt
    }
}
