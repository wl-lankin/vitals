import XCTest
@testable import VitalsCore

final class HistoryTests: XCTestCase {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func sample(_ offset: TimeInterval, cpu: Double = 0, app: String? = nil) -> Sample {
        var s = Sample.empty(cores: 2, at: base.addingTimeInterval(offset))
        s.cpu.total = cpu
        s.cpu.cores = [cpu, cpu]
        if let app {
            s.processes.topCPU = [AppUsage(id: app, name: app, bundlePath: nil, pid: 1, cpu: cpu, memory: 0, processCount: 1)]
        }
        return s
    }

    func testRetentionDropsOldSamples() {
        var history = History(retention: 10)
        for i in 0..<20 { history.append(sample(Double(i) * 2)) }
        XCTAssertEqual(history.samples.first?.time, base.addingTimeInterval(28))
        XCTAssertEqual(history.samples.count, 6)
    }

    func testClockJumpingBackStartsOver() {
        var history = History()
        history.append(sample(100))
        history.append(sample(102))
        history.append(sample(50))
        XCTAssertEqual(history.samples.count, 1)
    }

    func testShortSpanKeepsRawSamples() {
        var history = History()
        for i in 0..<400 { history.append(sample(Double(i) * 2)) }
        let window = history.window(span: 600, maxPoints: 300, interval: 2)
        XCTAssertEqual(window.count, 301)
        XCTAssertEqual(window.last?.time, history.latest?.time)
    }

    func testLongSpanFoldsIntoBuckets() {
        var history = History()
        for i in 0..<1800 { history.append(sample(Double(i) * 2, cpu: i % 6 == 0 ? 0.6 : 0)) }
        let window = history.window(span: 3600, maxPoints: 300, interval: 2)
        XCTAssertLessThanOrEqual(window.count, 301)
        XCTAssertGreaterThanOrEqual(window.count, 299)
        // Every full bucket holds six samples, one of them at 0.6.
        XCTAssertEqual(window[150].cpu.total, 0.1, accuracy: 0.0001)
    }

    func testMergeKeepsTheBusiestAppList() {
        let merged = Sample.merged([sample(0, cpu: 0.2, app: "calm"), sample(2, cpu: 0.9, app: "busy"),
                                    sample(4, cpu: 0.1, app: "idle")][...])
        XCTAssertEqual(merged.processes.topCPU.first?.name, "busy")
        XCTAssertEqual(merged.cpu.total, 0.4, accuracy: 0.0001)
        XCTAssertEqual(merged.time, base.addingTimeInterval(4))
    }

    func testNearest() {
        let samples = [sample(0), sample(2), sample(4), sample(6)]
        XCTAssertEqual(History.nearest(in: samples, to: base.addingTimeInterval(2.9))?.time, base.addingTimeInterval(2))
        XCTAssertEqual(History.nearest(in: samples, to: base.addingTimeInterval(3.1))?.time, base.addingTimeInterval(4))
        XCTAssertEqual(History.nearest(in: samples, to: base.addingTimeInterval(-50))?.time, base)
        XCTAssertEqual(History.nearest(in: samples, to: base.addingTimeInterval(99))?.time, base.addingTimeInterval(6))
        XCTAssertNil(History.nearest(in: [], to: base))
    }
}
