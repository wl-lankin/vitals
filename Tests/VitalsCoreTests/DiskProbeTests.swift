import XCTest
@testable import VitalsCore

final class DiskProbeTests: XCTestCase {
    private func facts(local: Bool = true, internalDisk: Bool = true, image: Bool = false, ejectable: Bool = false,
                       removable: Bool = false, startup: Bool = false) -> VolumeFacts {
        VolumeFacts(isLocal: local, isInternal: internalDisk, isImage: image, isEjectable: ejectable,
                    isRemovable: removable, isStartup: startup)
    }

    func testKind() {
        XCTAssertEqual(DiskMath.kind(facts()), .internalDisk)
        XCTAssertEqual(DiskMath.kind(facts(internalDisk: false)), .external)
        XCTAssertEqual(DiskMath.kind(facts(local: false, internalDisk: false)), .network)
        XCTAssertEqual(DiskMath.kind(facts(internalDisk: false, image: true)), .image)
    }

    func testEjectable() {
        XCTAssertFalse(DiskMath.isEjectable(facts(ejectable: true, startup: true)))
        XCTAssertTrue(DiskMath.isEjectable(facts(ejectable: true)))
        XCTAssertTrue(DiskMath.isEjectable(facts(removable: true)))
        XCTAssertTrue(DiskMath.isEjectable(facts(local: false)))
        XCTAssertTrue(DiskMath.isEjectable(facts(image: true)))
        XCTAssertFalse(DiskMath.isEjectable(facts()))
    }

    func testFreeFallback() {
        XCTAssertEqual(DiskMath.free(important: 500, plain: 100), 500)
        XCTAssertEqual(DiskMath.free(important: 0, plain: 100), 100)
        XCTAssertEqual(DiskMath.free(important: nil, plain: 100), 100)
        XCTAssertEqual(DiskMath.free(important: nil, plain: nil), 0)
    }

    func testOrder() {
        func v(_ name: String) -> Volume {
            Volume(id: "/" + name, name: name, total: 1, free: 1, kind: .external, isEjectable: true)
        }
        let ordered = DiskMath.order([(v("b"), false), (v("Macintosh HD"), true), (v("A"), false)])
        XCTAssertEqual(ordered.map(\.name), ["Macintosh HD", "A", "b"])
    }
}
