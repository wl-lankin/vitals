import AppKit
import ServiceManagement
import SwiftUI
import VitalsCore

struct PopoverView: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
                .padding(.horizontal, Metrics.inset)
                .padding(.top, 15)
                .padding(.bottom, 10)
            TimeRail()
                .padding(.horizontal, Metrics.inset)
                .padding(.bottom, 2)
            // No rules between the rows: a trace stands on its own baseline, and that line already
            // closes the section. Rows without a trace draw a rule themselves.
            ProcessorRow()
            MemoryRow()
            DisksRow()
            NetworkRow()
            PowerRow()
            FooterView()
        }
        .frame(width: Metrics.width)
        .background(alignment: .top) { Aura(color: monitor.verdict.level.color) }
        .background { PanelVeil() }
    }
}

struct HeaderView: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let verdict = monitor.verdict
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Text(verdict.title)
                    .font(.readout(30))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
                Spacer(minLength: 4)
                PulseDot(color: verdict.level.color)
            }
            .animation(.easeInOut(duration: 0.25), value: verdict.title)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verdict.detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Spacer(minLength: 4)
                Text("läuft seit \(Fmt.duration(monitor.uptime))")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
                    .help("Seit dem letzten Neustart des Mac")
            }
        }
    }
}

/// The state as a small light, like the status lamp on an instrument.
struct PulseDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.6), color.opacity(0.12)],
                                 center: .center, startRadius: 3, endRadius: 10))
            .frame(width: 20, height: 20)
            .overlay(Circle().fill(color).frame(width: 9, height: 9))
            .animation(.easeInOut(duration: 0.4), value: color)
    }
}

/// Names the time axis the traces share, and carries the readout of the scrub cursor.
struct TimeRail: View {
    @Environment(Monitor.self) private var monitor
    @State private var labelWidth: CGFloat = 170
    @State private var hover = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                HStack {
                    Button {
                        monitor.setSpan(monitor.span == .tenMinutes ? .hour : .tenMinutes)
                    } label: {
                        HStack(spacing: 4) {
                            Text(monitor.span.label)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hover ? .primary : .secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hover = $0 }
                    .help("Zeitraum der Kurven wechseln")
                    Spacer()
                    Text("jetzt")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .opacity(monitor.isLive ? 1 : 0)

                if let cursor = monitor.cursor {
                    let shown = monitor.shown
                    let age = monitor.latest.time.timeIntervalSince(shown.time)
                    Text("\(Fmt.ago(age)) · \(Fmt.clock(shown.time, seconds: monitor.span == .tenMinutes)) Uhr")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
                        .offset(x: min(max(0, cursor * geo.size.width - labelWidth / 2),
                                       max(0, geo.size.width - labelWidth)))
                }
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 18)
    }
}

struct FooterView: View {
    @ObservedObject private var updater = Updater.shared
    @State private var hover = false

    var body: some View {
        HStack {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                MenuBarController.shared?.close()
            } label: {
                Text("„Aktivitätsanzeige“ öffnen")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hover ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            Spacer()
            if case .ready(let version) = updater.state {
                Button {
                    updater.relaunch()
                } label: {
                    Label("\(version) bereit · Neu starten", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Tone.processor)
                }
                .buttonStyle(.plain)
                .help("Vitals wurde aktualisiert und startet neu")
            }
            SettingsMenu()
        }
        .padding(.horizontal, Metrics.inset)
        .padding(.vertical, 10)
    }
}

struct SettingsMenu: View {
    @Environment(Monitor.self) private var monitor
    @AppStorage("barStyle") private var barStyle = BarStyle.icon.rawValue
    @AppStorage("animations") private var animations = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var updateState: Updater.State = .idle

    private var updateLabel: String {
        switch updateState {
        case .checking: "Suche nach Updates …"
        case .upToDate: "Vitals ist aktuell (\(Updater.shared.currentVersion))"
        case .downloading(let v): "Lade Version \(v) …"
        case .ready(let v): "Version \(v) ist bereit"
        case .failed(let m): "Update fehlgeschlagen: \(m)"
        case .idle: "Nach Updates suchen …"
        }
    }

    var body: some View {
        Menu {
            Picker("Menüleiste", selection: $barStyle) {
                ForEach(BarStyle.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Picker("Zeitraum", selection: Binding(get: { monitor.span }, set: { monitor.setSpan($0) })) {
                ForEach(Monitor.Span.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Animationen", isOn: $animations)
            Divider()
            Toggle("Bei Anmeldung starten", isOn: Binding(
                get: { launchAtLogin },
                set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        NSLog("Vitals: launch at login failed: \(error.localizedDescription)")
                    }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }))
            Divider()
            Button(updateLabel) { Task { await Updater.shared.check(manual: true) } }
                .disabled(!Updater.shared.isEnabled)
            Divider()
            Button("Vitals \(Updater.shared.currentVersion) beenden") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .onReceive(Updater.shared.$state) { updateState = $0 }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Einstellungen")
    }
}
