import AppKit
import SwiftUI

package enum HavenIconProvider {
    private static let resourceBundleName = "Haven_HavenAppKit.bundle"
    private static let menuBarResourceNames = ["HavenMenuTemplate@2x", "HavenMenuTemplate"]

    @MainActor
    package static var menuBarIcon: Image {
        let image = menuBarNSImage()
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)

        return Image(nsImage: image)
            .renderingMode(.template)
    }

    @MainActor
    private static func menuBarNSImage() -> NSImage {
        if let url = menuBarImageURL(),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return NSImage(systemSymbolName: "house", accessibilityDescription: "Haven") ?? NSImage()
    }

    package static func menuBarImageURL(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        menuBarImageURL(searchDirectories: resourceSearchDirectories(for: bundle), fileManager: fileManager)
    }

    package static func menuBarImageURL(
        searchDirectories: [URL],
        fileManager: FileManager = .default
    ) -> URL? {
        for directory in searchDirectories {
            for resourceName in menuBarResourceNames {
                let url = directory
                    .appendingPathComponent(resourceName, isDirectory: false)
                    .appendingPathExtension("png")

                if fileManager.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        return nil
    }

    package static func resourceSearchDirectories(for bundle: Bundle) -> [URL] {
        let baseDirectories = [
            bundle.resourceURL,
            bundle.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true),
            bundle.bundleURL,
            bundle.executableURL?.deletingLastPathComponent(),
        ].compactMap { $0 }

        let candidates = baseDirectories.flatMap { directory in
            [
                directory.appendingPathComponent(resourceBundleName, isDirectory: true),
                directory,
            ]
        }

        var seenPaths = Set<String>()
        return candidates.filter { url in
            seenPaths.insert(url.standardizedFileURL.path).inserted
        }
    }
}
