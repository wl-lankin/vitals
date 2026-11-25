import Foundation
import IOKit
import IOKit.ps

public final class PowerProbe {
    private struct Details {
        var health: Double?
        var cycles: Int?
        var temperature: Double?
        var adapterWatts: Int?
        var systemLoadWatts: Double?
        var voltage: Double?
        var amperage: Int64?
    }

    // Registry reads are cheap here, but health/cycles change slowly, so the slow part is cached.
    private var cachedSlow: (health: Double?, cycles: Int?, at: UInt64)?
    private let slowInterval: UInt64 = 30_000_000_000

    public init() {}

    public func read() -> PowerSample {
        let details = readRegistry()
        guard let ps = readPowerSource() else {
            return PowerSample(battery: nil, systemWatts: systemWatts(details, onBattery: false))
        }

        let now = DispatchTime.now().uptimeNanoseconds
        if cachedSlow == nil || now &- cachedSlow!.at > slowInterval {
            cachedSlow = (details.health, details.cycles, now)
        }
        let slow = cachedSlow

        let state: PowerState = ps.external ? (ps.charging ? .charging : .pluggedIn) : .battery
        let battery = BatterySample(
            percent: ps.percent,
            state: state,
            timeRemaining: ps.timeRemaining,
            health: slow?.health,
            cycles: slow?.cycles,
            temperature: details.temperature,
            adapterWatts: ps.external ? details.adapterWatts : nil,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        return PowerSample(battery: battery, systemWatts: systemWatts(details, onBattery: state == .battery))
    }

    private func systemWatts(_ d: Details, onBattery: Bool) -> Double? {
        if let load = d.systemLoadWatts, load > 0 { return load }
        if onBattery, let v = d.voltage, let a = d.amperage, v > 0, a != 0 {
            return v / 1000 * Double(a.magnitude) / 1000
        }
        return nil
    }

    // MARK: IOPS

    private struct PowerSource {
        var percent: Int
        var external: Bool
        var charging: Bool
        var timeRemaining: TimeInterval?
    }

    private func readPowerSource() -> PowerSource? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            if let present = desc[kIOPSIsPresentKey] as? Bool, !present { continue }

            let current = (desc[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let maxCap = (desc[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
            let percent = maxCap > 0 ? Int((current / maxCap * 100).rounded()) : 0
            let external = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false

            let key = external ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            var remaining: TimeInterval?
            if let minutes = (desc[key] as? NSNumber)?.intValue, minutes > 0 {
                remaining = TimeInterval(minutes) * 60
            }
            if external && !charging { remaining = nil }
            return PowerSource(percent: min(100, max(0, percent)), external: external, charging: charging,
                               timeRemaining: remaining)
        }
        return nil
    }

    // MARK: IORegistry

    private func readRegistry() -> Details {
        var d = Details()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return d }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else { return d }

        let batteryData = props["BatteryData"] as? [String: Any]
        let design = number(props["DesignCapacity"]) ?? number(batteryData?["DesignCapacity"])
        let full = number(props["NominalChargeCapacity"]) ?? number(batteryData?["NominalChargeCapacity"])
            ?? number(props["AppleRawMaxCapacity"]) ?? number(batteryData?["FullChargeCapacity"])
        if let design, let full, design > 0, full > 0 {
            d.health = min(1, max(0, Double(full) / Double(design)))
        }
        d.cycles = number(props["CycleCount"]).map { Int($0) }
        if let t = number(props["Temperature"]), t > 0 { d.temperature = Double(t) / 100 }
        if let adapter = props["AdapterDetails"] as? [String: Any], let w = number(adapter["Watts"]), w > 0 {
            d.adapterWatts = Int(w)
        }
        if let telemetry = props["PowerTelemetryData"] as? [String: Any], let load = number(telemetry["SystemLoad"]) {
            d.systemLoadWatts = Double(load) / 1000
        }
        d.voltage = number(props["Voltage"]).map { Double($0) }
        d.amperage = number(props["Amperage"])
        return d
    }

    // The registry hands signed values over as unsigned 64-bit when negative; reinterpret the bits.
    private func number(_ value: Any?) -> Int64? {
        guard let n = value as? NSNumber else { return nil }
        if CFNumberGetType(n) == .sInt64Type || CFNumberGetType(n) == .longLongType || CFNumberGetType(n) == .sInt32Type {
            return n.int64Value
        }
        return Int64(bitPattern: n.uint64Value)
    }
}
