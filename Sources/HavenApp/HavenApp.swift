import SwiftUI

@main
struct HavenApp: App {
    @State private var settings = HavenSettingsModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
        }
        .defaultSize(width: 1100, height: 700)
    }
}
