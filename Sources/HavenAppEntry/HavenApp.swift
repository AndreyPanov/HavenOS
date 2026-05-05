import AppKit
import SwiftUI
import HavenAppKit

final class HavenAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        sender.setActivationPolicy(.accessory)
        return false
    }
}

@main
struct HavenApp: App {
    @NSApplicationDelegateAdaptor(HavenAppDelegate.self) private var appDelegate
    @State private var settings: HavenSettingsModel
    @State private var serviceManager: ServiceManager
    @State private var loginItemManager: LoginItemManager
    @State private var appUpdateModel: AppUpdateModel

    @MainActor
    init() {
        let settings = HavenSettingsModel()
        let serviceManager = ServiceManager()
        let loginItemManager = LoginItemManager()
        let appUpdateModel = AppUpdateModel()

        serviceManager.load(
            catalogURL: settings.catalogFolderURL,
            backupSettings: settings.backupSettings
        )

        _settings = State(initialValue: settings)
        _serviceManager = State(initialValue: serviceManager)
        _loginItemManager = State(initialValue: loginItemManager)
        _appUpdateModel = State(initialValue: appUpdateModel)

        // Ensure the app runs as a regular GUI application with dock icon and menu bar,
        // even when launched as a bare executable outside a .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)

        // SwiftPM executables don't embed Info.plist into Contents/Info.plist,
        // so Bundle.main.bundleIdentifier is nil. Disable automatic window
        // tabbing to avoid AppKit's "Cannot index window tabs" warning.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        Window("Haven", id: "main") {
            ContentView()
                .environment(settings)
                .environment(serviceManager)
                .environment(appUpdateModel)
        }
        .defaultSize(width: 1100, height: 700)

        MenuBarExtra {
            HavenStatusMenu()
                .environment(settings)
                .environment(serviceManager)
                .environment(loginItemManager)
        } label: {
            HavenIconProvider.menuBarIcon
                .accessibilityLabel("Haven")
        }
        .menuBarExtraStyle(.window)
    }
}
