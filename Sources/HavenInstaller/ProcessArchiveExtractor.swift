import Foundation

/// Production `ArchiveExtractor` using system command-line tools.
///
/// Uses `/usr/bin/ditto` for ZIP extraction and `/usr/bin/tar` for
/// tar.gz extraction. Both tools are built into macOS and do not
/// require Homebrew or any user-installed dependencies.
public struct ProcessArchiveExtractor: ArchiveExtractor, Sendable {

    public init() {}

    public func extract(
        archiveURL: URL,
        to destinationDirectory: URL,
        format: ArtifactFormat
    ) throws {
        // Create destination directory
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        switch format {
        case .zip:
            try extractZip(archiveURL: archiveURL, to: destinationDirectory)
        case .tarGz:
            try extractTarGz(archiveURL: archiveURL, to: destinationDirectory)
        case .executable:
            // Single executables are not archives — the installer handles them
            // directly by copying. This should not be called for executables.
            break
        }
    }

    // MARK: - ZIP extraction

    /// Extract a ZIP archive using `/usr/bin/ditto`.
    ///
    /// ditto is preferred over unzip because it preserves extended attributes
    /// and resource forks on macOS, and handles Unicode filenames correctly.
    private func extractZip(archiveURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", archiveURL.path, destination.path]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw ProcessArchiveExtractorError.extractionFailed(
                exitCode: process.terminationStatus,
                stderr: stderr
            )
        }
    }

    // MARK: - tar.gz extraction

    /// Extract a tar.gz archive using `/usr/bin/tar`.
    private func extractTarGz(archiveURL: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archiveURL.path, "-C", destination.path]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw ProcessArchiveExtractorError.extractionFailed(
                exitCode: process.terminationStatus,
                stderr: stderr
            )
        }
    }
}

/// Internal errors from process-based extraction.
/// These are caught by `ArtifactInstaller` and wrapped into
/// `ArtifactInstallerError.extractionFailed`.
enum ProcessArchiveExtractorError: Error, Equatable {
    case extractionFailed(exitCode: Int32, stderr: String)
}
