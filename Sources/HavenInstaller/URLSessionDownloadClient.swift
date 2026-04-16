import Foundation

/// Production `DownloadClient` using URLSession synchronous data download.
///
/// Downloads the resource to a temporary file in the system temp directory.
/// The caller is responsible for moving or cleaning up the file.
public struct URLSessionDownloadClient: DownloadClient, Sendable {

    public init() {}

    public func download(from url: URL) throws -> URL {
        // Use a semaphore to make the async URLSession call synchronous.
        // This is acceptable because artifact installation is not on the main thread.
        let semaphore = DispatchSemaphore(value: 0)

        var resultURL: URL?
        var resultError: Error?

        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            if let error = error {
                resultError = error
            } else if let httpResponse = response as? HTTPURLResponse,
                      !(200...299).contains(httpResponse.statusCode) {
                resultError = URLError(
                    .badServerResponse,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode) for \(url.lastPathComponent)"]
                )
            } else if let localURL = localURL {
                // URLSession deletes the temp file after the completion handler returns,
                // so we need to move it to a stable location.
                let stableURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.moveItem(at: localURL, to: stableURL)
                    resultURL = stableURL
                } catch {
                    resultError = error
                }
            } else {
                resultError = URLError(.badServerResponse)
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let error = resultError {
            throw error
        }
        guard let url = resultURL else {
            throw URLError(.badServerResponse)
        }
        return url
    }
}
