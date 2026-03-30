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
