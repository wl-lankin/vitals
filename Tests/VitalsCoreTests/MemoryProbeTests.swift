import XCTest
@testable import VitalsCore

final class MemoryProbeTests: XCTestCase {
    func testSplit() {
        let pages = MemoryPages(internalPages: 300, purgeable: 50, external: 100, wired: 80, compressor: 40)
        let s = MemoryMath.split(total: 1000 * 16, pages: pages, pageSize: 16)
        XCTAssertEqual(s.app, 250 * 16)
        XCTAssertEqual(s.wired, 80 * 16)
        XCTAssertEqual(s.compressed, 40 * 16)
        XCTAssertEqual(s.cached, 150 * 16)
        XCTAssertEqual(s.free, 480 * 16)
    }

    func testPartsNeverExceedTotal() {
        let pages = MemoryPages(internalPages: 900, purgeable: 0, external: 500, wired: 400, compressor: 300)
        let s = MemoryMath.split(total: 1000 * 16, pages: pages, pageSize: 16)
        XCTAssertEqual(s.app + s.wired + s.compressed + s.cached + s.free, 1000 * 16)
        XCTAssertEqual(s.free, 0)
    }

    func testPurgeableLargerThanInternal() {
        let pages = MemoryPages(internalPages: 10, purgeable: 20, external: 0, wired: 0, compressor: 0)
        XCTAssertEqual(MemoryMath.split(total: 1000, pages: pages, pageSize: 1).app, 0)
    }

    func testPressure() {
        XCTAssertEqual(MemoryMath.pressure(level: 1), .normal)
        XCTAssertEqual(MemoryMath.pressure(level: 2), .warning)
        XCTAssertEqual(MemoryMath.pressure(level: 4), .critical)
        XCTAssertEqual(MemoryMath.pressure(level: nil), .normal)
    }
}
