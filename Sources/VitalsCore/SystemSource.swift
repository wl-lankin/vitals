import Foundation

/// The real machine.
public final class SystemSource: VitalsSource {
    private let cpu = CPUProbe()
    private let memory = MemoryProbe()
    private let disk = DiskProbe()
    private let network = NetworkProbe()
    private let power = PowerProbe()
    private let sensors = SensorProbe()
    private let process = ProcessProbe()

    public init() {}

    public var topology: CPUTopology { cpu.topology }

    public func read(at time: Date, processes: ProcessSample) -> Sample {
        Sample(time: time, cpu: cpu.read(), memory: memory.read(), disk: disk.read(), network: network.read(),
               power: power.read(), sensors: sensors.read(), processes: processes)
    }

    public func readProcesses() -> ProcessSample {
        process.read()
    }

    public func invalidateVolumes() {
        disk.refreshVolumes()
    }
}
