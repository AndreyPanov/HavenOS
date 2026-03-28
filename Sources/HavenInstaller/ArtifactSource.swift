import Foundation

/// Where an artifact can be fetched from.
///
/// Haven supports two source types:
/// - Local file URLs (for bundled or pre-downloaded artifacts)
/// - Remote URLs (for downloading from a server)
public enum ArtifactSource: Equatable, Sendable {

    /// A local file at the given URL.
    case local(URL)

    /// A remote resource at the given URL.
    case remote(URL)

    /// Convenience initializer from a string.
    ///
    /// Strings starting with `http://` or `https://` are treated as remote;
    /// everything else is treated as a local file path.
    public init(string: String) {
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            self = .remote(URL(string: string)!)
        } else {
            self = .local(URL(fileURLWithPath: string))
        }
    }
}
