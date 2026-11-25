import Foundation

struct MemoryPages {
    var internalPages: UInt64
    var purgeable: UInt64
    var external: UInt64
    var wired: UInt64
    var compressor: UInt64
}

enum MemoryMath {
    static func split(total: UInt64, pages: MemoryPages, pageSize: UInt64)
        -> (app: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64, free: UInt64) {
        let appPages = pages.internalPages > pages.purgeable ? pages.internalPages - pages.purgeable : 0
        // Clamp each part in order so the five parts never exceed the total.
        var remaining = total
        func take(_ pageCount: UInt64) -> UInt64 {
            let bytes = min(remaining, pageCount.multipliedReportingOverflow(by: pageSize).partialValue)
            remaining -= bytes
            return bytes
        }
        let app = take(appPages)
        let wired = take(pages.wired)
        let compressed = take(pages.compressor)
        let cached = take(pages.external &+ pages.purgeable)
        return (app, wired, compressed, cached, remaining)
    }

    static func pressure(level: Int?) -> MemoryPressure {
        switch level {
        case 2: return .warning
        case 4: return .critical
        default: return .normal
        }
    }
}

public final class MemoryProbe {
    private let total: UInt64
    private let pageSize: UInt64
    private let host = mach_host_self()

    public init() {
        var size: Int64 = 0
        var length = MemoryLayout<Int64>.size
        total = sysctlbyname("hw.memsize", &size, &length, nil, 0) == 0 ? UInt64(max(0, size)) : 0
        var page: vm_size_t = 0
        pageSize = host_page_size(host, &page) == KERN_SUCCESS && page > 0 ? UInt64(page) : 16384
    }

    public func read() -> MemorySample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var sample = MemorySample.zero
        sample.total = total
        if result == KERN_SUCCESS {
            let pages = MemoryPages(internalPages: UInt64(stats.internal_page_count),
                                    purgeable: UInt64(stats.purgeable_count),
                                    external: UInt64(stats.external_page_count),
                                    wired: UInt64(stats.wire_count),
                                    compressor: UInt64(stats.compressor_page_count))
            let split = MemoryMath.split(total: total, pages: pages, pageSize: pageSize)
            sample.app = split.app
            sample.wired = split.wired
            sample.compressed = split.compressed
            sample.cached = split.cached
            sample.free = split.free
        } else {
            sample.free = total
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            sample.swapUsed = swap.xsu_used
            sample.swapTotal = swap.xsu_total
        }
        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        let hasLevel = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0
        sample.pressure = MemoryMath.pressure(level: hasLevel ? Int(level) : nil)
        return sample
    }
}
