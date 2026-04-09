import AppKit
import SwiftUI

/// Displays a service icon — custom image from disk when available, SF Symbol fallback otherwise.
struct ServiceIconView: View {
    let systemName: String
    let imagePath: String?
    let size: CGFloat

    init(systemName: String, imagePath: String? = nil, size: CGFloat = 32) {
        self.systemName = systemName
        self.imagePath = imagePath
        self.size = size
    }

    var body: some View {
        if let path = imagePath, let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        } else {
            Image(systemName: systemName)
                .font(.system(size: size * 0.6))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}
