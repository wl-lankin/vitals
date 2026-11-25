import AppKit
import SwiftUI
import VitalsCore

/// Status item plus its own panel. The panel follows the height of its content (rows expand in
/// place), stays anchored at its top edge and recomputes its shadow after every resize.
@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    static private(set) var shared: MenuBarController?

    private let monitor: Monitor
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: VitalsPanel?
    private var lastClose = Date.distantPast
    private var lastLabel: BarLabel?

    init(monitor: Monitor) {
        self.monitor = monitor
        super.init()
        Self.shared = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .regular), weight: .regular)
        }
        updateLabel()
        monitor.onSample = { [weak self] in self?.updateLabel() }
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    var isOpen: Bool { panel?.isVisible ?? false }

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        monitor.setOpen(true)
        panel.fitToContent(anchor: anchorPoint())
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // The first frame after ordering in can come from a stale backing store; force a fresh one.
        panel.contentView?.needsDisplay = true
        panel.displayIfNeeded()
        panel.invalidateShadow()
        statusItem.button?.highlight(true)
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        monitor.setOpen(false)
        lastClose = Date()
        statusItem.button?.highlight(false)
    }

    @objc private func statusClicked() {
        // A click on the status item first takes key from the panel, which closes it. Without this
        // guard the same click would immediately open it again.
        if !isOpen && Date().timeIntervalSince(lastClose) < 0.3 { return }
        toggle()
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    @objc private func defaultsChanged() {
        updateLabel()
    }

    private func updateLabel() {
        guard let button = statusItem.button else { return }
        let label = BarLabel.make(sample: monitor.current, load: monitor.currentLoad)
        guard label != lastLabel else { return }
        lastLabel = label
        button.image = BarIcon.image(level: label.level)
        button.title = label.text.map { " " + $0 } ?? ""
        button.toolTip = label.text == nil ? "Vitals" : nil
    }

    private func makePanel() -> VitalsPanel {
        let panel = VitalsPanel(monitor: monitor)
        panel.delegate = self
        return panel
    }

    /// Top-left corner for the panel: just below the status item, kept on its screen.
    private func anchorPoint() -> NSPoint {
        guard let button = statusItem.button, let window = button.window else {
            let screen = NSScreen.main?.visibleFrame ?? .zero
            return NSPoint(x: screen.maxX - Metrics.width - 10, y: screen.maxY - 4)
        }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return NSPoint(x: frame.minX, y: frame.minY - 4)
    }
}

/// Borderless key panel with popover material, rounded corners and a shadow that follows the content.
final class VitalsPanel: NSPanel {
    private static let radius: CGFloat = 12
    private let host: NSHostingView<AnyView>
    private let relay = SizeRelay()
    private var anchor = NSPoint.zero

    @MainActor
    init(monitor: Monitor) {
        let relay = self.relay
        // The content is measured at its ideal height and pinned to the top, so the window can follow
        // it exactly and the content never floats in the middle of a window that is still too large.
        let root = PopoverView()
            .environment(monitor)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geo in
                Color.clear.onChange(of: geo.size, initial: true) { _, size in relay.report(size) }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        host = NSHostingView(rootView: AnyView(root))
        super.init(contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: 600),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.maskImage = Self.roundedMask(radius: Self.radius)

        // Frame-based layout: the window size is set by `refit()`, never by Auto Layout.
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        contentView = effect
        host.frame = effect.bounds

        relay.onChange = { [weak self] in self?.refit() }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        MenuBarController.shared?.close()
    }

    @MainActor
    func fitToContent(anchor: NSPoint) {
        self.anchor = anchor
        host.layoutSubtreeIfNeeded()
        refit()
    }

    /// Sizes the panel to its content, top edge at the anchor, kept inside the visible screen area.
    @MainActor
    private func refit() {
        var size = relay.size
        if size.width <= 0 || size.height <= 0 { size = host.fittingSize }
        guard size.width > 0, size.height > 0 else { return }
        size = NSSize(width: ceil(size.width), height: ceil(size.height))
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? .zero
        var x = anchor.x
        if screen.width > 0 {
            x = min(max(x, screen.minX + 6), screen.maxX - size.width - 6)
        }
        let frame = NSRect(x: x, y: anchor.y - size.height, width: size.width, height: size.height)
        if frame != self.frame {
            setFrame(frame, display: true)
        }
        invalidateShadow()
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Carries the measured SwiftUI content size to the panel, outside of the view update.
private final class SizeRelay {
    private(set) var size = CGSize.zero
    var onChange: (() -> Void)?

    func report(_ size: CGSize) {
        guard size != self.size else { return }
        self.size = size
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }
}
