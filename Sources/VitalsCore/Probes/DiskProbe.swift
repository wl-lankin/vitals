import Foundation
import DiskArbitration
import IOKit

struct VolumeFacts {
    var isLocal: Bool
    var isInternal: Bool
    var isImage: Bool
    var isEjectable: Bool
    var isRemovable: Bool
    var isStartup: Bool
}

enum DiskMath {
    static func kind(_ f: VolumeFacts) -> VolumeKind {
        if !f.isLocal { return .network }
        if f.isImage { return .image }
        if !f.isInternal { return .external }
        return .internalDisk
    }

    static func isEjectable(_ f: VolumeFacts) -> Bool {
        if f.isStartup { return false }
        return f.isEjectable || f.isRemovable || !f.isLocal || f.isImage
    }

    static func free(important: Int64?, plain: Int64?) -> UInt64 {
        if let important, important > 0 { return UInt64(important) }
        if let plain, plain > 0 { return UInt64(plain) }
        return 0
    }

    /// Startup volume first, then the rest by localized name.
    static func order(_ volumes: [(volume: Volume, isStartup: Bool)]) -> [Volume] {
        volumes.sorted { a, b in
            if a.isStartup != b.isStartup { return a.isStartup }
            let order = a.volume.name.localizedStandardCompare(b.volume.name)
            return order == .orderedSame ? a.volume.id < b.volume.id : order == .orderedAscending
        }.map(\.volume)
    }
}

public final class DiskProbe {
    private var volumes: [Volume] = []
    private var volumesFetchedAt: UInt64 = 0
    private var needsRefresh = true
    private var previousRead: UInt64 = 0
    private var previousWrite: UInt64 = 0
    private var previousTime: UInt64 = 0
    private var hasPrevious = false
    private let session = DASessionCreate(kCFAllocatorDefault)
    private static let refreshInterval: UInt64 = 10_000_000_000

    public init() {}

    public func refreshVolumes() {
        needsRefresh = true
    }

    public func read() -> DiskSample {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        if needsRefresh || now &- volumesFetchedAt >= Self.refreshInterval {
            volumes = fetchVolumes()
            volumesFetchedAt = now
            needsRefresh = false
        }
        let counters = Self.readCounters()
        var readRate = 0.0
        var writeRate = 0.0
        if hasPrevious {
            let seconds = Double(now &- previousTime) / 1e9
            readRate = NetworkMath.rate(previous: previousRead, current: counters.read, seconds: seconds)
            writeRate = NetworkMath.rate(previous: previousWrite, current: counters.write, seconds: seconds)
        }
        previousRead = counters.read
        previousWrite = counters.write
        previousTime = now
        hasPrevious = true
        return DiskSample(volumes: volumes, readRate: readRate, writeRate: writeRate)
    }

    private func fetchVolumes() -> [Volume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsLocalKey, .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
            .volumeIsRootFileSystemKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                               options: [.skipHiddenVolumes]) else { return [] }
        var found: [(volume: Volume, isStartup: Bool)] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let isStartup = values.volumeIsRootFileSystem ?? (url.path == "/")
            let facts = VolumeFacts(isLocal: values.volumeIsLocal ?? true,
                                    isInternal: values.volumeIsInternal ?? true,
                                    isImage: isDiskImage(url),
                                    isEjectable: values.volumeIsEjectable ?? false,
                                    isRemovable: values.volumeIsRemovable ?? false,
                                    isStartup: isStartup)
            let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            let free = DiskMath.free(important: values.volumeAvailableCapacityForImportantUsage,
                                     plain: values.volumeAvailableCapacity.map(Int64.init))
            let name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent
            let volume = Volume(id: url.path, name: name, total: total, free: min(free, total == 0 ? free : total),
                                kind: DiskMath.kind(facts), isEjectable: DiskMath.isEjectable(facts))
            found.append((volume, isStartup))
        }
        return DiskMath.order(found)
    }

    private func isDiskImage(_ url: URL) -> Bool {
        guard let session, let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any] else { return false }
        let model = description[kDADiskDescriptionDeviceModelKey as String] as? String
        let proto = description[kDADiskDescriptionDeviceProtocolKey as String] as? String
        return model == "Disk Image" || proto == "Disk Image"
    }

    private static func readCounters() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0
        var write: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString,
                                                              kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
            else { continue }
            read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (read, write)
    }
}
