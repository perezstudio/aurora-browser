import Foundation
import SwiftData

@Model
final class HistoryEntry {
    @Attribute(.unique) var id: UUID
    var url: String
    var title: String
    var visitedAt: Date
    var visitCount: Int

    init(
        id: UUID = UUID(),
        url: String,
        title: String,
        visitedAt: Date = Date(),
        visitCount: Int = 1
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.visitedAt = visitedAt
        self.visitCount = visitCount
    }
}
