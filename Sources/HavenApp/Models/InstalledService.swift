import Foundation
import HavenCore

struct InstalledService: Identifiable, Hashable {
    let id: String
    let name: String
    let serviceDescription: String
    let icon: String
    let iconImagePath: String?
    var status: ServiceStatus
    let port: Int?
    let dataPath: String
    let instructions: String?
    let onboarding: Onboarding?

    var localURL: String? {
        guard let port = port else { return nil }
        return "http://localhost:\(port)"
    }
}
