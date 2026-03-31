import XCTest
import Foundation
import HavenCore
import HavenRuntimes
@testable import HavenLaunchd

// MARK: - LaunchdLabel Tests

final class LaunchdLabelTests: XCTestCase {

    func testLabelPrefix() {
        XCTAssertEqual(LaunchdLabel.prefix, "app.haven")
    }

    func testLabelGeneration() {
        let label = LaunchdLabel.label(
            capabilityID: "haven.capability.test-library",
            unitID: "haven.unit.test-db"
        )
        XCTAssertEqual(label, "app.haven.haven.capability.test-library.haven.unit.test-db")
    }

    func testLabelIsDeterministic() {
        let a = LaunchdLabel.label(capabilityID: "cap.x", unitID: "unit.y")
        let b = LaunchdLabel.label(capabilityID: "cap.x", unitID: "unit.y")
        XCTAssertEqual(a, b)
    }

    func testDifferentUnitsProduceDifferentLabels() {
        let a = LaunchdLabel.label(capabilityID: "cap.x", unitID: "unit.a")
        let b = LaunchdLabel.label(capabilityID: "cap.x", unitID: "unit.b")
        XCTAssertNotEqual(a, b)
    }

    func testDifferentCapabilitiesProduceDifferentLabels() {
        let a = LaunchdLabel.label(capabilityID: "cap.x", unitID: "unit.a")
        let b = LaunchdLabel.label(capabilityID: "cap.y", unitID: "unit.a")
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - LaunchdKeepAlivePolicy Tests

final class LaunchdKeepAlivePolicyTests: XCTestCase {

    func testAlwaysPlistValue() {
        let value = LaunchdKeepAlivePolicy.always.plistValue()
        XCTAssertEqual(value as? Bool, true)
    }

    func testSuccessfulExitPlistValue() {
        let value = LaunchdKeepAlivePolicy.successfulExit.plistValue()
        let dict = value as? [String: Bool]
        XCTAssertNotNil(dict)
        XCTAssertEqual(dict?["SuccessfulExit"], false)
    }

    func testNonePlistValue() {
        let value = LaunchdKeepAlivePolicy.none.plistValue()
        XCTAssertEqual(value as? Bool, false)
    }

    func testShouldIncludeInPlist() {
        XCTAssertTrue(LaunchdKeepAlivePolicy.always.shouldIncludeInPlist)
        XCTAssertTrue(LaunchdKeepAlivePolicy.successfulExit.shouldIncludeInPlist)
        XCTAssertFalse(LaunchdKeepAlivePolicy.none.shouldIncludeInPlist)
    }

    func testEquality() {
        XCTAssertEqual(LaunchdKeepAlivePolicy.always, .always)
        XCTAssertEqual(LaunchdKeepAlivePolicy.successfulExit, .successfulExit)
        XCTAssertEqual(LaunchdKeepAlivePolicy.none, .none)
        XCTAssertNotEqual(LaunchdKeepAlivePolicy.always, .none)
        XCTAssertNotEqual(LaunchdKeepAlivePolicy.always, .successfulExit)
    }
}

// MARK: - LaunchdJob Make Tests (Native Runtime)

final class LaunchdJobNativeTests: XCTestCase {

    func testMakeFromNativeRuntime() {
        let layout = makeLayout()
        let prepared = makeNativePreparedRuntime()

        let job = LaunchdJob.make(
            capabilityID: "haven.capability.test-library",
            unitID: "haven.unit.test-db",
            preparedRuntime: prepared,
            serviceLayout: layout
        )

        XCTAssertEqual(job.label, "app.haven.haven.capability.test-library.haven.unit.test-db")
        XCTAssertEqual(job.programArguments, ["/opt/haven/bin/test-db", "--datadir", "/data"])
        XCTAssertEqual(job.workingDirectory, layout.serviceRoot.path)
        XCTAssertTrue(job.runAtLoad)
        XCTAssertEqual(job.keepAlive, .successfulExit) // default
    }

    func testLogPaths() {
        let layout = makeLayout()
        let prepared = makeNativePreparedRuntime()

        let job = LaunchdJob.make(
            capabilityID: "haven.capability.test-library",
            unitID: "haven.unit.test-db",
            preparedRuntime: prepared,
            serviceLayout: layout
        )

        let expectedStdout = layout.logs
            .appendingPathComponent("haven.unit.test-db.stdout.log").path
        let expectedStderr = layout.logs
            .appendingPathComponent("haven.unit.test-db.stderr.log").path

        XCTAssertEqual(job.standardOutPath, expectedStdout)
        XCTAssertEqual(job.standardErrorPath, expectedStderr)
    }

    func testEnvironmentVariablesPassedThrough() {
        let layout = makeLayout()
        let prepared = makeNativePreparedRuntime(environment: [
            "DATA_DIR": "/data",
            "LOG_LEVEL": "info",
        ])

        let job = LaunchdJob.make(
            capabilityID: "cap.x",
            unitID: "unit.y",
            preparedRuntime: prepared,
            serviceLayout: layout
        )

        XCTAssertEqual(job.environmentVariables["DATA_DIR"], "/data")
        XCTAssertEqual(job.environmentVariables["LOG_LEVEL"], "info")
    }

    func testCustomKeepAlivePolicy() {
        let layout = makeLayout()
        let prepared = makeNativePreparedRuntime()

        let jobAlways = LaunchdJob.make(
            capabilityID: "cap.x",
            unitID: "unit.y",
            preparedRuntime: prepared,
            serviceLayout: layout,
            keepAlive: .always
        )
        XCTAssertEqual(jobAlways.keepAlive, .always)

        let jobNone = LaunchdJob.make(
            capabilityID: "cap.x",
            unitID: "unit.y",
            preparedRuntime: prepared,
            serviceLayout: layout,
            keepAlive: .none
        )
        XCTAssertEqual(jobNone.keepAlive, .none)
    }
}

// MARK: - LaunchdJob Make Tests (Python Runtime)

final class LaunchdJobPythonTests: XCTestCase {

    func testMakeFromPythonRuntime() {
        let layout = makeLayout(capabilityID: "haven.capability.py-svc")
        let venvRoot = layout.run
            .appendingPathComponent("venvs")
            .appendingPathComponent("haven.unit.py-app")
        let pythonExe = venvRoot.appendingPathComponent("bin").appendingPathComponent("python3")

        let prepared = PreparedRuntime(
            unitID: "haven.unit.py-app",
            executableURL: pythonExe,
            arguments: ["-m", "pyapp", "--serve"],
            environment: [
                "VIRTUAL_ENV": venvRoot.path,
                "PATH": "\(venvRoot.appendingPathComponent("bin").path):/usr/bin:/bin",
                "APP_PORT": "9000",
            ],
            workingDirectory: layout.serviceRoot,
            managedDirectories: layout.allDirectories + [venvRoot],
            runtimeType: .python,
            healthcheck: Healthcheck(type: .http, target: "http://localhost:9000/health"),
            port: 9000,
            dependsOn: []
        )

        let job = LaunchdJob.make(
            capabilityID: "haven.capability.py-svc",
            unitID: "haven.unit.py-app",
            preparedRuntime: prepared,
            serviceLayout: layout
        )

        // Label should follow the convention
        XCTAssertEqual(job.label, "app.haven.haven.capability.py-svc.haven.unit.py-app")

        // Program arguments should include the venv python
        XCTAssertEqual(job.programArguments.first, pythonExe.path)
        XCTAssertTrue(job.programArguments.contains("-m"))
        XCTAssertTrue(job.programArguments.contains("pyapp"))

        // Environment should include VIRTUAL_ENV and PATH
        XCTAssertEqual(job.environmentVariables["VIRTUAL_ENV"], venvRoot.path)
        XCTAssertNotNil(job.environmentVariables["PATH"])
        XCTAssertEqual(job.environmentVariables["APP_PORT"], "9000")
    }

    func testPythonLogPaths() {
        let layout = makeLayout(capabilityID: "haven.capability.py-svc")
        let venvRoot = layout.run
            .appendingPathComponent("venvs")
            .appendingPathComponent("haven.unit.py-app")
        let pythonExe = venvRoot.appendingPathComponent("bin").appendingPathComponent("python3")

        let prepared = PreparedRuntime(
            unitID: "haven.unit.py-app",
            executableURL: pythonExe,
            arguments: ["-m", "app"],
            environment: [:],
            workingDirectory: layout.serviceRoot,
            managedDirectories: [],
            runtimeType: .python,
            healthcheck: nil,
            port: nil,
            dependsOn: []
        )

        let job = LaunchdJob.make(
            capabilityID: "haven.capability.py-svc",
            unitID: "haven.unit.py-app",
            preparedRuntime: prepared,
            serviceLayout: layout
        )

        XCTAssertTrue(job.standardOutPath.contains("haven.unit.py-app.stdout.log"))
        XCTAssertTrue(job.standardErrorPath.contains("haven.unit.py-app.stderr.log"))
        // Logs should be under the service logs directory
        XCTAssertTrue(job.standardOutPath.hasPrefix(layout.logs.path))
        XCTAssertTrue(job.standardErrorPath.hasPrefix(layout.logs.path))
    }
}

// MARK: - Plist Encoding Tests

final class LaunchdJobPlistTests: XCTestCase {

    func testPlistDictionaryContainsRequiredKeys() {
        let job = makeMinimalJob()
        let dict = job.plistDictionary()

        XCTAssertNotNil(dict["Label"])
        XCTAssertNotNil(dict["ProgramArguments"])
        XCTAssertNotNil(dict["WorkingDirectory"])
        XCTAssertNotNil(dict["StandardOutPath"])
        XCTAssertNotNil(dict["StandardErrorPath"])
        XCTAssertNotNil(dict["RunAtLoad"])
    }

    func testPlistDictionaryLabelValue() {
        let job = makeMinimalJob()
        let dict = job.plistDictionary()
        XCTAssertEqual(dict["Label"] as? String, "app.haven.cap.x.unit.y")
    }

    func testPlistDictionaryProgramArguments() {
        let job = makeMinimalJob()
        let dict = job.plistDictionary()
        let args = dict["ProgramArguments"] as? [String]
        XCTAssertEqual(args, ["/bin/x", "--flag"])
    }

    func testPlistDictionaryRunAtLoad() {
        let job = makeMinimalJob()
        let dict = job.plistDictionary()
        XCTAssertEqual(dict["RunAtLoad"] as? Bool, true)
    }

    func testPlistDictionaryOmitsEmptyEnvironment() {
        let job = LaunchdJob(
            label: "app.haven.cap.x.unit.y",
            programArguments: ["/bin/x"],
            environmentVariables: [:],
            workingDirectory: "/tmp",
            standardOutPath: "/tmp/stdout.log",
            standardErrorPath: "/tmp/stderr.log",
            runAtLoad: true,
            keepAlive: .none
        )
        let dict = job.plistDictionary()
        XCTAssertNil(dict["EnvironmentVariables"])
    }

    func testPlistDictionaryIncludesNonEmptyEnvironment() {
        let job = LaunchdJob(
            label: "app.haven.cap.x.unit.y",
            programArguments: ["/bin/x"],
            environmentVariables: ["FOO": "bar"],
            workingDirectory: "/tmp",
            standardOutPath: "/tmp/stdout.log",
            standardErrorPath: "/tmp/stderr.log",
            runAtLoad: true,
            keepAlive: .none
        )
        let dict = job.plistDictionary()
        let env = dict["EnvironmentVariables"] as? [String: String]
        XCTAssertEqual(env?["FOO"], "bar")
    }

    func testPlistDictionaryKeepAliveAlways() {
        let job = LaunchdJob(
            label: "app.haven.cap.x.unit.y",
            programArguments: ["/bin/x"],
            environmentVariables: [:],
            workingDirectory: "/tmp",
            standardOutPath: "/tmp/stdout.log",
            standardErrorPath: "/tmp/stderr.log",
            runAtLoad: true,
            keepAlive: .always
        )
        let dict = job.plistDictionary()
        XCTAssertEqual(dict["KeepAlive"] as? Bool, true)
    }

    func testPlistDictionaryKeepAliveSuccessfulExit() {
        let job = makeMinimalJob() // default keepAlive is .successfulExit
        let dict = job.plistDictionary()
        let keepAlive = dict["KeepAlive"] as? [String: Bool]
        XCTAssertNotNil(keepAlive)
        XCTAssertEqual(keepAlive?["SuccessfulExit"], false)
    }

    func testPlistDictionaryKeepAliveNoneIsOmitted() {
        let job = LaunchdJob(
            label: "app.haven.cap.x.unit.y",
            programArguments: ["/bin/x"],
            environmentVariables: [:],
            workingDirectory: "/tmp",
            standardOutPath: "/tmp/stdout.log",
            standardErrorPath: "/tmp/stderr.log",
            runAtLoad: true,
            keepAlive: .none
        )
        let dict = job.plistDictionary()
        XCTAssertNil(dict["KeepAlive"])
    }

    func testPlistDataProducesValidXML() throws {
        let job = makeMinimalJob()
        let data = try job.plistData()

        // Should be non-empty
        XCTAssertFalse(data.isEmpty)

        // Should be valid XML plist
        let xml = String(data: data, encoding: .utf8)
        XCTAssertNotNil(xml)
        XCTAssertTrue(xml?.contains("<!DOCTYPE plist") == true)
        XCTAssertTrue(xml?.contains("<plist version=\"1.0\">") == true)
    }

    func testPlistDataRoundTrips() throws {
        let job = LaunchdJob(
            label: "app.haven.cap.rt.unit.rt",
            programArguments: ["/bin/svc", "--port", "8080"],
            environmentVariables: ["DATA_DIR": "/data", "LOG_LEVEL": "debug"],
            workingDirectory: "/opt/services/rt",
            standardOutPath: "/opt/services/rt/logs/unit.rt.stdout.log",
            standardErrorPath: "/opt/services/rt/logs/unit.rt.stderr.log",
            runAtLoad: true,
            keepAlive: .successfulExit
        )

        let data = try job.plistData()

        // Deserialize and check values
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any]

        XCTAssertNotNil(plist)
        XCTAssertEqual(plist?["Label"] as? String, "app.haven.cap.rt.unit.rt")
        XCTAssertEqual(plist?["ProgramArguments"] as? [String], ["/bin/svc", "--port", "8080"])
        XCTAssertEqual(plist?["WorkingDirectory"] as? String, "/opt/services/rt")
        XCTAssertEqual(plist?["RunAtLoad"] as? Bool, true)

        let env = plist?["EnvironmentVariables"] as? [String: String]
        XCTAssertEqual(env?["DATA_DIR"], "/data")
        XCTAssertEqual(env?["LOG_LEVEL"], "debug")

        let keepAlive = plist?["KeepAlive"] as? [String: Bool]
        XCTAssertEqual(keepAlive?["SuccessfulExit"], false)
    }

    func testPlistDataEnvironmentRoundTripsAllValues() throws {
        let env = [
            "KEY_A": "value_a",
            "KEY_B": "value with spaces",
            "KEY_C": "/path/to/something",
            "KEY_D": "special=chars&here",
        ]
        let job = LaunchdJob(
            label: "app.haven.cap.env.unit.env",
            programArguments: ["/bin/x"],
            environmentVariables: env,
            workingDirectory: "/tmp",
            standardOutPath: "/tmp/stdout.log",
            standardErrorPath: "/tmp/stderr.log",
            runAtLoad: true,
            keepAlive: .none
        )

        let data = try job.plistData()
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any]
        let roundTripped = plist?["EnvironmentVariables"] as? [String: String]

        XCTAssertEqual(roundTripped, env)
    }
}

// MARK: - ProgramArguments Integration Tests

final class LaunchdJobProgramArgumentsTests: XCTestCase {

    func testNativeProgramArgumentsStartWithExecutable() {
        let layout = makeLayout()
        let prepared = makeNativePreparedRuntime(
            arguments: ["--datadir", "/data", "--port", "5432"]
        )

        let job = LaunchdJob.make(
            capabilityID: "haven.capability.test-library",
            unitID: "haven.unit.test-db",
            preparedRuntime: prepared,
            serviceLayout: layout
        )

        XCTAssertEqual(job.programArguments.first, "/opt/haven/bin/test-db")
        XCTAssertEqual(
            job.programArguments,
            ["/opt/haven/bin/test-db", "--datadir", "/data", "--port", "5432"]
        )
    }

    func testEntrypointStyleProgramArguments() {
        // Simulates entrypoint-style spec where arguments are only flags
        let layout = makeLayout()
        let prepared = PreparedRuntime(
            unitID: "haven.unit.hello-svc",
            executableURL: URL(fileURLWithPath: "/opt/haven/installed/haven.unit.hello-svc/HelloService"),
            arguments: ["--port", "8088"],
            environment: [:],
            workingDirectory: layout.serviceRoot,
            managedDirectories: [],
            runtimeType: .native,
            healthcheck: nil,
            port: 8088,
            dependsOn: []
        )

        let job = LaunchdJob.make(
            capabilityID: "haven.capability.hello",
            unitID: "haven.unit.hello-svc",
            preparedRuntime: prepared,
            serviceLayout: layout
        )

        XCTAssertEqual(
            job.programArguments,
            ["/opt/haven/installed/haven.unit.hello-svc/HelloService", "--port", "8088"]
        )
    }

    func testPythonProgramArgumentsStartWithInterpreter() {
        let layout = makeLayout(capabilityID: "haven.capability.py-svc")
        let venvRoot = layout.run
            .appendingPathComponent("venvs")
            .appendingPathComponent("haven.unit.py-app")
        let pythonExe = venvRoot
            .appendingPathComponent("bin")
            .appendingPathComponent("python3")

        let prepared = PreparedRuntime(
            unitID: "haven.unit.py-app",
            executableURL: pythonExe,
            arguments: ["-m", "pyapp", "--serve"],
            environment: ["VIRTUAL_ENV": venvRoot.path],
            workingDirectory: layout.serviceRoot,
            managedDirectories: [],
            runtimeType: .python,
            healthcheck: nil,
            port: nil,
            dependsOn: []
        )

        let job = LaunchdJob.make(
            capabilityID: "haven.capability.py-svc",
            unitID: "haven.unit.py-app",
            preparedRuntime: prepared,
            serviceLayout: layout
        )

        XCTAssertEqual(job.programArguments.first, pythonExe.path)
        XCTAssertEqual(job.programArguments, [pythonExe.path, "-m", "pyapp", "--serve"])
    }

    func testPlistRoundTripPreservesProgramArguments() throws {
        let layout = makeLayout()
        let prepared = makeNativePreparedRuntime(arguments: ["--port", "8080"])

        let job = LaunchdJob.make(
            capabilityID: "cap.x",
            unitID: "unit.y",
            preparedRuntime: prepared,
            serviceLayout: layout
        )

        let data = try job.plistData()
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any]

        let plistArgs = plist?["ProgramArguments"] as? [String]
        XCTAssertEqual(plistArgs, ["/opt/haven/bin/test-db", "--port", "8080"])
    }
}

// MARK: - LaunchdJob Equality Tests

final class LaunchdJobEqualityTests: XCTestCase {

    func testEquality() {
        let a = makeMinimalJob()
        let b = makeMinimalJob()
        XCTAssertEqual(a, b)
    }

    func testInequalityDifferentLabel() {
        let a = makeMinimalJob()
        let b = LaunchdJob(
            label: "app.haven.cap.z.unit.z",
            programArguments: a.programArguments,
            environmentVariables: a.environmentVariables,
            workingDirectory: a.workingDirectory,
            standardOutPath: a.standardOutPath,
            standardErrorPath: a.standardErrorPath,
            runAtLoad: a.runAtLoad,
            keepAlive: a.keepAlive
        )
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - LaunchdJob.logPath Tests

final class LaunchdJobLogPathTests: XCTestCase {

    func testStdoutLogPath() {
        let layout = makeLayout()
        let path = LaunchdJob.logPath(unitID: "haven.unit.test-db", stream: "stdout", serviceLayout: layout)
        let expected = layout.logs.appendingPathComponent("haven.unit.test-db.stdout.log").path
        XCTAssertEqual(path, expected)
    }

    func testStderrLogPath() {
        let layout = makeLayout()
        let path = LaunchdJob.logPath(unitID: "haven.unit.test-db", stream: "stderr", serviceLayout: layout)
        let expected = layout.logs.appendingPathComponent("haven.unit.test-db.stderr.log").path
        XCTAssertEqual(path, expected)
    }

    func testLogPathIsUnderServiceLogs() {
        let layout = makeLayout()
        let path = LaunchdJob.logPath(unitID: "unit.x", stream: "stdout", serviceLayout: layout)
        XCTAssertTrue(path.hasPrefix(layout.logs.path))
    }

    func testLogPathIsDeterministic() {
        let layout = makeLayout()
        let a = LaunchdJob.logPath(unitID: "unit.x", stream: "stdout", serviceLayout: layout)
        let b = LaunchdJob.logPath(unitID: "unit.x", stream: "stdout", serviceLayout: layout)
        XCTAssertEqual(a, b)
    }
}

// MARK: - Test Helpers

private let testBaseDir = URL(fileURLWithPath: "/tmp/haven-launchd-test")

private func makeLayout(
    capabilityID: String = "haven.capability.test-library"
) -> ServiceDirectoryLayout {
    ServiceDirectoryLayout(
        servicesDirectory: testBaseDir.appendingPathComponent("Services"),
        capabilityID: capabilityID
    )
}

private func makeNativePreparedRuntime(
    unitID: String = "haven.unit.test-db",
    arguments: [String] = ["--datadir", "/data"],
    environment: [String: String] = [:],
    port: Int? = nil
) -> PreparedRuntime {
    PreparedRuntime(
        unitID: unitID,
        executableURL: URL(fileURLWithPath: "/opt/haven/bin/test-db"),
        arguments: arguments,
        environment: environment,
        workingDirectory: makeLayout().serviceRoot,
        managedDirectories: makeLayout().allDirectories,
        runtimeType: .native,
        healthcheck: nil,
        port: port,
        dependsOn: []
    )
}

private func makeMinimalJob() -> LaunchdJob {
    let layout = makeLayout()
    let prepared = PreparedRuntime(
        unitID: "unit.y",
        executableURL: URL(fileURLWithPath: "/bin/x"),
        arguments: ["--flag"],
        environment: ["KEY": "val"],
        workingDirectory: layout.serviceRoot,
        managedDirectories: [],
        runtimeType: .native,
        healthcheck: nil,
        port: nil,
        dependsOn: []
    )
    return LaunchdJob.make(
        capabilityID: "cap.x",
        unitID: "unit.y",
        preparedRuntime: prepared,
        serviceLayout: layout
    )
}
