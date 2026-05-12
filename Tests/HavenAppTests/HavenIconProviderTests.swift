import Foundation
import Testing
@testable import HavenAppKit

@Suite("Haven icon provider")
struct HavenIconProviderTests {
    @Test("finds menu icon in packaged app resource bundle")
    func findsMenuIconInPackagedAppResourceBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HavenIconProviderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let resourceBundle = root
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Haven_HavenAppKit.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: resourceBundle, withIntermediateDirectories: true)

        let expectedURL = resourceBundle.appendingPathComponent("HavenMenuTemplate@2x.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: expectedURL)

        let foundURL = try #require(HavenIconProvider.menuBarImageURL(searchDirectories: [resourceBundle]))
        #expect(foundURL.standardizedFileURL == expectedURL.standardizedFileURL)
    }

    @Test("searches macOS app Contents resources")
    func searchesMacOSAppContentsResources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HavenIconProviderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appBundleURL = root.appendingPathComponent("HavenOS.app", isDirectory: true)
        let contentsURL = appBundleURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let resourceBundleURL = resourcesURL.appendingPathComponent("Haven_HavenAppKit.bundle", isDirectory: true)

        try FileManager.default.createDirectory(at: resourceBundleURL, withIntermediateDirectories: true)
        try minimalInfoPlist.data(using: .utf8)!.write(to: contentsURL.appendingPathComponent("Info.plist"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(
            to: resourceBundleURL.appendingPathComponent("HavenMenuTemplate@2x.png")
        )

        let bundle = try #require(Bundle(url: appBundleURL))
        let foundURL = try #require(HavenIconProvider.menuBarImageURL(bundle: bundle))

        #expect(foundURL.standardizedFileURL == resourceBundleURL
            .appendingPathComponent("HavenMenuTemplate@2x.png")
            .standardizedFileURL)
    }

    private var minimalInfoPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>HavenOS</string>
            <key>CFBundleIdentifier</key>
            <string>app.haven.HavenOS.tests</string>
            <key>CFBundleName</key>
            <string>HavenOS</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
        </dict>
        </plist>
        """
    }
}
