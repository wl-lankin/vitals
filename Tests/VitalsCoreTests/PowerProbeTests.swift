import XCTest
@testable import VitalsCore

final class PowerProbeTests: XCTestCase {
    func testReadIsConsistent() {
        let probe = PowerProbe()
        let sample = probe.read()
        if let b = sample.battery {
            XCTAssertTrue((0...100).contains(b.percent))
            if let h = b.health { XCTAssertTrue((0...1).contains(h)) }
            if let t = b.timeRemaining { XCTAssertGreaterThan(t, 0) }
            if b.state == .battery { XCTAssertNil(b.adapterWatts) }
        }
        if let w = sample.systemWatts { XCTAssertGreaterThan(w, 0) }
    }
}
