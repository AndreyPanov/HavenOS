import Foundation

extension String {
    /// Strips a leading "./" prefix from a relative path.
    public var strippingDotSlashPrefix: String {
        hasPrefix("./") ? String(dropFirst(2)) : self
    }
}
