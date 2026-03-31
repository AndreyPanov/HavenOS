import SwiftUI

@Observable
class HavenSettingsModel {
    var dataDirectory = "~/.haven"
    var launchAtLogin = false
    var autoStartServices = true

    var baseDirectory = "~/.haven"
    var downloadsDirectory = "~/.haven/downloads"
    var artifactsDirectory = "~/.haven/artifacts"

    var showInternalDetails = false

    let version = "0.1.0"
    let buildNumber = "1"
}
