import XCTest
@testable import VitalsCore

final class VerdictTests: XCTestCase {
    private func sample() -> Sample {
        var s = Sample.empty(cores: 10)
        s.memory = MemorySample(total: 24 << 30, app: 8 << 30, wired: 3 << 30, compressed: 1 << 30, cached: 6 << 30,
                                free: 6 << 30, swapUsed: 0, swapTotal: 0, pressure: .normal)
        s.disk.volumes = [Volume(id: "/", name: "Macintosh HD", total: 994_000_000_000, free: 400_000_000_000,
                                 kind: .internalDisk, isEjectable: false)]
        return s
    }

    private func app(_ name: String, cpu: Double = 0, memory: UInt64 = 0) -> AppUsage {
        AppUsage(id: name, name: name, bundlePath: nil, pid: 1, cpu: cpu, memory: memory, processCount: 1)
    }

    func testCalm() {
        XCTAssertEqual(Verdict.assess(sample()).level, .calm)
    }

    func testLoadNamesTheApp() {
        var s = sample()
        s.cpu.total = 0.7
        s.processes.topCPU = [app("Xcode", cpu: 4.2)]
        let verdict = Verdict.assess(s)
        XCTAssertEqual(verdict.title, "Unter Last")
        XCTAssertEqual(verdict.detail, "Xcode lastet 4 Kerne aus")
    }

    func testSmoothedLoadWinsOverTheSingleReading() {
        var s = sample()
        s.cpu.total = 0.9
        XCTAssertEqual(Verdict.assess(s, load: 0.1).level, .calm)
    }

    func testMemoryPressureOutranksLoad() {
        var s = sample()
        s.cpu.total = 0.9
        s.memory.pressure = .warning
        s.processes.topMemory = [app("Vivaldi", memory: 14 << 30)]
        let verdict = Verdict.assess(s)
        XCTAssertEqual(verdict.title, "Speicher wird knapp")
        XCTAssertEqual(verdict.detail, "Vivaldi belegt 14,0 GB")
    }

    func testLowBatteryOnlyCountsOnBattery() {
        var s = sample()
        s.power.battery = BatterySample(percent: 8, state: .charging, timeRemaining: nil, health: nil, cycles: nil,
                                        temperature: nil, adapterWatts: 70, lowPowerMode: false)
        XCTAssertEqual(Verdict.assess(s).level, .calm)
        s.power.battery?.state = .battery
        XCTAssertEqual(Verdict.assess(s).title, "Akku fast leer")
    }

    func testFullStartupDisk() {
        var s = sample()
        s.disk.volumes[0].free = 6_000_000_000
        XCTAssertEqual(Verdict.assess(s).title, "Startvolume fast voll")
    }

    func testHeatOutranksEverything() {
        var s = sample()
        s.memory.pressure = .critical
        s.sensors.thermal = .serious
        XCTAssertEqual(Verdict.assess(s).title, "Heiß gelaufen")
    }
}
