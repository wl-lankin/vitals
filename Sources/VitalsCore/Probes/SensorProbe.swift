import Foundation
import IOKit

public final class SensorProbe {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatchingFn = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias FloatValueFn = @convention(c) (CFTypeRef, Int32) -> Double

    private struct HID {
        let copyProperty: CopyPropertyFn
        let copyEvent: CopyEventFn
        let floatValue: FloatValueFn
        let client: CFTypeRef
        var services: [CFTypeRef]
    }

    private static let temperatureEventType: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16
    private static let refreshInterval: UInt64 = 4_000_000_000

    private var hid: HID?
    private var hidSetUp = false
    private var cpuServices: [CFTypeRef] = []
    private var cachedTemperature: Double?
    private var lastRefresh: UInt64 = 0

    public init() {}

    public func read() -> SensorSample {
        SensorSample(cpuTemperature: cpuTemperature(), gpuUsage: gpuUsage(), thermal: thermalLevel())
    }

    /// Every HID temperature sensor with its current value, for diagnostics.
    public func allTemperatureSensors() -> [(name: String, value: Double?)] {
        setUpHID()
        guard let hid else { return [] }
        return hid.services.map { (sensorName($0, hid) ?? "?", temperature(of: $0, hid)) }
    }

    private func thermalLevel() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    // MARK: GPU

    private func gpuUsage() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
                == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(
                service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                let percent = (stats["Device Utilization %"] as? NSNumber)?.doubleValue else { continue }
            let fraction = min(1, max(0, percent / 100))
            best = max(best ?? 0, fraction)
        }
        return best
    }

    // MARK: CPU temperature

    private func cpuTemperature() -> Double? {
        let now = DispatchTime.now().uptimeNanoseconds
        if hidSetUp, now &- lastRefresh < Self.refreshInterval { return cachedTemperature }
        lastRefresh = now
        setUpHID()
        guard let hid else { return nil }
        let values = cpuServices.compactMap { temperature(of: $0, hid) }
        cachedTemperature = values.max()
        return cachedTemperature
    }

    private func setUpHID() {
        guard !hidSetUp else { return }
        hidSetUp = true
        guard let handle = dlopen(nil, RTLD_NOW),
              let create = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let setMatching = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let copyServices = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let copyProperty = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let copyEvent = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let floatValue = dlsym(handle, "IOHIDEventGetFloatValue") else { return }

        let createFn = unsafeBitCast(create, to: CreateFn.self)
        let setMatchingFn = unsafeBitCast(setMatching, to: SetMatchingFn.self)
        let copyServicesFn = unsafeBitCast(copyServices, to: CopyServicesFn.self)

        guard let client = createFn(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        let matching: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
        _ = setMatchingFn(client, matching as CFDictionary)
        guard let array = copyServicesFn(client)?.takeRetainedValue() else { return }

        let count = CFArrayGetCount(array)
        var services: [CFTypeRef] = []
        for i in 0..<count {
            if let ptr = CFArrayGetValueAtIndex(array, i) {
                services.append(Unmanaged<CFTypeRef>.fromOpaque(ptr).takeUnretainedValue())
            }
        }
        let built = HID(copyProperty: unsafeBitCast(copyProperty, to: CopyPropertyFn.self),
                        copyEvent: unsafeBitCast(copyEvent, to: CopyEventFn.self),
                        floatValue: unsafeBitCast(floatValue, to: FloatValueFn.self),
                        client: client, services: services)
        hid = built
        cpuServices = services.filter { service in
            guard let name = sensorName(service, built) else { return false }
            return Self.isCPUSensor(name)
        }
    }

    static func isCPUSensor(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("tdie") || lower.contains("acc mtr temp") || lower.contains("pacc mtr temp")
            || lower.contains("eacc mtr temp") || lower.contains("cpu")
    }

    private func sensorName(_ service: CFTypeRef, _ hid: HID) -> String? {
        hid.copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String
    }

    private func temperature(of service: CFTypeRef, _ hid: HID) -> Double? {
        guard let event = hid.copyEvent(service, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else {
            return nil
        }
        let value = hid.floatValue(event, Self.temperatureField)
        guard value.isFinite, value > 0, value <= 130 else { return nil }
        return value
    }
}
