/// Shared scan/index status for content-based capabilities (Books, Music).
public enum ScanStatus: Sendable, Equatable {
    /// No scan in progress.
    case idle
    /// Scan is running.
    case scanning
    /// Scan completed successfully.
    case complete
    /// Scan failed.
    case error(String)
}
