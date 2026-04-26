import Foundation

/// Overall backup health status.
public enum BackupStatus: Sendable, Equatable {
    /// No backup has ever been configured.
    case notConfigured
    /// Backup has never run (configured but no successful backup yet).
    case neverRun
    /// Last backup succeeded and is within schedule.
    case healthy
    /// Last backup succeeded but is overdue per schedule.
    case overdue(daysSince: Int)
    /// Last backup had partial failures.
    case warning(message: String)
    /// Last backup failed entirely.
    case failed(message: String)
}

/// Protection state for a single capability.
public struct CapabilityProtection: Sendable, Equatable, Identifiable {
    public let capabilityID: String
    public let displayName: String
    public let isProtected: Bool
    public let lastBackedUp: Date?

    public var id: String { capabilityID }

    public init(
        capabilityID: String,
        displayName: String,
        isProtected: Bool,
        lastBackedUp: Date?
    ) {
        self.capabilityID = capabilityID
        self.displayName = displayName
        self.isProtected = isProtected
        self.lastBackedUp = lastBackedUp
    }
}

/// Computed backup health for display in the UI.
///
/// Derived from `BackupSettings` and the current set of installed capabilities.
/// This is a value type — recomputed on each refresh, not stored.
public struct BackupHealth: Sendable, Equatable {

    /// Overall backup status.
    public let status: BackupStatus

    /// When the last successful backup completed.
    public let lastBackupDate: Date?

    /// The configured backup destination (display path).
    public let destination: String?

    /// Per-capability protection breakdown.
    public let capabilities: [CapabilityProtection]

    /// Protection score from 0 to 100.
    /// Based on the percentage of installed capabilities that have a recent backup.
    public let protectionScore: Int

    public init(
        status: BackupStatus,
        lastBackupDate: Date?,
        destination: String?,
        capabilities: [CapabilityProtection],
        protectionScore: Int
    ) {
        self.status = status
        self.lastBackupDate = lastBackupDate
        self.destination = destination
        self.capabilities = capabilities
        self.protectionScore = protectionScore
    }

    /// Compute backup health from settings and installed capability info.
    ///
    /// - Parameters:
    ///   - settings: Current backup settings.
    ///   - installedCapabilities: Tuples of (capabilityID, displayName) for installed services.
    ///   - manifest: The last backup manifest, if one exists.
    public static func compute(
        settings: BackupSettings,
        installedCapabilities: [(id: String, name: String)],
        manifest: BackupManifest? = nil
    ) -> BackupHealth {
        guard settings.isConfigured else {
            return BackupHealth(
                status: .notConfigured,
                lastBackupDate: nil,
                destination: nil,
                capabilities: installedCapabilities.map {
                    CapabilityProtection(
                        capabilityID: $0.id,
                        displayName: $0.name,
                        isProtected: false,
                        lastBackedUp: nil
                    )
                },
                protectionScore: 0
            )
        }

        // Build per-capability protection from manifest
        let backedUpIDs = Set(manifest?.capabilities.filter { $0.status == .complete }.map(\.capabilityID) ?? [])
        let backupDate = manifest?.createdAt ?? settings.lastBackupDate

        let capProtections = installedCapabilities.map { cap in
            CapabilityProtection(
                capabilityID: cap.id,
                displayName: cap.name,
                isProtected: backedUpIDs.contains(cap.id),
                lastBackedUp: backedUpIDs.contains(cap.id) ? backupDate : nil
            )
        }

        let protectedCount = capProtections.filter(\.isProtected).count
        let totalCount = capProtections.count
        let score = totalCount > 0 ? (protectedCount * 100) / totalCount : 0

        // Determine overall status
        let status: BackupStatus
        if settings.lastBackupDate == nil && backupDate == nil {
            status = .neverRun
        } else if let result = settings.lastBackupResult {
            switch result {
            case .success:
                if settings.isOverdue() {
                    status = .overdue(daysSince: settings.daysSinceLastBackup ?? 0)
                } else {
                    status = .healthy
                }
            case .partial(_, let reason):
                status = .warning(message: reason)
            case .failed(let reason):
                status = .failed(message: reason)
            }
        } else if settings.isOverdue() {
            status = .overdue(daysSince: settings.daysSinceLastBackup ?? 0)
        } else {
            status = .healthy
        }

        return BackupHealth(
            status: status,
            lastBackupDate: backupDate ?? settings.lastBackupDate,
            destination: settings.destinationPath,
            capabilities: capProtections,
            protectionScore: score
        )
    }
}
