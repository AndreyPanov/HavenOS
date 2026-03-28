import Foundation

/// Writes data to a file atomically by writing to a temporary file
/// in the same directory and then renaming.
///
/// This ensures that readers never see a partially written file.
/// Parent directories are created if they do not exist.
public enum AtomicFileWriter {

    /// Write `data` to `destination` atomically.
    ///
    /// 1. Creates parent directories if needed.
    /// 2. Writes to a temporary file in the same directory.
    /// 3. Renames the temporary file to the destination.
    ///
    /// - Parameters:
    ///   - data: The bytes to write.
    ///   - destination: The final file URL.
    public static func write(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        // Write to a temporary file in the same directory so rename is atomic.
        let tempName = ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
        let tempURL = directory.appendingPathComponent(tempName)

        do {
            try data.write(to: tempURL, options: .atomic)
            // On APFS / HFS+, moveItem within the same volume is atomic.
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
        } catch {
            // Clean up the temp file on failure.
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }
}
