/// The execution context that hosts a ``Bundle``.
///
/// A RuntimeUnit is the running instance of a bundle. It owns the
/// lifecycle (start / stop) and is managed by a runtime adapter
/// (see `HavenRuntimes`).
public struct RuntimeUnit: Identifiable, Sendable {
    public enum State: String, Sendable {
        case idle
        case running
        case stopped
        case failed
    }

    public let id: String
    public let bundle: Bundle
    public private(set) var state: State

    public init(id: String, bundle: Bundle) {
        self.id = id
        self.bundle = bundle
        self.state = .idle
    }

    public mutating func start() {
        state = .running
    }

    public mutating func stop() {
        state = .stopped
    }
}
