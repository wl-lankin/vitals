import AppKit
import SwiftUI
import VitalsCore

/// `Vitals --snapshot <dir> [main|processor|memory|network|power|scrub] [--real]` renders the window
/// in light and dark mode to PNGs and quits. Demo data by default, so the pictures show no real apps.
@MainActor
enum Snapshot {
    static func runIfRequested(makeSource: () -> VitalsSource) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        let mode = i + 2 < args.count && !args[i + 2].hasPrefix("--") ? args[i + 2] : "main"

        let monitor: Monitor
        let wait: TimeInterval
        if args.contains("--real") {
            monitor = Monitor(source: makeSource())
            wait = 9
        } else {
            let demo = DemoSource()
            monitor = Monitor(source: demo, prefill: demo.prefill(), autostart: false)
            wait = 0.3
        }
        monitor.setOpen(true)

        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            switch mode {
            case "scrub": monitor.scrub(toFraction: 0.42)
            case "main": break
            default: monitor.expanded = Monitor.Section(rawValue: mode)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    render(monitor: monitor, appearance: NSAppearance(named: appearance)!,
                           to: dir.appendingPathComponent("vitals-\(mode)-\(name).png"))
                }
                exit(0)
            }
        }
    }

    /// `Vitals --soak <seconds> [--real]` keeps the window alive off screen with live updates and
    /// prints the memory footprint every five seconds. For finding leaks without clicking around.
    static func soakIfRequested(makeSource: () -> VitalsSource) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--soak"), i + 1 < args.count, let seconds = Double(args[i + 1]) else { return }
        let monitor = Monitor(source: args.contains("--real") ? makeSource() : DemoSource())
        monitor.setOpen(true)
        if let section = args.dropFirst(i + 2).compactMap({ Monitor.Section(rawValue: $0) }).first {
            monitor.expanded = section
        }
        let host = NSHostingView(rootView: PopoverView().environment(monitor))
        let size = NSSize(width: Metrics.width, height: 760)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: 40, y: 40), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .init(rawValue: -1000)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
        soakWindow = window
        soakMonitor = monitor
        let start = Date()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            print(String(format: "%3.0f s  %.1f MB", Date().timeIntervalSince(start), footprint() / 1_048_576))
            fflush(stdout)
            if Date().timeIntervalSince(start) >= seconds { exit(0) }
        }
    }

    private static var soakWindow: NSWindow?
    private static var soakMonitor: Monitor?

    nonisolated private static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) : 0
    }

    private static func render(monitor: Monitor, appearance: NSAppearance, to url: URL) {
        let host = NSHostingView(rootView: PopoverView().environment(monitor))
        host.appearance = appearance
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        host.frame = effect.bounds
        effect.addSubview(host)
        window.contentView = effect
        window.orderFrontRegardless()
        effect.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        guard let rep = effect.bitmapImageRepForCachingDisplay(in: effect.bounds) else { return }
        effect.cacheDisplay(in: effect.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
