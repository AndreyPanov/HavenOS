import Foundation
import HavenCore

/// Downloads and places provision files with path safety enforcement.
///
/// All destinations are validated to stay inside the service root directory.
/// Downloads are atomic: written to a temp file first, then moved into place.
/// Existing files are skipped (idempotent).
public struct ProvisionDownloader: Sendable {

    private nonisolated(unsafe) let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Execute a single provision, downloading source to destination atomically.
    ///
    /// - Parameters:
    ///   - provision: The resolved provision (variables already expanded).
    ///   - serviceRoot: The service's root directory — destination must stay inside.
    /// - Throws: ``ProvisionError`` if path escapes, download fails, or write fails.
    public func execute(provision: Provision, serviceRoot: URL) throws {
        let destURL = URL(fileURLWithPath: provision.destination).standardizedFileURL
        let rootPath = serviceRoot.standardizedFileURL.path

        // Path safety: destination must be inside service root
        guard destURL.path.hasPrefix(rootPath) else {
            throw ProvisionError.pathEscapesServiceRoot(
                destination: provision.destination,
                serviceRoot: rootPath
            )
        }

        // Reject path traversal components
        let components = destURL.pathComponents
        guard !components.contains("..") else {
            throw ProvisionError.pathEscapesServiceRoot(
                destination: provision.destination,
                serviceRoot: rootPath
            )
        }

        // Skip if file already exists (idempotent)
        guard !fileManager.fileExists(atPath: destURL.path) else {
            return
        }

        // Ensure parent directory exists
        let parentDir = destURL.deletingLastPathComponent()
        try? fileManager.createDirectory(
            at: parentDir,
            withIntermediateDirectories: true
        )

        // Download
        guard let sourceURL = URL(string: provision.source) else {
            throw ProvisionError.downloadFailed(
                source: provision.source,
                detail: "Invalid source URL."
            )
        }

        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw ProvisionError.downloadFailed(
                source: provision.source,
                detail: error.localizedDescription
            )
        }

        // Atomic write: temp file → move
        let tempURL = destURL.appendingPathExtension("downloading")
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw ProvisionError.writeFailed(
                destination: provision.destination,
                detail: error.localizedDescription
            )
        }

        do {
            try fileManager.moveItem(at: tempURL, to: destURL)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw ProvisionError.writeFailed(
                destination: provision.destination,
                detail: error.localizedDescription
            )
        }
    }
}
