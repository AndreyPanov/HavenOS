import Foundation

struct InstalledService: Identifiable, Hashable {
    let id: String
    let name: String
    let serviceDescription: String
    let icon: String
    var status: ServiceStatus
    let port: Int?
    let dataPath: String

    var localURL: String? {
        guard let port = port else { return nil }
        return "http://localhost:\(port)"
    }
}
