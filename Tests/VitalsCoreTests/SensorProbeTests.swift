import XCTest
@testable import VitalsCore

final class SensorProbeTests: XCTestCase {
    func testCPUSensorNames() {
        XCTAssertTrue(SensorProbe.isCPUSensor("PMU tdie4"))
        XCTAssertTrue(SensorProbe.isCPUSensor("pACC MTR Temp Sensor0"))
        XCTAssertFalse(SensorProbe.isCPUSensor("gas gauge battery"))
        XCTAssertFalse(SensorProbe.isCPUSensor("NAND CH0 temp"))
        XCTAssertFalse(SensorProbe.isCPUSensor("PMU tcal"))
    }

    func testReadIsPlausibleAndCached() {
        let probe = SensorProbe()
        let a = probe.read()
        let b = probe.read()
        XCTAssertEqual(a.cpuTemperature, b.cpuTemperature)
        if let t = a.cpuTemperature { XCTAssertTrue((0...130).contains(t)) }
        if let g = a.gpuUsage { XCTAssertTrue((0...1).contains(g)) }
    }
}
