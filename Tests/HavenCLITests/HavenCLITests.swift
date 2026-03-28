import XCTest
import ArgumentParser
import HavenCLIKit

// CLI tests validate argument parsing contracts without running the full
// executable. Add integration tests against the built binary separately.

final class ListCommandTests: XCTestCase {
    func testDefaultVerboseIsFalse() throws {
        let cmd = try ListCommand.parse([])
        XCTAssertFalse(cmd.verbose)
    }

    func testVerboseFlagSetsTrue() throws {
        let cmd = try ListCommand.parse(["--verbose"])
        XCTAssertTrue(cmd.verbose)
    }

    func testShortVerboseFlagSetsTrue() throws {
        let cmd = try ListCommand.parse(["-v"])
        XCTAssertTrue(cmd.verbose)
    }
}
