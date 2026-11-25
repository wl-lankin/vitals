import Foundation

// Value types shared by the probes (which fill them) and the UI (which draws them).
// Fractions are 0...1, sizes are bytes, rates are bytes per second, temperatures are °C.

// MARK: Processor

public enum CoreKind: String, Sendable, Codable {
    case performance, efficiency, unknown
}

public struct CPUTopology: Equatable, Sendable, Codable {
    /// Marketing name of the chip, e.g. "Apple M5".
    public var chip: String
    /// One entry per logical core, index-aligned with `CPUSample.cores`.
    public var kinds: [CoreKind]

    public init(chip: String, kinds: [CoreKind]) {
        self.chip = chip
        self.kinds = kinds
    }

    public var performanceCores: Int { kinds.filter { $0 == .performance }.count }
    public var efficiencyCores: Int { kinds.filter { $0 == .efficiency }.count }
}

public struct CPUSample: Equatable, Sendable, Codable {
    /// Busy share of all cores together.
    public var total: Double
    public var user: Double
    public var system: Double
    /// Busy share per logical core.
    public var cores: [Double]
    /// One-minute load average.
    public var loadAverage: Double

    public init(total: Double, user: Double, system: Double, cores: [Double], loadAverage: Double) {
        self.total = total
        self.user = user
        self.system = system
        self.cores = cores
        self.loadAverage = loadAverage
    }

    public static let zero = CPUSample(total: 0, user: 0, system: 0, cores: [], loadAverage: 0)
}

// MARK: Memory

public enum MemoryPressure: Int, Sendable, Codable, Comparable {
    case normal, warning, critical

    public static func < (a: MemoryPressure, b: MemoryPressure) -> Bool { a.rawValue < b.rawValue }
}

/// Split the way Activity Monitor shows it: used = app + wired + compressed.
public struct MemorySample: Equatable, Sendable, Codable {
    public var total: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    /// File cache plus purgeable memory; the system hands it back on demand.
    public var cached: UInt64
    public var free: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64
    public var pressure: MemoryPressure

    public init(total: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64, free: UInt64,
                swapUsed: UInt64, swapTotal: UInt64, pressure: MemoryPressure) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.free = free
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.pressure = pressure
    }

    public var used: UInt64 { app + wired + compressed }
    public var usedFraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }

    public static let zero = MemorySample(total: 0, app: 0, wired: 0, compressed: 0, cached: 0, free: 0,
                                          swapUsed: 0, swapTotal: 0, pressure: .normal)
}

// MARK: Disks

public enum VolumeKind: String, Sendable, Codable {
    case internalDisk, external, network, image
}

public struct Volume: Identifiable, Equatable, Sendable, Codable {
    /// Mount path, e.g. "/" or "/Volumes/T7".
    public var id: String
    public var name: String
    public var total: UInt64
    /// Space the user can actually fill, including what the system would purge for it.
    public var free: UInt64
    public var kind: VolumeKind
    public var isEjectable: Bool

    public init(id: String, name: String, total: UInt64, free: UInt64, kind: VolumeKind, isEjectable: Bool) {
        self.id = id
        self.name = name
        self.total = total
        self.free = free
        self.kind = kind
        self.isEjectable = isEjectable
    }

    public var usedFraction: Double { total == 0 ? 0 : min(1, 1 - Double(free) / Double(total)) }
}

public struct DiskSample: Equatable, Sendable, Codable {
    /// Volumes a user would recognise: the startup disk first, then the rest by name.
    public var volumes: [Volume]
    /// Throughput of all physical disks together.
    public var readRate: Double
    public var writeRate: Double

    public init(volumes: [Volume], readRate: Double, writeRate: Double) {
        self.volumes = volumes
        self.readRate = readRate
        self.writeRate = writeRate
    }

    public static let zero = DiskSample(volumes: [], readRate: 0, writeRate: 0)
}

// MARK: Network

public enum LinkKind: String, Sendable, Codable {
    case wifi, ethernet, cellular, vpn, other
}

public struct NetworkLink: Equatable, Sendable, Codable {
    /// BSD name, e.g. "en0".
    public var name: String
    public var kind: LinkKind
    public var ipv4: String?
    public var router: String?

    public init(name: String, kind: LinkKind, ipv4: String?, router: String?) {
        self.name = name
        self.kind = kind
        self.ipv4 = ipv4
        self.router = router
    }
}

public struct NetworkSample: Equatable, Sendable, Codable {
    public var downRate: Double
    public var upRate: Double
    /// Bytes since boot over the physical interfaces.
    public var totalDown: UInt64
    public var totalUp: UInt64
    /// The interface that carries the default route, nil when offline.
    public var link: NetworkLink?

    public init(downRate: Double, upRate: Double, totalDown: UInt64, totalUp: UInt64, link: NetworkLink?) {
        self.downRate = downRate
        self.upRate = upRate
        self.totalDown = totalDown
        self.totalUp = totalUp
        self.link = link
    }

    public static let zero = NetworkSample(downRate: 0, upRate: 0, totalDown: 0, totalUp: 0, link: nil)
}

// MARK: Power

public enum PowerState: String, Sendable, Codable {
    /// Running from the battery.
    case battery
    /// Plugged in and charging.
    case charging
    /// Plugged in, not charging (full or held by the system).
    case pluggedIn
}

public struct BatterySample: Equatable, Sendable, Codable {
    /// 0...100 as the system shows it.
    public var percent: Int
    public var state: PowerState
    /// Seconds until empty (on battery) or full (charging); nil while the system is still estimating.
    public var timeRemaining: TimeInterval?
    /// Current full capacity relative to design capacity.
    public var health: Double?
    public var cycles: Int?
    public var temperature: Double?
    /// Rated power of the connected adapter in watts.
    public var adapterWatts: Int?
    public var lowPowerMode: Bool

    public init(percent: Int, state: PowerState, timeRemaining: TimeInterval?, health: Double?, cycles: Int?,
                temperature: Double?, adapterWatts: Int?, lowPowerMode: Bool) {
        self.percent = percent
        self.state = state
        self.timeRemaining = timeRemaining
        self.health = health
        self.cycles = cycles
        self.temperature = temperature
        self.adapterWatts = adapterWatts
        self.lowPowerMode = lowPowerMode
    }
}

public struct PowerSample: Equatable, Sendable, Codable {
    /// nil on Macs without a battery.
    public var battery: BatterySample?
    /// What the whole machine draws right now, in watts; nil where the hardware does not report it.
    public var systemWatts: Double?

    public init(battery: BatterySample?, systemWatts: Double?) {
        self.battery = battery
        self.systemWatts = systemWatts
    }

    public static let zero = PowerSample(battery: nil, systemWatts: nil)
}

// MARK: Sensors

public enum ThermalLevel: Int, Sendable, Codable, Comparable {
    case nominal, fair, serious, critical

    public static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }
}

public struct SensorSample: Equatable, Sendable, Codable {
    /// Hottest CPU die sensor; nil where no sensor can be read.
    public var cpuTemperature: Double?
    public var gpuUsage: Double?
    public var thermal: ThermalLevel

    public init(cpuTemperature: Double?, gpuUsage: Double?, thermal: ThermalLevel) {
        self.cpuTemperature = cpuTemperature
        self.gpuUsage = gpuUsage
        self.thermal = thermal
    }

    public static let zero = SensorSample(cpuTemperature: nil, gpuUsage: nil, thermal: .nominal)
}

// MARK: Processes

/// One app with all of its helper processes folded in.
public struct AppUsage: Identifiable, Equatable, Sendable, Codable {
    /// Bundle path for apps, executable name for everything else.
    public var id: String
    public var name: String
    /// Path of the .app bundle, nil for plain executables and daemons.
    public var bundlePath: String?
    /// The app's main process.
    public var pid: Int32
    /// 1.0 is one fully used core, so an app can exceed 1.
    public var cpu: Double
    public var memory: UInt64
    public var processCount: Int

    public init(id: String, name: String, bundlePath: String?, pid: Int32, cpu: Double, memory: UInt64,
                processCount: Int) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
        self.pid = pid
        self.cpu = cpu
        self.memory = memory
        self.processCount = processCount
    }
}

public struct ProcessSample: Equatable, Sendable, Codable {
    /// Highest first, at most five each.
    public var topCPU: [AppUsage]
    public var topMemory: [AppUsage]
    public var processCount: Int

    public init(topCPU: [AppUsage], topMemory: [AppUsage], processCount: Int) {
        self.topCPU = topCPU
        self.topMemory = topMemory
        self.processCount = processCount
    }

    public static let zero = ProcessSample(topCPU: [], topMemory: [], processCount: 0)
}

// MARK: Everything at one moment

public struct Sample: Equatable, Sendable, Codable {
    public var time: Date
    public var cpu: CPUSample
    public var memory: MemorySample
    public var disk: DiskSample
    public var network: NetworkSample
    public var power: PowerSample
    public var sensors: SensorSample
    public var processes: ProcessSample

    public init(time: Date, cpu: CPUSample, memory: MemorySample, disk: DiskSample, network: NetworkSample,
                power: PowerSample, sensors: SensorSample, processes: ProcessSample) {
        self.time = time
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.power = power
        self.sensors = sensors
        self.processes = processes
    }

    /// What the window shows before the first reading has arrived.
    public static func empty(cores: Int, at time: Date = Date()) -> Sample {
        var cpu = CPUSample.zero
        cpu.cores = Array(repeating: 0, count: cores)
        return Sample(time: time, cpu: cpu, memory: .zero, disk: .zero, network: .zero, power: .zero,
                      sensors: .zero, processes: .zero)
    }
}
