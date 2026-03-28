import XCTest
import HavenCore

final class CapabilityTests: XCTestCase {
    func testInitStoresProperties() {
        let cap = Capability(id: "cap.test", name: "Test", version: "1.0.0")
        XCTAssertEqual(cap.id, "cap.test")
        XCTAssertEqual(cap.name, "Test")
        XCTAssertEqual(cap.version, "1.0.0")
    }

    func testEqualityIsIdBased() {
        let a = Capability(id: "cap.x", name: "X", version: "1.0.0")
        let b = Capability(id: "cap.x", name: "X", version: "1.0.0")
        XCTAssertEqual(a, b)
    }
}

final class BundleTests: XCTestCase {
    func testStoresCapabilities() {
        let cap = Capability(id: "cap.a", name: "A", version: "1.0.0")
        let bundle = Bundle(id: "bundle.test", name: "Test Bundle", capabilities: [cap])
        XCTAssertEqual(bundle.capabilities.count, 1)
        XCTAssertEqual(bundle.capabilities.first?.id, "cap.a")
    }
}

final class RuntimeUnitTests: XCTestCase {
    private func makeUnit() -> RuntimeUnit {
        let bundle = Bundle(id: "b", name: "B", capabilities: [])
        return RuntimeUnit(id: "unit.1", bundle: bundle)
    }

    func testInitialStateIsIdle() {
        XCTAssertEqual(makeUnit().state, .idle)
    }

    func testStartTransitionsToRunning() {
        var unit = makeUnit()
        unit.start()
        XCTAssertEqual(unit.state, .running)
    }

    func testStopTransitionsToStopped() {
        var unit = makeUnit()
        unit.start()
        unit.stop()
        XCTAssertEqual(unit.state, .stopped)
    }
}
