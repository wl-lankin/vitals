import Foundation
import SystemConfiguration

enum NetworkMath {
    /// Only physical interfaces count, so tunnels and virtual links do not double-count traffic.
    static func isPhysical(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }

    static func rate(previous: UInt64, current: UInt64, seconds: Double) -> Double {
        guard current >= previous, seconds > 0 else { return 0 }
        return Double(current - previous) / seconds
    }

    /// Kind from the BSD name alone; `isWiFi` comes from SystemConfiguration for en* names.
    static func linkKind(name: String, isWiFi: Bool) -> LinkKind {
        if name.hasPrefix("pdp_ip") { return .cellular }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") { return .vpn }
        if name.hasPrefix("en") { return isWiFi ? .wifi : .ethernet }
        return .other
    }
}

public final class NetworkProbe {
    private var previousDown: UInt64 = 0
    private var previousUp: UInt64 = 0
    private var previousTime: UInt64 = 0
    private var hasPrevious = false
    private let store: SCDynamicStore?
    private var wifiNames: Set<String>?

    public init() {
        store = SCDynamicStoreCreate(nil, "Vitals" as CFString, nil, nil)
    }

    public func read() -> NetworkSample {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let counters = Self.readCounters()
        var down = 0.0
        var up = 0.0
        if hasPrevious {
            let seconds = Double(now &- previousTime) / 1e9
            down = NetworkMath.rate(previous: previousDown, current: counters.down, seconds: seconds)
            up = NetworkMath.rate(previous: previousUp, current: counters.up, seconds: seconds)
        }
        previousDown = counters.down
        previousUp = counters.up
        previousTime = now
        hasPrevious = true
        return NetworkSample(downRate: down, upRate: up, totalDown: counters.down, totalUp: counters.up,
                             link: readLink())
    }

    // NET_RT_IFLIST2 reports ifi_ibytes/ifi_obytes truncated to 32 bits on current macOS, so read
    // the full 64-bit counters per interface from the ifmib sysctl instead.
    private static func readCounters() -> (down: UInt64, up: UInt64) {
        guard let list = if_nameindex() else { return (0, 0) }
        defer { if_freenameindex(list) }
        var down: UInt64 = 0
        var up: UInt64 = 0
        var cursor = list
        while cursor.pointee.if_index != 0 {
            defer { cursor += 1 }
            guard let namePointer = cursor.pointee.if_name,
                  NetworkMath.isPhysical(String(cString: namePointer)) else { continue }
            var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(cursor.pointee.if_index),
                                IFDATA_GENERAL]
            var data = ifmibdata()
            var size = MemoryLayout<ifmibdata>.size
            guard sysctl(&mib, UInt32(mib.count), &data, &size, nil, 0) == 0 else { continue }
            down &+= data.ifmd_data.ifi_ibytes
            up &+= data.ifmd_data.ifi_obytes
        }
        return (down, up)
    }

    private func readLink() -> NetworkLink? {
        guard let store,
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let name = global["PrimaryInterface"] as? String, !name.isEmpty else { return nil }
        let router = global["Router"] as? String
        let isWiFi = name.hasPrefix("en") && wifiInterfaceNames().contains(name)
        return NetworkLink(name: name, kind: NetworkMath.linkKind(name: name, isWiFi: isWiFi),
                           ipv4: Self.ipv4(of: name), router: router)
    }

    private func wifiInterfaceNames() -> Set<String> {
        if let wifiNames { return wifiNames }
        var names = Set<String>()
        if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for interface in all {
                if let type = SCNetworkInterfaceGetInterfaceType(interface),
                   (type as String) == (kSCNetworkInterfaceTypeIEEE80211 as String),
                   let bsd = SCNetworkInterfaceGetBSDName(interface) {
                    names.insert(bsd as String)
                }
            }
        }
        wifiNames = names
        return names
    }

    private static func ipv4(of name: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(first) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.pointee.ifa_name) == name else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}
