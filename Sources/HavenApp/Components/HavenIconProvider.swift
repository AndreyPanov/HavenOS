import AppKit
import SwiftUI

package enum HavenIconProvider {
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
        if let url = Bundle.module.url(forResource: "HavenMenuTemplate@2x", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return NSImage(systemSymbolName: "house", accessibilityDescription: "Haven") ?? NSImage()
    }
}
