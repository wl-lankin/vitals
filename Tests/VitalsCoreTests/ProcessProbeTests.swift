import XCTest
@testable import VitalsCore

final class ProcessProbeTests: XCTestCase {
    func testCPUTimeFormats() {
        XCTAssertEqual(ProcessProbe.parseCPUTime("0:00.01")!, 0.01, accuracy: 1e-9)
        XCTAssertEqual(ProcessProbe.parseCPUTime("186:37.62")!, 186 * 60 + 37.62, accuracy: 1e-9)
        XCTAssertEqual(ProcessProbe.parseCPUTime("1:02:03.50")!, 3723.5, accuracy: 1e-9)
        XCTAssertEqual(ProcessProbe.parseCPUTime("2-03:04:05")!, 183845.0, accuracy: 1e-9)
        XCTAssertNil(ProcessProbe.parseCPUTime("abc"))
        XCTAssertNil(ProcessProbe.parseCPUTime("12"))
        XCTAssertNil(ProcessProbe.parseCPUTime(""))
    }

    func testParseLineWithSpacesInPath() {
        let e = ProcessProbe.parseLine("  123     1  12:34.56  2048 /Applications/Some App.app/Contents/MacOS/Some App")
        XCTAssertEqual(e?.pid, 123)
        XCTAssertEqual(e?.ppid, 1)
        XCTAssertEqual(e?.rssBytes, 2048 * 1024)
        XCTAssertEqual(e?.path, "/Applications/Some App.app/Contents/MacOS/Some App")
        XCTAssertEqual(e!.cpuSeconds, 12 * 60 + 34.56, accuracy: 1e-9)
    }

    func testParseLineRejectsGarbage() {
        XCTAssertNil(ProcessProbe.parseLine(""))
        XCTAssertNil(ProcessProbe.parseLine("1 2 3"))
        XCTAssertNil(ProcessProbe.parseLine("x 1 0:00.00 10 /bin/ls"))
        XCTAssertNil(ProcessProbe.parseLine("1 1 0:00.00 10"))
    }

    func testOutermostBundle() {
        let helper = "/Applications/Vivaldi.app/Contents/Frameworks/V.framework/Versions/1/Helpers/Vivaldi Helper (Renderer).app/Contents/MacOS/Vivaldi Helper (Renderer)"
        XCTAssertEqual(ProcessProbe.outermostBundle(in: helper), "/Applications/Vivaldi.app")
        XCTAssertEqual(ProcessProbe.outermostBundle(in: "/Applications/Ünï Çode.app/Contents/MacOS/x"),
                       "/Applications/Ünï Çode.app")
        XCTAssertNil(ProcessProbe.outermostBundle(in: "/usr/bin/true"))
        XCTAssertNil(ProcessProbe.outermostBundle(in: "/opt/my.application/bin/x"))
    }

    func testClassify() {
        XCTAssertEqual(ProcessProbe.classify(path: "/Applications/A.app/Contents/MacOS/A"), .bundle("/Applications/A.app"))
        XCTAssertEqual(ProcessProbe.classify(path: "/usr/local/bin/claude"), .executable("claude"))
        XCTAssertEqual(ProcessProbe.classify(path: "kernel_task"), .executable("kernel_task"))
        XCTAssertEqual(ProcessProbe.classify(path: "/System/Library/Frameworks/WebKit.framework/X.xpc/Contents/MacOS/X"),
                       .needsResponsible)
        XCTAssertEqual(ProcessProbe.classify(path: "/System/Library/PrivateFrameworks/P.framework/p"), .needsResponsible)
        XCTAssertEqual(ProcessProbe.classify(path: "/usr/libexec/thing.xpc"), .executable("thing.xpc"))
    }

    func testAggregate() {
        let vivaldi = "/Applications/Vivaldi.app"
        let records = [
            ProcessRecord(pid: 50, path: vivaldi + "/Contents/Frameworks/H.app/Contents/MacOS/H", cpu: 0.5, memory: 100),
            ProcessRecord(pid: 40, path: vivaldi + "/Contents/MacOS/Vivaldi", cpu: 0.25, memory: 300),
            ProcessRecord(pid: 30, path: vivaldi + "/Contents/MacOS/Vivaldi", cpu: 0.0, memory: 1),
            ProcessRecord(pid: 60, path: "/System/Library/Frameworks/WebKit.framework/W.xpc/Contents/MacOS/W", cpu: 0.1, memory: 50),
            ProcessRecord(pid: 61, path: "/System/Library/Frameworks/WebKit.framework/W.xpc/Contents/MacOS/W", cpu: 0.1, memory: 20),
            ProcessRecord(pid: 70, path: "/usr/bin/yes", cpu: 1.0, memory: 10),
            ProcessRecord(pid: 71, path: "/usr/bin/yes", cpu: 0.001, memory: 10),
            ProcessRecord(pid: 80, path: "/bin/idle", cpu: 0.001, memory: 5),
        ]
        let sample = ProcessProbe.aggregate(records, responsiblePID: { $0 == 60 ? 40 : nil },
                                            displayName: { _ in "Vivaldi" })
        XCTAssertEqual(sample.processCount, 8)
        XCTAssertEqual(sample.topCPU.map(\.id), ["yes", vivaldi, "W"])
        let v = sample.topCPU[1]
        XCTAssertEqual(v.name, "Vivaldi")
        XCTAssertEqual(v.bundlePath, vivaldi)
        XCTAssertEqual(v.processCount, 4)
        XCTAssertEqual(v.pid, 30)
        XCTAssertEqual(v.cpu, 0.85, accuracy: 1e-9)
        XCTAssertEqual(v.memory, 451)
        XCTAssertEqual(sample.topCPU[0].cpu, 1.001, accuracy: 1e-9)
        XCTAssertNil(sample.topCPU[0].bundlePath)
        XCTAssertEqual(sample.topCPU[2].processCount, 1)
        XCTAssertEqual(sample.topMemory.first?.id, vivaldi)
    }

    func testAggregateLimitsToFive() {
        let records = (1...10).map { ProcessRecord(pid: Int32($0), path: "/bin/p\($0)", cpu: Double($0), memory: UInt64($0)) }
        let sample = ProcessProbe.aggregate(records, responsiblePID: { _ in nil }, displayName: { $0 })
        XCTAssertEqual(sample.topCPU.count, 5)
        XCTAssertEqual(sample.topCPU.first?.id, "p10")
        XCTAssertEqual(sample.topMemory.count, 5)
    }

    func testLiveReadDoesNotCrash() {
        let probe = ProcessProbe()
        let first = probe.read()
        XCTAssertGreaterThan(first.processCount, 10)
        XCTAssertTrue(first.topCPU.isEmpty)
        let second = probe.read()
        XCTAssertGreaterThan(second.processCount, 10)
        XCTAssertLessThanOrEqual(second.topMemory.count, 5)
    }

    func testNamesOfServicesAndRetitledProcesses() {
        XCTAssertEqual(ProcessProbe.readableName("com.apple.SafariPlatformSupport.Helper"), "SafariPlatformSupport.Helper")
        XCTAssertEqual(ProcessProbe.readableName("kernel_task"), "kernel_task")
        XCTAssertEqual(ProcessProbe.readableName("node.js"), "node.js")
        XCTAssertEqual(ProcessProbe.lastComponent("npm exec some-tool@1.2.3 mcp"), "npm")
        XCTAssertEqual(ProcessProbe.lastComponent("/usr/libexec/My Tool"), "My Tool")
    }
}
