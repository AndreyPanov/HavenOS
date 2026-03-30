import Foundation

/// A file-backed ``StateStore`` that persists state as JSON.
///
/// Thread safety is provided by an `NSLock`. All reads and writes
/// go through the lock. Writes are atomic via ``AtomicFileWriter``.
///
/// If the state file does not exist, ``load()`` returns empty state
/// rather than throwing.
public final class FileStateStore: StateStore, @unchecked Sendable {

    /// Path to the JSON state file.
    private let stateFileURL: URL

    /// Protects all reads and writes.
    private let lock = NSLock()

    /// Encoder configured for deterministic, readable output.
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Decoder matching the encoder's date strategy.
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Create a store backed by the given file URL.
    ///
    /// The file (and its parent directories) are created lazily on first write.
    public init(stateFileURL: URL) {
        self.stateFileURL = stateFileURL
    }

    /// Convenience: create a store using a ``HavenPaths`` instance.
    public convenience init(paths: HavenPaths) {
        self.init(stateFileURL: paths.stateFile)
    }

    // MARK: - StateStore

    public func load() throws -> HavenState {
        lock.lock()
        defer { lock.unlock() }
        return try loadUnsafe()
    }

    public func save(_ state: HavenState) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveUnsafe(state)
    }

    public func service(for capabilityID: String) throws -> StoredServiceState? {
        lock.lock()
        defer { lock.unlock() }
        let state = try loadUnsafe()
        return state.services[capabilityID]
    }

    public func upsert(_ service: StoredServiceState) throws {
        lock.lock()
        defer { lock.unlock() }
        var state = try loadUnsafe()
        state.services[service.capability] = service
        try saveUnsafe(state)
    }

    public func remove(capabilityID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var state = try loadUnsafe()
        state.services.removeValue(forKey: capabilityID)
        try saveUnsafe(state)
    }

    // MARK: - Internal (no locking)

    private func loadUnsafe() throws -> HavenState {
        guard FileManager.default.fileExists(atPath: stateFileURL.path) else {
            return HavenState()
        }
        let data = try Data(contentsOf: stateFileURL)
        return try decoder.decode(HavenState.self, from: data)
    }

    private func saveUnsafe(_ state: HavenState) throws {
        let data = try encoder.encode(state)
        try AtomicFileWriter.write(data, to: stateFileURL)
    }
}
