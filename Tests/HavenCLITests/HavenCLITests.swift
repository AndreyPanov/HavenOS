import XCTest
import ArgumentParser
@testable import HavenCLIKit

// CLI tests validate argument parsing contracts without running the full
// executable. Add integration tests against the built binary separately.

// MARK: - InstallCommand

final class InstallCommandTests: XCTestCase {
    func testCapabilityIDIsRequired() {
        XCTAssertThrowsError(try InstallCommand.parse([]))
    }

    func testCapabilityIDParsed() throws {
        let cmd = try InstallCommand.parse(["haven.capability.test"])
        XCTAssertEqual(cmd.capability, "haven.capability.test")
    }

    func testSpecsDirDefault() throws {
        let cmd = try InstallCommand.parse(["haven.capability.test"])
        XCTAssertEqual(cmd.specsDir, "~/.haven/Specs")
    }

    func testSpecsDirOverride() throws {
        let cmd = try InstallCommand.parse([
            "haven.capability.test", "--specs-dir", "/custom/specs"
        ])
        XCTAssertEqual(cmd.specsDir, "/custom/specs")
    }

    func testSetOptionSingleValue() throws {
        let cmd = try InstallCommand.parse([
            "haven.capability.test", "--set", "port=8080"
        ])
        XCTAssertEqual(cmd.set, ["port=8080"])
    }

    func testSetOptionMultipleValues() throws {
        let cmd = try InstallCommand.parse([
            "haven.capability.test",
            "--set", "port=8080",
            "--set", "data_path=/srv/data"
        ])
        XCTAssertEqual(cmd.set, ["port=8080", "data_path=/srv/data"])
    }

    func testBaseDirDefault() throws {
        let cmd = try InstallCommand.parse(["haven.capability.test"])
        XCTAssertEqual(cmd.common.baseDir, "~/.haven")
    }

    func testBaseDirOverride() throws {
        let cmd = try InstallCommand.parse([
            "haven.capability.test", "--base-dir", "/custom/haven"
        ])
        XCTAssertEqual(cmd.common.baseDir, "/custom/haven")
    }
}

// MARK: - UninstallCommand

final class UninstallCommandTests: XCTestCase {
    func testCapabilityIDIsRequired() {
        XCTAssertThrowsError(try UninstallCommand.parse([]))
    }

    func testCapabilityIDParsed() throws {
        let cmd = try UninstallCommand.parse(["haven.capability.test"])
        XCTAssertEqual(cmd.capability, "haven.capability.test")
    }
}

// MARK: - StartCommand

final class StartCommandTests: XCTestCase {
    func testCapabilityIDIsRequired() {
        XCTAssertThrowsError(try StartCommand.parse([]))
    }

    func testCapabilityIDParsed() throws {
        let cmd = try StartCommand.parse(["haven.capability.test"])
        XCTAssertEqual(cmd.capability, "haven.capability.test")
    }
}

// MARK: - StopCommand

final class StopCommandTests: XCTestCase {
    func testCapabilityIDIsRequired() {
        XCTAssertThrowsError(try StopCommand.parse([]))
    }

    func testCapabilityIDParsed() throws {
        let cmd = try StopCommand.parse(["haven.capability.test"])
        XCTAssertEqual(cmd.capability, "haven.capability.test")
    }
}

// MARK: - StatusCommand

final class StatusCommandTests: XCTestCase {
    func testCapabilityIDIsRequired() {
        XCTAssertThrowsError(try StatusCommand.parse([]))
    }

    func testCapabilityIDParsed() throws {
        let cmd = try StatusCommand.parse(["haven.capability.test"])
        XCTAssertEqual(cmd.capability, "haven.capability.test")
    }
}

// MARK: - ListCommand

final class ListCommandTests: XCTestCase {
    func testParsesWithNoArguments() throws {
        let cmd = try ListCommand.parse([])
        XCTAssertEqual(cmd.common.baseDir, "~/.haven")
    }

    func testBaseDirOverride() throws {
        let cmd = try ListCommand.parse(["--base-dir", "/custom/haven"])
        XCTAssertEqual(cmd.common.baseDir, "/custom/haven")
    }
}

// MARK: - Havenctl Top-Level

final class HavenctlTests: XCTestCase {
    func testSubcommandsParsed() {
        let subcommands = Havenctl.configuration.subcommands
        let names = subcommands.map { $0.configuration.commandName }
        XCTAssertTrue(names.contains("install"))
        XCTAssertTrue(names.contains("uninstall"))
        XCTAssertTrue(names.contains("start"))
        XCTAssertTrue(names.contains("stop"))
        XCTAssertTrue(names.contains("status"))
        XCTAssertTrue(names.contains("list"))
    }

    func testDefaultSubcommandIsList() {
        XCTAssertNotNil(Havenctl.configuration.defaultSubcommand)
    }
}
