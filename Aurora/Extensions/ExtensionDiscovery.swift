import Foundation
import AppKit

@MainActor
final class ExtensionDiscovery {

    struct DiscoveredExtension: Identifiable {
        let id: String // bundleIdentifier
        let appName: String
        let appexPath: String
        let bundleIdentifier: String
        let displayName: String
        let version: String
        let extensionDescription: String
        let iconData: Data?
    }

    static func scan() async -> [DiscoveredExtension] {
        guard aurora_ext_is_available() else { return [] }

        return await Task.detached(priority: .userInitiated) {
            var results: [DiscoveredExtension] = []
            let fm = FileManager.default

            var searchDirs: [URL] = []
            searchDirs.append(URL(fileURLWithPath: "/Applications"))
            if let home = fm.homeDirectoryForCurrentUser as URL? {
                searchDirs.append(home.appendingPathComponent("Applications"))
            }

            for dir in searchDirs {
                guard let apps = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for appURL in apps where appURL.pathExtension == "app" {
                    let pluginsDir = appURL.appendingPathComponent("Contents/PlugIns")
                    guard let plugins = try? fm.contentsOfDirectory(
                        at: pluginsDir, includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) else { continue }

                    for pluginURL in plugins where pluginURL.pathExtension == "appex" {
                        guard let ext = Self.checkAppex(at: pluginURL, appName: appURL.deletingPathExtension().lastPathComponent) else { continue }
                        results.append(ext)
                    }
                }
            }

            return results
        }.value
    }

    private nonisolated static func checkAppex(at url: URL, appName: String) -> DiscoveredExtension? {
        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let plistData = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return nil
        }

        // Check extension point identifier
        guard let nsExtension = plist["NSExtension"] as? [String: Any],
              let pointID = nsExtension["NSExtensionPointIdentifier"] as? String,
              pointID == "com.apple.Safari.web-extension" else {
            return nil
        }

        guard let bundleID = plist["CFBundleIdentifier"] as? String else { return nil }

        // Read all metadata from Info.plist — do NOT call WKWebExtension APIs
        // during scanning. WebKit's initWithAppExtensionBundle: can crash (EXC_BREAKPOINT)
        // on certain .appex bundles. We only touch WebKit when actually loading.
        let displayName = plist["CFBundleDisplayName"] as? String
            ?? plist["CFBundleName"] as? String
            ?? appName

        let version = plist["CFBundleShortVersionString"] as? String ?? "1.0"

        // Try to read the extension's manifest.json for a description
        let manifestURL = url.appendingPathComponent("Contents/Resources/manifest.json")
        var description = ""
        if let manifestData = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] {
            description = manifest["description"] as? String ?? ""
        }

        // Get icon from the parent .app bundle
        let appURL = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var iconData: Data? = nil
        if let appBundle = Bundle(url: appURL),
           let image = appBundle.image(forResource: NSImage.applicationIconName) ?? NSWorkspace.shared.icon(forFile: appURL.path) as NSImage? {
            let targetSize = NSSize(width: 64, height: 64)
            let resized = NSImage(size: targetSize)
            resized.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: targetSize))
            resized.unlockFocus()
            if let tiff = resized.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff) {
                iconData = bitmap.representation(using: .png, properties: [:])
            }
        }

        return DiscoveredExtension(
            id: bundleID,
            appName: appName,
            appexPath: url.path,
            bundleIdentifier: bundleID,
            displayName: displayName,
            version: version,
            extensionDescription: description,
            iconData: iconData
        )
    }
}
