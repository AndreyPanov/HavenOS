import Foundation

/// Abstraction over downloading a remote URL to a local file.
///
/// The protocol enables testing without real network requests.
/// `URLSessionDownloadClient` is the production implementation;
/// tests can provide a mock that returns local fixture files.
public protocol DownloadClient: Sendable {

    /// Download the resource at `url` to a local temporary file.
    ///
    /// - Parameters:
    ///   - url: The remote URL to download.
    ///   - progress: Optional callback with fraction completed (0.0–1.0), or -1 if unknown.
    /// - Returns: The local file URL where the downloaded data was saved.
    /// - Throws: If the download fails.
    func download(from url: URL, progress: (@Sendable (Double) -> Void)?) throws -> URL
}

extension DownloadClient {
    public func download(from url: URL) throws -> URL {
        try download(from: url, progress: nil)
    }
}
