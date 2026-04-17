import Foundation
import HavenCore
import os

private let log = Logger(subsystem: "com.haven", category: "ReadinessChecker")

/// Polls a readiness probe until the target responds or a timeout is reached.
///
/// Used during multi-unit startup to ensure a dependency (e.g. a database)
/// is accepting connections before starting units that depend on it.
public struct ReadinessChecker: Sendable {

    public init() {}

    /// Error thrown when a readiness probe times out.
    public struct ReadinessTimeout: Error, CustomStringConvertible {
        public let probe: ReadinessProbe
        public let elapsed: TimeInterval

        public var description: String {
            "Readiness probe timed out after \(Int(elapsed))s (target: \(probe.target))"
        }
    }

    /// Poll until the probe succeeds or `timeoutSeconds` is exceeded.
    ///
    /// - Parameters:
    ///   - probe: The resolved readiness probe (all placeholders expanded).
    ///   - progress: Optional callback for status updates.
    /// - Throws: ``ReadinessTimeout`` if the probe doesn't succeed in time.
    public func waitUntilReady(
        probe: ReadinessProbe,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let deadline = Date().addingTimeInterval(TimeInterval(probe.timeoutSeconds))
        let interval = UInt64(probe.intervalSeconds) * 1_000_000_000

        log.info("[readiness] Waiting for \(probe.type.rawValue) probe: \(probe.target) (timeout: \(probe.timeoutSeconds)s)")
        progress?("Waiting for \(probe.target)…")

        while Date() < deadline {
            let ok: Bool
            switch probe.type {
            case .tcp:
                ok = checkTCP(target: probe.target)
            case .http:
                ok = await checkHTTP(target: probe.target)
            case .exec:
                ok = checkExec(target: probe.target)
            }

            if ok {
                log.info("[readiness] Probe succeeded: \(probe.target)")
                return
            }

            try await Task.sleep(nanoseconds: interval)
        }

        let elapsed = TimeInterval(probe.timeoutSeconds)
        throw ReadinessTimeout(probe: probe, elapsed: elapsed)
    }

    // MARK: - Probe implementations

    /// TCP: try connecting to host:port. Returns true if connection succeeds.
    private func checkTCP(target: String) -> Bool {
        let parts = target.split(separator: ":")
        guard parts.count == 2,
              let port = UInt16(parts[1]) else {
            log.warning("[readiness] Invalid TCP target: \(target)")
            return false
        }
        let host = String(parts[0])

        let socket = socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }

        // Set short connect timeout
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, host == "localhost" ? "127.0.0.1" : host, &addr.sin_addr)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(socket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    /// HTTP: issue a GET request. Returns true on 2xx response.
    private func checkHTTP(target: String) async -> Bool {
        guard let url = URL(string: target) else {
            log.warning("[readiness] Invalid HTTP target: \(target)")
            return false
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)

        do {
            let (_, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse {
                return (200..<300).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    /// Exec: run a shell command. Returns true on exit code 0.
    private func checkExec(target: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", target]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
