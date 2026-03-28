import Foundation

/// The observed runtime status of a launchd job.
///
/// This type represents what launchd reports about a job's current state.
/// It is derived from querying launchd, not from Haven's own state store.
public struct LaunchdJobStatus: Equatable, Sendable {

    /// The high-level lifecycle state of the job.
    public enum State: Equatable, Sendable {
        /// The job's plist file exists in LaunchAgents but is not loaded
        /// into the launchd domain.
        case installed

        /// The job is loaded into launchd and currently running.
        case running

        /// The job is loaded into launchd but not currently running
        /// (exited or was stopped).
        case stopped

        /// The job is not known to launchd (no plist, not loaded).
        case notFound
    }

    /// The lifecycle state.
    public let state: State

    /// The process ID, if the job is currently running.
    public let pid: Int?

    /// The last exit status, if available. A non-zero value typically
    /// indicates the process exited abnormally.
    public let lastExitStatus: Int?

    /// The launchd label this status belongs to.
    public let label: String

    public init(
        state: State,
        pid: Int? = nil,
        lastExitStatus: Int? = nil,
        label: String
    ) {
        self.state = state
        self.pid = pid
        self.lastExitStatus = lastExitStatus
        self.label = label
    }
}
