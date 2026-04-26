import Foundation
import Synchronization
import os

private let log = Logger(subsystem: "com.haven", category: "BackupScheduler")

/// Manages automatic backup scheduling based on `BackupSettings`.
///
/// Checks periodically (every hour) whether a backup is overdue,
/// and calls the provided `onBackupNeeded` handler when one is due.
///
/// The scheduler runs in-process — the app must be running for
/// automatic backups to trigger. This is appropriate because Haven
/// is a long-running GUI app on a Mac mini.
///
/// Usage:
/// ```swift
/// let scheduler = BackupScheduler {
///     await performBackup()
/// }
/// scheduler.start(settings: currentSettings)
/// ```
public final class BackupScheduler: Sendable {

    /// How often to check if a backup is due (seconds).
    public static let defaultCheckInterval: TimeInterval = 60 * 60 // 1 hour

    private let checkInterval: TimeInterval
    private let onBackupNeeded: @Sendable () async -> Void
    private let _isRunning = Mutex(false)
    private let _task = Mutex<Task<Void, Never>?>(nil)

    /// Whether the scheduler is currently active.
    public var isRunning: Bool {
        _isRunning.withLock { $0 }
    }

    /// Create a scheduler with a callback for when backup is needed.
    ///
    /// - Parameters:
    ///   - checkInterval: How often to check (default: 1 hour).
    ///   - onBackupNeeded: Called when a backup is overdue. Runs on a background task.
    public init(
        checkInterval: TimeInterval = BackupScheduler.defaultCheckInterval,
        onBackupNeeded: @escaping @Sendable () async -> Void
    ) {
        self.checkInterval = checkInterval
        self.onBackupNeeded = onBackupNeeded
    }

    /// Start the scheduler. Performs an immediate check, then checks periodically.
    ///
    /// - Parameter settings: Current backup settings (used for the initial check).
    public func start(settings: BackupSettings) {
        stop()

        _isRunning.withLock { $0 = true }
        log.info("Backup scheduler started (interval: \(self.checkInterval)s)")

        let task = Task { [weak self] in
            guard let self else { return }

            // Immediate check on start
            if settings.isConfigured && settings.isOverdue() {
                log.info("Backup is overdue on scheduler start, triggering…")
                await self.onBackupNeeded()
            }

            // Periodic checks
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.checkInterval))
                guard !Task.isCancelled else { break }

                let current = BackupSettings.load()
                if current.isConfigured && current.isOverdue() {
                    log.info("Scheduled backup check: overdue, triggering…")
                    await self.onBackupNeeded()
                } else {
                    log.debug("Scheduled backup check: not due yet")
                }
            }

            self._isRunning.withLock { $0 = false }
            log.info("Backup scheduler stopped")
        }

        _task.withLock { $0 = task }
    }

    /// Stop the scheduler.
    public func stop() {
        _task.withLock { existing in
            existing?.cancel()
            existing = nil
        }
        _isRunning.withLock { $0 = false }
    }

    /// Perform a one-time check and trigger backup if overdue.
    /// Does not start the periodic timer.
    public func checkNow(settings: BackupSettings) async {
        guard settings.isConfigured && settings.isOverdue() else {
            log.debug("Manual check: backup not due")
            return
        }
        log.info("Manual check: backup overdue, triggering…")
        await onBackupNeeded()
    }

    deinit {
        _task.withLock { $0?.cancel() }
    }
}
