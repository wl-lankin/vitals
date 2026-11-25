import XCTest
@testable import VitalsCore

final class NetworkProbeTests: XCTestCase {
    func testPhysicalFilter() {
        for name in ["en0", "en5", "pdp_ip0"] { XCTAssertTrue(NetworkMath.isPhysical(name), name) }
        for name in ["lo0", "utun3", "awdl0", "llw0", "bridge0", "ap1", "anpi0", "gif0", "stf0"] {
            XCTAssertFalse(NetworkMath.isPhysical(name), name)
        }
    }

    func testRate() {
        XCTAssertEqual(NetworkMath.rate(previous: 1000, current: 3000, seconds: 2), 1000)
        XCTAssertEqual(NetworkMath.rate(previous: 3000, current: 1000, seconds: 2), 0)
        XCTAssertEqual(NetworkMath.rate(previous: 0, current: 10, seconds: 0), 0)
    }

    func testLinkKind() {
        XCTAssertEqual(NetworkMath.linkKind(name: "en0", isWiFi: true), .wifi)
        XCTAssertEqual(NetworkMath.linkKind(name: "en6", isWiFi: false), .ethernet)
        XCTAssertEqual(NetworkMath.linkKind(name: "pdp_ip0", isWiFi: false), .cellular)
        XCTAssertEqual(NetworkMath.linkKind(name: "utun4", isWiFi: false), .vpn)
        XCTAssertEqual(NetworkMath.linkKind(name: "ipsec0", isWiFi: false), .vpn)
        XCTAssertEqual(NetworkMath.linkKind(name: "ppp0", isWiFi: false), .vpn)
        XCTAssertEqual(NetworkMath.linkKind(name: "bridge0", isWiFi: false), .other)
    }
}
