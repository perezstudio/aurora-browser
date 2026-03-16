import Foundation
import SwiftData

@Model
final class PinnedTab {
    @Attribute(.unique) var id: UUID
    var url: String
    var title: String
    var faviconData: Data?
    var order: Int

    var profile: Profile?

    init(
        id: UUID = UUID(),
        url: String,
        title: String,
        faviconData: Data? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.faviconData = faviconData
        self.order = order
    }
}
