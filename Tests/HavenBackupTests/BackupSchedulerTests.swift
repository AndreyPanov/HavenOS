import Testing
import Foundation
import Synchronization
@testable import HavenBackup

@Suite("BackupScheduler")
struct BackupSchedulerTests {

    @Test("checkNow triggers when overdue")
    func checkNowTriggersWhenOverdue() async {
        let triggered = Mutex(false)
        let scheduler = BackupScheduler(onBackupNeeded: {
            triggered.withLock { $0 = true }
        })

        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
            schedule: .daily,
            lastBackupDate: Date().addingTimeInterval(-2 * 24 * 60 * 60)
        )

        await scheduler.checkNow(settings: settings)
        #expect(triggered.withLock { $0 })
    }

    @Test("checkNow does not trigger when not overdue")
    func checkNowSkipsWhenNotDue() async {
        let triggered = Mutex(false)
        let scheduler = BackupScheduler(onBackupNeeded: {
            triggered.withLock { $0 = true }
        })

        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
            schedule: .weekly,
            lastBackupDate: Date().addingTimeInterval(-60 * 60) // 1 hour ago
        )

        await scheduler.checkNow(settings: settings)
        #expect(!triggered.withLock { $0 })
    }

    @Test("checkNow does not trigger for manual schedule")
    func checkNowSkipsManual() async {
        let triggered = Mutex(false)
        let scheduler = BackupScheduler(onBackupNeeded: {
            triggered.withLock { $0 = true }
        })

        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
            schedule: .manual
        )

        await scheduler.checkNow(settings: settings)
        #expect(!triggered.withLock { $0 })
    }

    @Test("checkNow does not trigger when not configured")
    func checkNowSkipsUnconfigured() async {
        let triggered = Mutex(false)
        let scheduler = BackupScheduler(onBackupNeeded: {
            triggered.withLock { $0 = true }
        })

        let settings = BackupSettings() // no destination
        await scheduler.checkNow(settings: settings)
        #expect(!triggered.withLock { $0 })
    }

    @Test("start triggers immediately when overdue")
    func startTriggersImmediately() async throws {
        let triggered = Mutex(false)
        let scheduler = BackupScheduler(
            checkInterval: 999, // won't reach periodic check
            onBackupNeeded: {
                triggered.withLock { $0 = true }
            }
        )

        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
            schedule: .daily,
            lastBackupDate: Date().addingTimeInterval(-2 * 24 * 60 * 60)
        )

        scheduler.start(settings: settings)

        // Wait briefly for the immediate check
        try await Task.sleep(for: .milliseconds(200))

        scheduler.stop()
        #expect(triggered.withLock { $0 })
    }

    @Test("start does not trigger immediately when not overdue")
    func startDoesNotTriggerWhenNotDue() async throws {
        let triggered = Mutex(false)
        let scheduler = BackupScheduler(
            checkInterval: 999,
            onBackupNeeded: {
                triggered.withLock { $0 = true }
            }
        )

        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
            schedule: .weekly,
            lastBackupDate: Date()
        )

        scheduler.start(settings: settings)
        try await Task.sleep(for: .milliseconds(200))
        scheduler.stop()

        #expect(!triggered.withLock { $0 })
    }

    @Test("stop cancels the scheduler")
    func stopCancels() async throws {
        let count = Mutex(0)
        let scheduler = BackupScheduler(
            checkInterval: 0.05, // 50ms for fast test
            onBackupNeeded: {
                count.withLock { $0 += 1 }
            }
        )

        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
            schedule: .daily
            // no lastBackupDate → always overdue
        )

        scheduler.start(settings: settings)
        try await Task.sleep(for: .milliseconds(100))
        scheduler.stop()

        let countAtStop = count.withLock { $0 }
        try await Task.sleep(for: .milliseconds(200))
        let countAfterWait = count.withLock { $0 }

        // No additional triggers after stop
        #expect(countAfterWait == countAtStop)
    }

    @Test("isRunning reflects scheduler state")
    func isRunningState() async throws {
        let scheduler = BackupScheduler(
            checkInterval: 999,
            onBackupNeeded: {}
        )

        #expect(!scheduler.isRunning)

        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
            schedule: .weekly,
            lastBackupDate: Date()
        )

        scheduler.start(settings: settings)
        #expect(scheduler.isRunning)

        scheduler.stop()
        // Give a moment for the flag to update
        try await Task.sleep(for: .milliseconds(50))
        #expect(!scheduler.isRunning)
    }
}
