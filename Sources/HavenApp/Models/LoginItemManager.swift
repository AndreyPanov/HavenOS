import Foundation
import ServiceManagement
import os

private let loginLog = Logger(subsystem: "com.haven", category: "LoginItem")

@MainActor
@Observable
package final class LoginItemManager {
    package private(set) var isOpenAtLogin = false
    package private(set) var statusDescription: String?
    package var lastError: String?

    package init() {
        refresh()
    }

    package func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isOpenAtLogin = true
            statusDescription = nil
        case .requiresApproval:
            isOpenAtLogin = false
            statusDescription = "Approve in Login Items"
        case .notFound:
            isOpenAtLogin = false
            statusDescription = "Available in the app bundle"
        case .notRegistered:
            isOpenAtLogin = false
            statusDescription = nil
        @unknown default:
            isOpenAtLogin = false
            statusDescription = "Unknown login item status"
        }
    }

    package func setOpenAtLogin(_ enabled: Bool) {
        lastError = nil

        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginLog.error("Failed to update login item: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }

        refresh()
    }
}
