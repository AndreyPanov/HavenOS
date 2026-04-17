import AppKit
import SwiftUI

/// Displays a service icon — remote URL, local image, or SF Symbol fallback.
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
        if let path = imagePath, let url = URL(string: path), url.scheme == "https" || url.scheme == "http" {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
                default:
                    sfSymbolFallback
                }
            }
        } else if let path = imagePath, let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        } else {
            sfSymbolFallback
        }
    }

    private var sfSymbolFallback: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.6))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}
