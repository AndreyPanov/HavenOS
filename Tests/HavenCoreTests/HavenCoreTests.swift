import XCTest
import HavenCore

// MARK: - Capability Tests

final class CapabilityTests: XCTestCase {

    func testInitStoresProperties() {
        let cap = Capability(id: "cap.test", name: "Test", version: "1.0.0", description: "A test.")
        XCTAssertEqual(cap.id, "cap.test")
        XCTAssertEqual(cap.name, "Test")
        XCTAssertEqual(cap.version, "1.0.0")
        XCTAssertEqual(cap.description, "A test.")
    }

    func testEquality() {
        let a = Capability(id: "cap.x", name: "X", version: "1.0.0")
        let b = Capability(id: "cap.x", name: "X", version: "1.0.0")
        XCTAssertEqual(a, b)
    }

    func testCodableRoundTrip() throws {
        let original = Capability.testLibraryExample
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Capability.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testValidationSuccess() {
        XCTAssertNoThrow(try Capability.testLibraryExample.validate())
    }

    func testValidationFailsOnEmptyID() {
        let cap = Capability(id: "", name: "X", version: "1.0.0")
        XCTAssertThrowsError(try cap.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("id") == true)
        }
    }

    func testValidationFailsOnEmptyName() {
        let cap = Capability(id: "cap.x", name: "  ", version: "1.0.0")
        XCTAssertThrowsError(try cap.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("name") == true)
        }
    }

    func testValidationFailsOnEmptyVersion() {
        let cap = Capability(id: "cap.x", name: "X", version: "")
        XCTAssertThrowsError(try cap.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("version") == true)
        }
    }

    func testNewFieldsRoundTrip() throws {
        let cap = Capability(
            id: "cap.test", name: "Test", version: "1.0.0",
            description: "Desc",
            icon: "books.vertical",
            fullDescription: "A rich description.",
            notes: ["Python", "Web"],
            screenshots: ["/path/to/shot.png"]
        )
        let data = try JSONEncoder().encode(cap)
        let decoded = try JSONDecoder().decode(Capability.self, from: data)
        XCTAssertEqual(decoded.icon, "books.vertical")
        XCTAssertEqual(decoded.fullDescription, "A rich description.")
        XCTAssertEqual(decoded.notes, ["Python", "Web"])
        XCTAssertEqual(decoded.screenshots, ["/path/to/shot.png"])
    }

    func testNewFieldsDefaultToNilOrEmpty() throws {
        let json = """
        {"id": "cap.x", "name": "X", "version": "1.0.0"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Capability.self, from: json)
        XCTAssertNil(decoded.icon)
        XCTAssertNil(decoded.fullDescription)
        XCTAssertEqual(decoded.notes, [])
        XCTAssertEqual(decoded.screenshots, [])
    }

    func testWithResolvedImages() {
        let cap = Capability(id: "cap.x", name: "X", version: "1.0.0", iconImage: "icon.png", screenshots: ["a.png"])
        let resolved = cap.withResolvedImages(iconImage: "/abs/icon.png", screenshots: ["/abs/a.png"])
        XCTAssertEqual(resolved.screenshots, ["/abs/a.png"])
        XCTAssertEqual(resolved.iconImage, "/abs/icon.png")
        XCTAssertEqual(resolved.id, cap.id)
    }
}

// MARK: - SettingField Tests

final class SettingFieldTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let field = SettingField(key: "port", label: "Port", fieldType: .integer, defaultValue: "8080")
        let data = try JSONEncoder().encode(field)
        let decoded = try JSONDecoder().decode(SettingField.self, from: data)
        XCTAssertEqual(field, decoded)
    }

    func testValidationSuccess() {
        let field = SettingField(key: "music_path", label: "Music Path", fieldType: .path)
        XCTAssertNoThrow(try field.validate())
    }

    func testValidationFailsOnEmptyKey() {
        let field = SettingField(key: "", label: "Label", fieldType: .string)
        XCTAssertThrowsError(try field.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("key") == true)
        }
    }

    func testValidationFailsOnInvalidIdentifier() {
        let field = SettingField(key: "123bad", label: "Label", fieldType: .string)
        XCTAssertThrowsError(try field.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("identifier") == true)
        }
    }

    func testValidationFailsOnKeyWithSpaces() {
        let field = SettingField(key: "bad key", label: "Label", fieldType: .string)
        XCTAssertThrowsError(try field.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("identifier") == true)
        }
    }

    func testValidationFailsOnEmptyLabel() {
        let field = SettingField(key: "ok_key", label: "  ", fieldType: .string)
        XCTAssertThrowsError(try field.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("label") == true)
        }
    }
}

// MARK: - Healthcheck Tests

final class HealthcheckTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let hc = Healthcheck(type: .http, target: "http://localhost:8080/health")
        let data = try JSONEncoder().encode(hc)
        let decoded = try JSONDecoder().decode(Healthcheck.self, from: data)
        XCTAssertEqual(hc, decoded)
    }

    func testValidationSuccess() {
        let hc = Healthcheck(type: .tcp, target: "localhost:5432", intervalSeconds: 10, retries: 2)
        XCTAssertNoThrow(try hc.validate())
    }

    func testValidationFailsOnEmptyTarget() {
        let hc = Healthcheck(type: .exec, target: "")
        XCTAssertThrowsError(try hc.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("target") == true)
        }
    }

    func testValidationFailsOnZeroInterval() {
        let hc = Healthcheck(type: .http, target: "http://localhost", intervalSeconds: 0)
        XCTAssertThrowsError(try hc.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("intervalSeconds") == true)
        }
    }

    func testValidationFailsOnZeroRetries() {
        let hc = Healthcheck(type: .http, target: "http://localhost", retries: 0)
        XCTAssertThrowsError(try hc.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("retries") == true)
        }
    }
}

// MARK: - Bundle Tests

final class BundleTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let original = Bundle.testLibraryBasicExample
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Bundle.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testValidationSuccess() {
        XCTAssertNoThrow(try Bundle.testLibraryBasicExample.validate())
    }

    func testValidationFailsOnEmptyID() {
        let bundle = Bundle(id: "", name: "B", capability: "cap.x")
        XCTAssertThrowsError(try bundle.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("id") == true)
        }
    }

    func testValidationFailsOnEmptyName() {
        let bundle = Bundle(id: "b.1", name: "", capability: "cap.x")
        XCTAssertThrowsError(try bundle.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("name") == true)
        }
    }

    func testValidationFailsOnEmptyCapability() {
        let bundle = Bundle(id: "b.1", name: "B", capability: "")
        XCTAssertThrowsError(try bundle.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("capability") == true)
        }
    }

    func testValidationFailsOnBlankCapability() {
        let bundle = Bundle(id: "b.1", name: "B", capability: "  ")
        XCTAssertThrowsError(try bundle.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("capability") == true)
        }
    }

    func testValidationCascadesToSettings() {
        let badSetting = SettingField(key: "123", label: "Bad", fieldType: .string)
        let bundle = Bundle(id: "b.1", name: "B", capability: "cap.x", settings: [badSetting])
        XCTAssertThrowsError(try bundle.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("identifier") == true)
        }
    }

    func testInstructionsRoundTrip() throws {
        let bundle = Bundle(
            id: "b.1", name: "B", capability: "cap.x",
            instructions: "Step 1: Do this\nStep 2: Do that"
        )
        let data = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(Bundle.self, from: data)
        XCTAssertEqual(decoded.instructions, "Step 1: Do this\nStep 2: Do that")
    }

    func testInstructionsDefaultsToNil() throws {
        let json = """
        {"id": "b.1", "name": "B", "capability": "cap.x"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Bundle.self, from: json)
        XCTAssertNil(decoded.instructions)
    }
}

// MARK: - RuntimeUnit Tests

final class RuntimeUnitTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let original = RuntimeUnit.testDBExample
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeUnit.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testValidationSuccess() {
        XCTAssertNoThrow(try RuntimeUnit.testDBExample.validate())
    }

    func testValidationFailsOnEmptyID() {
        let unit = RuntimeUnit(id: "", bundleID: "b", runtimeType: .native,
                               installSource: "/bin/x", launchArguments: ["/bin/x"])
        XCTAssertThrowsError(try unit.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("id") == true)
        }
    }

    func testValidationFailsOnEmptyBundleID() {
        let unit = RuntimeUnit(id: "u.1", bundleID: "", runtimeType: .native,
                               installSource: "/bin/x", launchArguments: ["/bin/x"])
        XCTAssertThrowsError(try unit.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("bundleID") == true)
        }
    }

    func testValidationFailsOnEmptyInstallSource() {
        let unit = RuntimeUnit(id: "u.1", bundleID: "b", runtimeType: .native,
                               installSource: "", launchArguments: ["/bin/x"])
        XCTAssertThrowsError(try unit.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("installSource") == true)
        }
    }

    func testValidationFailsOnEmptyLaunchArguments() {
        let unit = RuntimeUnit(id: "u.1", bundleID: "b", runtimeType: .native,
                               installSource: "/bin/x", launchArguments: [])
        XCTAssertThrowsError(try unit.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("launchArguments") == true)
        }
    }

    func testValidationCascadesToHealthcheck() {
        let badHC = Healthcheck(type: .http, target: "", intervalSeconds: 30, retries: 3)
        let unit = RuntimeUnit(id: "u.1", bundleID: "b", runtimeType: .native,
                               installSource: "/bin/x", launchArguments: ["/bin/x"],
                               healthcheck: badHC)
        XCTAssertThrowsError(try unit.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("target") == true)
        }
    }

    func testRuntimeTypeEnumCoverage() {
        XCTAssertEqual(RuntimeUnit.RuntimeType.native.rawValue, "native")
        XCTAssertEqual(RuntimeUnit.RuntimeType.python.rawValue, "python")
    }

    // MARK: - Python Validation

    func testPythonUnitValidationSuccess() {
        XCTAssertNoThrow(try RuntimeUnit.testPythonExample.validate())
    }

    func testPythonUnitValidationFailsWithoutPythonConfig() {
        let unit = RuntimeUnit(
            id: "u.1", bundleID: "b.1", runtimeType: .python,
            installSource: "", launchArguments: []
        )
        XCTAssertThrowsError(try unit.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("python") == true)
        }
    }

    func testPythonUnitValidationFailsOnEmptyPackage() {
        let unit = RuntimeUnit(
            id: "u.1", bundleID: "b.1", runtimeType: .python,
            installSource: "", launchArguments: [],
            python: RuntimeUnit.PythonConfig(
                package: "", version: "1.0",
                entrypoint: .init(module: "mod")
            )
        )
        XCTAssertThrowsError(try unit.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("package") == true)
        }
    }

    func testPythonUnitValidationFailsOnEmptyVersion() {
        let unit = RuntimeUnit(
            id: "u.1", bundleID: "b.1", runtimeType: .python,
            installSource: "", launchArguments: [],
            python: RuntimeUnit.PythonConfig(
                package: "pkg", version: "",
                entrypoint: .init(module: "mod")
            )
        )
        XCTAssertThrowsError(try unit.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("version") == true)
        }
    }

    func testPythonUnitValidationFailsOnEmptyModule() {
        let unit = RuntimeUnit(
            id: "u.1", bundleID: "b.1", runtimeType: .python,
            installSource: "", launchArguments: [],
            python: RuntimeUnit.PythonConfig(
                package: "pkg", version: "1.0",
                entrypoint: .init(module: "")
            )
        )
        XCTAssertThrowsError(try unit.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("module") == true)
        }
    }

    func testPythonUnitValidationFailsWithArtifact() {
        let unit = RuntimeUnit(
            id: "u.1", bundleID: "b.1", runtimeType: .python,
            installSource: "", launchArguments: [],
            artifact: Artifact(
                type: .githubRelease, repo: "owner/repo", version: "v1.0.0",
                assets: [ArtifactAsset(os: "macos", arch: "arm64", file: "app.zip")]
            ),
            python: RuntimeUnit.PythonConfig(
                package: "pkg", version: "1.0",
                entrypoint: .init(module: "mod")
            )
        )
        XCTAssertThrowsError(try unit.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("artifact") == true)
        }
    }

    func testNativeUnitValidationFailsWithPythonConfig() {
        let unit = RuntimeUnit(
            id: "u.1", bundleID: "b.1", runtimeType: .native,
            installSource: "/bin/x", launchArguments: ["/bin/x"],
            python: RuntimeUnit.PythonConfig(
                package: "pkg", version: "1.0",
                entrypoint: .init(module: "mod")
            )
        )
        XCTAssertThrowsError(try unit.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("python") == true)
        }
    }

    func testPythonUnitAllowsEmptyInstallSourceAndLaunchArgs() {
        let unit = RuntimeUnit(
            id: "u.1", bundleID: "b.1", runtimeType: .python,
            installSource: "", launchArguments: [],
            python: RuntimeUnit.PythonConfig(
                package: "pkg", version: "1.0",
                entrypoint: .init(module: "mod")
            )
        )
        XCTAssertNoThrow(try unit.validate())
    }

    func testPythonConfigCodableRoundTrip() throws {
        let original = RuntimeUnit.testPythonExample
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeUnit.self, from: data)
        XCTAssertEqual(decoded.python?.package, "calibreweb")
        XCTAssertEqual(decoded.python?.version, "0.6.26")
        XCTAssertEqual(decoded.python?.entrypoint.module, "calibreweb")
        XCTAssertEqual(decoded.python?.entrypoint.args, [])
        XCTAssertEqual(decoded.runtimeType, .python)
    }

    func testPythonEntrypointArgsTakePrecedence() throws {
        // python.entrypoint.args should take precedence over top-level launchArguments
        let json = """
        {
            "id": "u.1", "bundleID": "b.1", "runtimeType": "python",
            "launchArguments": ["--should-be-ignored"],
            "python": {
                "package": "pkg", "version": "1.0",
                "entrypoint": { "module": "mod", "args": ["-p", "/data/app.db"] }
            }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RuntimeUnit.self, from: json)
        XCTAssertEqual(decoded.launchArguments, ["-p", "/data/app.db"])
        XCTAssertEqual(decoded.python?.entrypoint.args, ["-p", "/data/app.db"])
    }

    func testPythonEntrypointWithoutArgsFallsToLaunchArguments() throws {
        let json = """
        {
            "id": "u.1", "bundleID": "b.1", "runtimeType": "python",
            "launchArguments": ["--fallback"],
            "python": {
                "package": "pkg", "version": "1.0",
                "entrypoint": { "module": "mod" }
            }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RuntimeUnit.self, from: json)
        XCTAssertEqual(decoded.launchArguments, ["--fallback"])
        XCTAssertEqual(decoded.python?.entrypoint.args, [])
    }

    func testEntrypointRoundTrip() throws {
        let unit = RuntimeUnit(
            id: "u.1", bundleID: "b.1", runtimeType: .native,
            installSource: "/bin/x", launchArguments: ["/bin/x"],
            entrypoint: RuntimeUnit.Entrypoint(command: "./my-server", args: ["--port", "8080"])
        )
        let data = try JSONEncoder().encode(unit)
        let decoded = try JSONDecoder().decode(RuntimeUnit.self, from: data)
        XCTAssertEqual(decoded.entrypoint?.command, "./my-server")
        // entrypoint.args takes precedence over launchArguments
        XCTAssertEqual(decoded.launchArguments, ["--port", "8080"])
    }

    func testEntrypointNilWhenAbsent() throws {
        let unit = RuntimeUnit(
            id: "u.1", bundleID: "b.1", runtimeType: .native,
            installSource: "/bin/x", launchArguments: ["/bin/x"]
        )
        XCTAssertNil(unit.entrypoint)
        let data = try JSONEncoder().encode(unit)
        let decoded = try JSONDecoder().decode(RuntimeUnit.self, from: data)
        XCTAssertNil(decoded.entrypoint)
    }

    func testValidationAllowsEmptyInstallSourceWithArtifact() {
        let unit = RuntimeUnit(
            id: "u.1", bundleID: "b.1", runtimeType: .native,
            installSource: "", launchArguments: ["--port", "8080"],
            artifact: Artifact(
                type: .githubRelease, repo: "owner/repo", version: "v1.0.0",
                assets: [ArtifactAsset(os: "macos", arch: "arm64", file: "app.zip")]
            )
        )
        XCTAssertNoThrow(try unit.validate())
    }
}

// MARK: - ServiceRecord Tests

final class ServiceRecordTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let original = ServiceRecord.testLibraryExample
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ServiceRecord.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testValidationSuccess() {
        XCTAssertNoThrow(try ServiceRecord.testLibraryExample.validate())
    }

    func testValidationFailsOnEmptyID() {
        let record = ServiceRecord(
            id: "",
            capability: .testLibraryExample,
            bundle: .testLibraryBasicExample,
            units: [.testDBExample]
        )
        XCTAssertThrowsError(try record.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("id") == true)
        }
    }

    func testValidationCascadesToChildren() {
        let badCap = Capability(id: "", name: "X", version: "1.0.0")
        let record = ServiceRecord(
            id: "r.1",
            capability: badCap,
            bundle: .testLibraryBasicExample,
            units: [.testDBExample]
        )
        XCTAssertThrowsError(try record.validate())
    }
}

// MARK: - OnboardingStep Tests

final class OnboardingStepTests: XCTestCase {

    func testCodableRoundTripInfo() throws {
        let step = OnboardingStep(
            type: .info,
            title: "Welcome",
            body: "Your service is installed."
        )
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(OnboardingStep.self, from: data)
        XCTAssertEqual(step, decoded)
    }

    func testCodableRoundTripCredentials() throws {
        let step = OnboardingStep(
            type: .credentials,
            title: "Login",
            body: "Default credentials below.",
            fields: [
                OnboardingField(label: "Username", value: "admin"),
                OnboardingField(label: "Password", value: "secret123"),
            ]
        )
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(OnboardingStep.self, from: data)
        XCTAssertEqual(step, decoded)
        XCTAssertEqual(decoded.fields.count, 2)
        XCTAssertEqual(decoded.fields[0].label, "Username")
        XCTAssertEqual(decoded.fields[1].value, "secret123")
    }

    func testCodableRoundTripAction() throws {
        let step = OnboardingStep(
            type: .action,
            title: "Open App",
            body: "Access the web UI.",
            url: "http://localhost:8080"
        )
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(OnboardingStep.self, from: data)
        XCTAssertEqual(step, decoded)
        XCTAssertEqual(decoded.url, "http://localhost:8080")
    }

    func testDefaultsToEmptyFieldsAndNilURL() throws {
        let json = """
        {"type": "info", "title": "Hello", "body": "World"}
        """.data(using: .utf8)!
        let step = try JSONDecoder().decode(OnboardingStep.self, from: json)
        XCTAssertEqual(step.fields, [])
        XCTAssertNil(step.url)
    }

    func testValidationFailsOnEmptyTitle() {
        let step = OnboardingStep(type: .info, title: "", body: "Some body")
        XCTAssertThrowsError(try step.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("title") == true)
        }
    }

    func testValidationFailsOnEmptyBody() {
        let step = OnboardingStep(type: .info, title: "Title", body: "  ")
        XCTAssertThrowsError(try step.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("body") == true)
        }
    }

    func testValidationSucceeds() {
        let step = OnboardingStep(type: .credentials, title: "Login", body: "Use defaults.")
        XCTAssertNoThrow(try step.validate())
    }
}

// MARK: - OnboardingField Tests

final class OnboardingFieldTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let field = OnboardingField(label: "Port", value: "8080")
        let data = try JSONEncoder().encode(field)
        let decoded = try JSONDecoder().decode(OnboardingField.self, from: data)
        XCTAssertEqual(field, decoded)
    }
}

// MARK: - Onboarding Tests

final class OnboardingTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let onboarding = Onboarding(steps: [
            OnboardingStep(type: .info, title: "Welcome", body: "Hello"),
            OnboardingStep(type: .action, title: "Open", body: "Go", url: "http://localhost"),
        ])
        let data = try JSONEncoder().encode(onboarding)
        let decoded = try JSONDecoder().decode(Onboarding.self, from: data)
        XCTAssertEqual(onboarding, decoded)
    }

    func testDefaultsToEmptySteps() throws {
        let json = """
        {}
        """.data(using: .utf8)!
        let onboarding = try JSONDecoder().decode(Onboarding.self, from: json)
        XCTAssertEqual(onboarding.steps, [])
    }

    func testValidationCascadesToSteps() {
        let onboarding = Onboarding(steps: [
            OnboardingStep(type: .info, title: "", body: "Bad step")
        ])
        XCTAssertThrowsError(try onboarding.validate())
    }
}

// MARK: - Provision Tests

final class ProvisionTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let provision = Provision(
            description: "Sample database",
            source: "https://example.com/metadata.db",
            destination: "/srv/data/metadata.db",
            condition: "include_sample_db"
        )
        let data = try JSONEncoder().encode(provision)
        let decoded = try JSONDecoder().decode(Provision.self, from: data)
        XCTAssertEqual(provision, decoded)
    }

    func testConditionDefaultsToNil() throws {
        let json = """
        {"description": "Test", "source": "https://x.com/f", "destination": "/tmp/f"}
        """.data(using: .utf8)!
        let provision = try JSONDecoder().decode(Provision.self, from: json)
        XCTAssertNil(provision.condition)
    }

    func testValidationFailsOnEmptySource() {
        let provision = Provision(description: "X", source: "  ", destination: "/tmp/f")
        XCTAssertThrowsError(try provision.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("source") == true)
        }
    }

    func testValidationFailsOnEmptyDestination() {
        let provision = Provision(description: "X", source: "https://x.com/f", destination: "")
        XCTAssertThrowsError(try provision.validate()) { error in
            XCTAssertTrue((error as? ValidationError)?.message.contains("destination") == true)
        }
    }

    func testValidationSucceeds() {
        let provision = Provision(
            description: "DB", source: "https://x.com/f", destination: "/tmp/f"
        )
        XCTAssertNoThrow(try provision.validate())
    }
}

// MARK: - Bundle Onboarding Tests

final class BundleOnboardingTests: XCTestCase {

    func testBundleWithOnboardingRoundTrip() throws {
        let bundle = Bundle(
            id: "b.1", name: "B",
            capability: "cap.1",
            runtimeUnits: ["u.1"],
            onboarding: Onboarding(steps: [
                OnboardingStep(type: .credentials, title: "Login", body: "Use defaults.",
                               fields: [OnboardingField(label: "User", value: "admin")])
            ]),
            provisions: [
                Provision(description: "DB", source: "https://x.com/db",
                          destination: "/data/db", condition: "include_db")
            ]
        )
        let data = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(Bundle.self, from: data)
        XCTAssertEqual(bundle, decoded)
        XCTAssertEqual(decoded.onboarding?.steps.count, 1)
        XCTAssertEqual(decoded.provisions.count, 1)
    }

    func testBundleWithoutOnboardingDefaultsToNil() throws {
        let json = """
        {"id": "b.1", "name": "B", "capability": "c.1", "runtimeUnits": ["u.1"]}
        """.data(using: .utf8)!
        let bundle = try JSONDecoder().decode(Bundle.self, from: json)
        XCTAssertNil(bundle.onboarding)
        XCTAssertEqual(bundle.provisions, [])
    }

    func testBundleValidationCascadesToOnboarding() {
        let bundle = Bundle(
            id: "b.1", name: "B", capability: "c.1",
            onboarding: Onboarding(steps: [
                OnboardingStep(type: .info, title: "", body: "Invalid")
            ])
        )
        XCTAssertThrowsError(try bundle.validate())
    }

    func testBundleValidationCascadesToProvisions() {
        let bundle = Bundle(
            id: "b.1", name: "B", capability: "c.1",
            provisions: [
                Provision(description: "X", source: "", destination: "/tmp/f")
            ]
        )
        XCTAssertThrowsError(try bundle.validate())
    }
}
