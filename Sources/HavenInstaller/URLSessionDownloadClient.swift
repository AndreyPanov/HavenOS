import Foundation

/// Production `DownloadClient` using URLSession with delegate-based progress.
///
/// Uses delegate-only API (no completion handler) so that progress
/// callbacks are actually delivered by URLSession.
public struct URLSessionDownloadClient: DownloadClient, Sendable {

    public init() {}

    public func download(from url: URL, progress: (@Sendable (Double) -> Void)?) throws -> URL {
        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let task = session.downloadTask(with: url)
        task.resume()
        delegate.semaphore.wait()

        session.invalidateAndCancel()

        if let error = delegate.resultError {
            throw error
        }
        guard let resultURL = delegate.resultURL else {
            throw URLError(.badServerResponse)
        }
        return resultURL
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: (@Sendable (Double) -> Void)?
    let semaphore = DispatchSemaphore(value: 0)
    var resultURL: URL?
    var resultError: Error?

    init(progress: (@Sendable (Double) -> Void)?) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let progress else { return }
        if totalBytesExpectedToWrite > 0 {
            progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        } else {
            progress(-1)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let file = downloadTask.originalRequest?.url?.lastPathComponent ?? "unknown"
            resultError = URLError(
                .badServerResponse,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode) for \(file)"]
            )
            return
        }
        let stableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(location.pathExtension)
        do {
            try FileManager.default.moveItem(at: location, to: stableURL)
            resultURL = stableURL
        } catch {
            resultError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, resultError == nil {
            resultError = error
        }
        semaphore.signal()
    }
}
