import XCTest
@testable import VitalsCore

final class FormatTests: XCTestCase {
    func testMemoryUsesBinarySteps() {
        XCTAssertEqual(Fmt.memory(24 * 1_073_741_824, trim: true).text, "24 GB")
        XCTAssertEqual(Fmt.memory(UInt64(14.2 * 1_073_741_824)).text, "14,2 GB")
        XCTAssertEqual(Fmt.memory(512 * 1_048_576).text, "512 MB")
    }

    func testStorageUsesDecimalSteps() {
        XCTAssertEqual(Fmt.storage(432_900_000_000).text, "433 GB")
        XCTAssertEqual(Fmt.storage(58_300_000_000).text, "58,3 GB")
        XCTAssertEqual(Fmt.storage(2_000_398_934_016).text, "2 TB")
        XCTAssertEqual(Fmt.storage(994_610_155_520).text, "995 GB")
    }

    func testRateStepsUpInsteadOfShowingFourDigits() {
        XCTAssertEqual(Fmt.rate(0).text, "0 KB/s")
        XCTAssertEqual(Fmt.rate(84_000).text, "84 KB/s")
        XCTAssertEqual(Fmt.rate(999_600).text, "1,0 MB/s")
        XCTAssertEqual(Fmt.rate(1_240_000).text, "1,2 MB/s")
        XCTAssertEqual(Fmt.rate(310_000_000).text, "310 MB/s")
    }

    func testDuration() {
        XCTAssertEqual(Fmt.duration(20), "unter 1 Min.")
        XCTAssertEqual(Fmt.duration(8 * 60), "8 Min.")
        XCTAssertEqual(Fmt.duration(15 * 3600 + 8 * 60), "15 Std. 8 Min.")
        XCTAssertEqual(Fmt.duration(2 * 3600), "2 Std.")
        XCTAssertEqual(Fmt.duration(30 * 86400 + 10 * 3600 + 120), "30 T. 10 Std.")
    }

    func testAgo() {
        XCTAssertEqual(Fmt.ago(0.4), "jetzt")
        XCTAssertEqual(Fmt.ago(45), "vor 45 Sek.")
        XCTAssertEqual(Fmt.ago(200), "vor 3 Min. 20 Sek.")
        XCTAssertEqual(Fmt.ago(1800), "vor 30 Min.")
    }

    func testPercentAndWatts() {
        XCTAssertEqual(Fmt.percent(0.116), "12")
        XCTAssertEqual(Fmt.percent(3.68), "368")
        XCTAssertEqual(Fmt.watts(3.692).text, "3,7 W")
        XCTAssertEqual(Fmt.watts(140).text, "140 W")
    }
}
