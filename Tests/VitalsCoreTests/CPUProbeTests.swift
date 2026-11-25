import XCTest
@testable import VitalsCore

final class CPUProbeTests: XCTestCase {
    func testFractions() {
        let f = CPUMath.fractions(previous: CPUTicks(user: 100, system: 50, idle: 850),
                                  current: CPUTicks(user: 130, system: 60, idle: 910))
        XCTAssertEqual(f.total, 0.4, accuracy: 1e-9)
        XCTAssertEqual(f.user, 0.3, accuracy: 1e-9)
        XCTAssertEqual(f.system, 0.1, accuracy: 1e-9)
    }

    func testEmptyAndBackwardsDeltaGiveZero() {
        let t = CPUTicks(user: 10, system: 10, idle: 10)
        XCTAssertEqual(CPUMath.fractions(previous: t, current: t).total, 0)
        let back = CPUTicks(user: 5, system: 10, idle: 10)
        XCTAssertEqual(CPUMath.fractions(previous: t, current: back).total, 0)
    }

    func testKindsFromDeviceTree() {
        let map = [0: "E", 1: "E", 2: "P", 3: "P"]
        XCTAssertEqual(CPUMath.kinds(count: 4, clusterByCPU: map, performanceCount: nil, efficiencyCount: nil),
                       [.efficiency, .efficiency, .performance, .performance])
    }

    func testKindsFallbackToPerfLevels() {
        XCTAssertEqual(CPUMath.kinds(count: 5, clusterByCPU: [:], performanceCount: 2, efficiencyCount: 3),
                       [.efficiency, .efficiency, .efficiency, .performance, .performance])
    }

    func testKindsUnknownWhenNothingMatches() {
        XCTAssertEqual(CPUMath.kinds(count: 3, clusterByCPU: [0: "E"], performanceCount: nil, efficiencyCount: nil),
                       [.unknown, .unknown, .unknown])
    }
}
