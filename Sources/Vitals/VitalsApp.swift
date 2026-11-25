import ServiceManagement
import SwiftUI
import VitalsCore

@main
struct VitalsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--launch-at-login") {
            try? SMAppService.mainApp.register()
        }
        Snapshot.runIfRequested(makeSource: AppDelegate.makeSource)
        Snapshot.soakIfRequested(makeSource: AppDelegate.makeSource)
        Updater.shared.start()
    }

    var body: some Scene {
        // The window lives in MenuBarController. SwiftUI needs at least one scene; this one is never
        // inserted, so unlike `Settings` it cannot pop up an empty window when the app activates.
        MenuBarExtra("Vitals", isInserted: .constant(false)) { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: Monitor?
    private var menuBar: MenuBarController?
    private var activity: NSObjectProtocol?

    static func makeSource() -> VitalsSource {
        CommandLine.arguments.contains("--demo") ? DemoSource() : SystemSource()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !CommandLine.arguments.contains("--snapshot"), !CommandLine.arguments.contains("--soak") else { return }
        // Without this App Nap stretches the sampling timer to many seconds once the window is closed.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Zeichnet die Systemwerte auf")
        let monitor = Monitor(source: Self.makeSource())
        self.monitor = monitor
        let menuBar = MenuBarController(monitor: monitor)
        self.menuBar = menuBar
        if CommandLine.arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { menuBar.open() }
        }
    }
}
