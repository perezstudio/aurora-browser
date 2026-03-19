import Foundation
import SwiftData

@Model
final class InstalledExtension {
    @Attribute(.unique) var id: UUID
    var bundleIdentifier: String
    var appexPath: String = ""
    var name: String
    var version: String
    var extensionDescription: String
    var isEnabled: Bool
    var profileID: UUID
    var installedAt: Date
    var grantedPermissions: [String]
    var iconData: Data?

    init(bundleIdentifier: String,
         appexPath: String,
         name: String,
         version: String,
         extensionDescription: String,
         isEnabled: Bool = true,
         profileID: UUID,
         grantedPermissions: [String] = [],
         iconData: Data? = nil) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.appexPath = appexPath
        self.name = name
        self.version = version
        self.extensionDescription = extensionDescription
        self.isEnabled = isEnabled
        self.profileID = profileID
        self.installedAt = Date()
        self.grantedPermissions = grantedPermissions
        self.iconData = iconData
    }
}
