import Darwin
import Foundation

/// One row of `ps` output.
struct ProcessListEntry: Equatable {
    var pid: Int32
    var ppid: Int32
    /// Cumulative CPU time in seconds.
    var cpuSeconds: Double
    /// Resident set size in bytes.
    var rssBytes: UInt64
    var path: String
}

/// A process with its per-read figures, ready to be grouped.
struct ProcessRecord: Equatable {
    var pid: Int32
    var path: String
    var cpu: Double
    var memory: UInt64
}

enum ProcessGroupKind: Equatable {
    case bundle(String)
    /// Helper-like executable that may belong to an app through its responsible process.
    case needsResponsible
    case executable(String)
}

public final class ProcessProbe {
    private var previous: [Int32: (seconds: Double, path: String)] = [:]
    private var previousTime: UInt64?
    private var lastSample: ProcessSample = .zero
    private var nameCache: [String: String] = [:]
    private let responsibleFn: (@convention(c) (Int32) -> Int32)?

    public init() {
        typealias Fn = @convention(c) (Int32) -> Int32
        if let handle = dlopen(nil, RTLD_NOW), let sym = dlsym(handle, "responsibility_get_pid_responsible_for_pid") {
            responsibleFn = unsafeBitCast(sym, to: Fn.self)
        } else {
            responsibleFn = nil
        }
    }

    public func read() -> ProcessSample {
        let start = DispatchTime.now().uptimeNanoseconds
        guard let output = runPS() else { return lastSample }
        let end = DispatchTime.now().uptimeNanoseconds

        let ownChild = lastChildPID
        let entries = output.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { Self.parseLine(String($0)) }
            .filter { $0.pid != ownChild }
        guard !entries.isEmpty else { return lastSample }

        let midpoint = start &+ (end &- start) / 2
        let elapsed = previousTime.map { Double(midpoint &- $0) / 1e9 } ?? 0

        var records: [ProcessRecord] = []
        records.reserveCapacity(entries.count)
        var seen: [Int32: (seconds: Double, path: String)] = [:]
        seen.reserveCapacity(entries.count)
        for e in entries {
            var cpu = 0.0
            if elapsed > 0, let p = previous[e.pid], p.path == e.path, e.cpuSeconds >= p.seconds {
                cpu = (e.cpuSeconds - p.seconds) / elapsed
            }
            seen[e.pid] = (e.cpuSeconds, e.path)
            records.append(ProcessRecord(pid: e.pid, path: e.path, cpu: cpu,
                                         memory: Self.footprint(of: e.pid) ?? e.rssBytes))
        }
        previous = seen
        previousTime = midpoint

        let responsible = responsibleFn
        let sample = Self.aggregate(
            records,
            responsiblePID: { pid in
                guard let responsible else { return nil }
                let r = responsible(pid)
                return r > 0 ? r : nil
            },
            displayName: { [self] bundle in displayName(forBundle: bundle) })
        lastSample = sample
        return sample
    }

    // MARK: ps

    private var lastChildPID: Int32 = 0

    // posix_spawn instead of Foundation.Process: about 25 ms instead of 95 ms per run.
    private func runPS() -> String? {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return nil }
        let readEnd = fds[0], writeEnd = fds[1]

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            close(readEnd); close(writeEnd)
            return nil
        }
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, writeEnd, 1)
        posix_spawn_file_actions_addclose(&actions, readEnd)
        posix_spawn_file_actions_addclose(&actions, writeEnd)
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)

        let arguments = ["ps", "-Axo", "pid=,ppid=,time=,rss=,comm="]
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { for p in argv { free(p) } }

        var child: pid_t = 0
        let rc = posix_spawn(&child, "/bin/ps", &actions, nil, &argv, environ)
        close(writeEnd)
        guard rc == 0 else { close(readEnd); return nil }
        lastChildPID = child

        // Read to EOF before waiting so a full pipe cannot block the child.
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        var timedOut = false
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            if now >= deadline { timedOut = true; break }
            var pfd = pollfd(fd: readEnd, events: Int16(POLLIN), revents: 0)
            let remainingMs = Int32(min(Int64(Int32.max), Int64((deadline - now) / 1_000_000) + 1))
            let ready = poll(&pfd, 1, remainingMs)
            if ready < 0 { if errno == EINTR { continue }; timedOut = true; break }
            if ready == 0 { continue }
            let n = Darwin.read(readEnd, &buffer, buffer.count)
            if n > 0 { data.append(buffer, count: n) }
            else if n == 0 { break }
            else if errno != EINTR && errno != EAGAIN { timedOut = true; break }
        }
        close(readEnd)
        if timedOut { kill(child, SIGTERM) }

        var status: Int32 = 0
        while waitpid(child, &status, 0) < 0 && errno == EINTR {}
        let exitedCleanly = (status & 0x7f) == 0 && ((status >> 8) & 0xff) == 0
        guard !timedOut, exitedCleanly else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Memory

    private static func footprint(of pid: Int32) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    private func displayName(forBundle path: String) -> String {
        if let cached = nameCache[path] { return cached }
        var name = FileManager.default.displayName(atPath: path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        if name.isEmpty { name = Self.lastComponent(path) }
        nameCache[path] = name
        return name
    }

    // MARK: Pure parts

    /// Parses `pid ppid time rss comm`; comm is the rest of the line and may contain spaces.
    static func parseLine(_ line: String) -> ProcessListEntry? {
        var rest = Substring(line)
        var fields: [Substring] = []
        for _ in 0..<4 {
            rest = rest.drop(while: { $0 == " " || $0 == "\t" })
            guard let end = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
            fields.append(rest[rest.startIndex..<end])
            rest = rest[end...]
        }
        let path = rest.drop(while: { $0 == " " || $0 == "\t" })
        guard !path.isEmpty,
              let pid = Int32(fields[0]), let ppid = Int32(fields[1]),
              let seconds = parseCPUTime(String(fields[2])),
              let rssKiB = UInt64(fields[3]) else { return nil }
        return ProcessListEntry(pid: pid, ppid: ppid, cpuSeconds: seconds, rssBytes: rssKiB &* 1024,
                                path: String(path))
    }

    /// Accepts `m:ss.cc`, `h:mm:ss` and `d-hh:mm:ss`; minutes may exceed 59.
    static func parseCPUTime(_ text: String) -> Double? {
        var rest = Substring(text)
        var days = 0.0
        if let dash = rest.firstIndex(of: "-") {
            guard let d = Double(rest[rest.startIndex..<dash]) else { return nil }
            days = d
            rest = rest[rest.index(after: dash)...]
        }
        let parts = rest.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        var values: [Double] = []
        for p in parts {
            guard let v = Double(p), v.isFinite, v >= 0 else { return nil }
            values.append(v)
        }
        var total = 0.0
        for v in values { total = total * 60 + v }
        return total + days * 86400
    }

    static func lastComponent(_ path: String) -> String {
        // A process that rewrote its title ("npm exec some-tool --flag") reports that instead of a path.
        guard path.hasPrefix("/") else {
            return path.split(separator: " ").first.map(String.init) ?? path
        }
        if let slash = path.lastIndex(of: "/") { return String(path[path.index(after: slash)...]) }
        return path
    }

    /// Service names in reverse-DNS form lose their vendor prefix:
    /// "com.apple.SafariPlatformSupport.Helper" reads as "SafariPlatformSupport.Helper".
    static func readableName(_ name: String) -> String {
        let parts = name.split(separator: ".")
        guard parts.count >= 3, ["com", "org", "net", "io"].contains(String(parts[0])) else { return name }
        return parts.dropFirst(2).joined(separator: ".")
    }

    /// The outermost `.app` bundle containing `path`, if any.
    static func outermostBundle(in path: String) -> String? {
        guard path.contains(".app") else { return nil }
        var offset = 0
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            offset += component.utf8.count
            if component.count > 4, component.hasSuffix(".app") {
                return String(decoding: Array(path.utf8.prefix(offset)), as: UTF8.self)
            }
            offset += 1
        }
        return nil
    }

    static func classify(path: String) -> ProcessGroupKind {
        if let bundle = outermostBundle(in: path) { return .bundle(bundle) }
        let components = path.split(separator: "/")
        let insideXPC = components.dropLast().contains { $0.hasSuffix(".xpc") }
        if insideXPC || path.hasPrefix("/System/Library/Frameworks/")
            || path.hasPrefix("/System/Library/PrivateFrameworks/") {
            return .needsResponsible
        }
        return .executable(lastComponent(path))
    }

    static func aggregate(_ records: [ProcessRecord],
                          responsiblePID: (Int32) -> Int32?,
                          displayName: (String) -> String) -> ProcessSample {
        var pathByPID: [Int32: String] = [:]
        pathByPID.reserveCapacity(records.count)
        for r in records { pathByPID[r.pid] = r.path }

        struct Group {
            var id: String
            var bundle: String?
            var cpu = 0.0
            var memory: UInt64 = 0
            var count = 0
            var lowestPID = Int32.max
            var mainPID = Int32.max
        }
        var groups: [String: Group] = [:]

        for r in records {
            var kind = classify(path: r.path)
            if kind == .needsResponsible {
                kind = .executable(lastComponent(r.path))
                if let rp = responsiblePID(r.pid), rp != r.pid, let rpath = pathByPID[rp],
                   let bundle = outermostBundle(in: rpath) {
                    kind = .bundle(bundle)
                }
            }
            let id: String
            let bundle: String?
            switch kind {
            case .bundle(let b): id = b; bundle = b
            case .executable(let name): id = name; bundle = nil
            case .needsResponsible: continue
            }
            var g = groups[id] ?? Group(id: id, bundle: bundle)
            g.cpu += r.cpu
            g.memory &+= r.memory
            g.count += 1
            g.lowestPID = min(g.lowestPID, r.pid)
            if let bundle, (r.path as NSString).deletingLastPathComponent == bundle + "/Contents/MacOS" {
                g.mainPID = min(g.mainPID, r.pid)
            }
            groups[id] = g
        }

        let usages: [AppUsage] = groups.values.map { g in
            AppUsage(id: g.id,
                     name: g.bundle.map(displayName) ?? readableName(g.id),
                     bundlePath: g.bundle,
                     pid: g.mainPID != Int32.max ? g.mainPID : g.lowestPID,
                     cpu: g.cpu, memory: g.memory, processCount: g.count)
        }
        let topCPU = usages.filter { $0.cpu > 0.005 }
            .sorted { $0.cpu != $1.cpu ? $0.cpu > $1.cpu : $0.id < $1.id }
            .prefix(5)
        let topMemory = usages
            .sorted { $0.memory != $1.memory ? $0.memory > $1.memory : $0.id < $1.id }
            .prefix(5)
        return ProcessSample(topCPU: Array(topCPU), topMemory: Array(topMemory), processCount: records.count)
    }
}
