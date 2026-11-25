import SwiftUI
import VitalsCore

/// A line (or the area under it) through values laid out on the shared time axis.
struct TraceShape: Shape {
    /// Horizontal positions, 0...1.
    let xs: [Double]
    /// Heights, 0 at the baseline and 1 at the top.
    let ys: [Double]
    let starts: [Bool]
    var closed = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = min(xs.count, ys.count)
        guard count > 0 else { return path }
        var segmentStart = 0

        func point(_ i: Int) -> CGPoint {
            CGPoint(x: rect.minX + xs[i] * rect.width,
                    y: rect.maxY - min(1, max(0, ys[i])) * rect.height)
        }
        func finish(_ end: Int) {
            guard closed else { return }
            path.addLine(to: CGPoint(x: point(end).x, y: rect.maxY))
            path.addLine(to: CGPoint(x: point(segmentStart).x, y: rect.maxY))
            path.closeSubpath()
        }

        for i in 0..<count {
            if i == 0 || (i < starts.count && starts[i]) {
                if i > 0 { finish(i - 1) }
                segmentStart = i
                path.move(to: point(i))
                // A lone sample would draw nothing; give it a hair of width.
                if i == count - 1 || (i + 1 < starts.count && starts[i + 1]) {
                    path.addLine(to: CGPoint(x: point(i).x + 0.5, y: point(i).y))
                }
            } else {
                path.addLine(to: point(i))
            }
        }
        finish(count - 1)
        return path
    }
}

/// One coloured trace: soft fill below, crisp line on top.
struct TraceLayer: View {
    let timeline: Timeline
    let ys: [Double]
    let color: Color
    var fillOpacity = 0.26

    var body: some View {
        ZStack {
            TraceShape(xs: timeline.xs, ys: ys, starts: timeline.starts, closed: true)
                .fill(LinearGradient(colors: [color.opacity(fillOpacity), color.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
            TraceShape(xs: timeline.xs, ys: ys, starts: timeline.starts)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

/// A point the frame marks on a trace: at the right edge while live, under the cursor while scrubbing.
struct TraceMark {
    /// Height from the bottom of the frame, 0...1.
    var y: Double
    var color: Color
}

/// Hosts one or more traces: takes the pointer for scrubbing and draws the cursor every trace shares.
struct TraceFrame<Content: View>: View {
    @Environment(Monitor.self) private var monitor
    var height: CGFloat = Metrics.traceHeight
    let marks: (Sample) -> [TraceMark]
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                content
                pointer(in: size)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    monitor.scrub(toFraction: location.x / max(1, size.width))
                case .ended:
                    monitor.endScrub()
                }
            }
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func pointer(in size: CGSize) -> some View {
        if monitor.timeline.samples.isEmpty {
            EmptyView()
        } else if let cursor = monitor.cursor {
            let x = cursor * size.width
            Rectangle()
                .fill(.primary.opacity(0.45))
                .frame(width: 1, height: size.height + 6)
                .offset(x: x - 0.5, y: -3)
            ForEach(Array(marks(monitor.shown).enumerated()), id: \.offset) { _, mark in
                Circle()
                    .fill(mark.color)
                    .overlay(Circle().strokeBorder(.background.opacity(0.9), lineWidth: 1.5))
                    .frame(width: 8, height: 8)
                    .offset(x: x - 4, y: (1 - mark.y) * size.height - 4)
            }
        } else {
            ForEach(Array(marks(monitor.latest).enumerated()), id: \.offset) { _, mark in
                // A gradient halo instead of a shadow: shadows are blurred on the CPU at every redraw.
                Circle()
                    .fill(RadialGradient(colors: [mark.color.opacity(0.5), mark.color.opacity(0)],
                                         center: .center, startRadius: 1.5, endRadius: 7))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().fill(mark.color).frame(width: 5, height: 5))
                    .offset(x: size.width - 7, y: (1 - mark.y) * size.height - 7)
            }
        }
    }
}

/// The thin line a trace stands on.
struct TraceBaseline: View {
    var body: some View {
        Rectangle().fill(.primary.opacity(0.1)).frame(height: 1)
    }
}

// MARK: The three kinds of chart

/// One value over time on a fixed or self-adjusting scale.
struct SingleTrace: View {
    @Environment(Monitor.self) private var monitor
    let color: Color
    /// Top of the scale; nil scales to the visible peak.
    var ceiling: Double? = 1
    var floor: Double = 1
    let value: (Sample) -> Double?

    var body: some View {
        let timeline = monitor.timeline
        let raw = timeline.samples.map { value($0) ?? 0 }
        let top = ceiling ?? Scale.fit(raw.max() ?? 0, floor: floor)
        TraceFrame(marks: { sample in
            [TraceMark(y: min(1, (value(sample) ?? 0) / top), color: color)]
        }) {
            VStack(spacing: 0) {
                TraceLayer(timeline: timeline, ys: raw.map { $0 / top }, color: color)
                TraceBaseline()
            }
        }
    }
}

/// Two opposing flows around a middle line: incoming above, outgoing below, on one scale.
struct MirroredTrace: View {
    @Environment(Monitor.self) private var monitor
    let color: Color
    let floor: Double
    let upper: (Sample) -> Double
    let lower: (Sample) -> Double

    var body: some View {
        let timeline = monitor.timeline
        let above = timeline.samples.map(upper)
        let below = timeline.samples.map(lower)
        let top = Scale.fit(max(above.max() ?? 0, below.max() ?? 0), floor: floor)
        TraceFrame(marks: { sample in
            [TraceMark(y: 0.5 + min(1, upper(sample) / top) / 2, color: color),
             TraceMark(y: 0.5 - min(1, lower(sample) / top) / 2, color: color.opacity(0.8))]
        }) {
            VStack(spacing: 0) {
                TraceLayer(timeline: timeline, ys: above.map { $0 / top }, color: color)
                TraceBaseline()
                TraceLayer(timeline: timeline, ys: below.map { $0 / top }, color: color.opacity(0.8), fillOpacity: 0.2)
                    .scaleEffect(x: 1, y: -1)
            }
        }
    }
}

/// Memory as stacked bands: what apps hold, what the system pins, what is compressed, what is only cache.
struct MemoryTrace: View {
    @Environment(Monitor.self) private var monitor

    static let app = Tone.memory
    static let wired = Color(light: 0x4B5FD6, dark: 0x8C9BFF)
    static let compressed = Color(light: 0x2CA6B8, dark: 0x79E0EE)

    var body: some View {
        let timeline = monitor.timeline
        let samples = timeline.samples
        func stack(_ part: (MemorySample) -> UInt64) -> [Double] {
            samples.map { $0.memory.total == 0 ? 0 : Double(part($0.memory)) / Double($0.memory.total) }
        }
        let wired = stack { $0.wired }
        let app = stack { $0.wired + $0.app }
        let used = stack { $0.used }
        let cached = stack { $0.used + $0.cached }

        return TraceFrame(marks: { sample in
            [TraceMark(y: sample.memory.usedFraction, color: Self.app)]
        }) {
            VStack(spacing: 0) {
                ZStack {
                    band(timeline, cached).fill(.primary.opacity(0.07))
                    band(timeline, used).fill(Self.compressed.opacity(0.42))
                    band(timeline, app).fill(Self.app.opacity(0.30))
                    band(timeline, wired).fill(Self.wired.opacity(0.42))
                    TraceShape(xs: timeline.xs, ys: used, starts: timeline.starts)
                        .stroke(Self.app, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                TraceBaseline()
            }
        }
    }

    private func band(_ timeline: Timeline, _ ys: [Double]) -> TraceShape {
        TraceShape(xs: timeline.xs, ys: ys, starts: timeline.starts, closed: true)
    }
}

enum Scale {
    /// Top of a self-adjusting scale: a little headroom above the peak, never below `floor`,
    /// so a quiet line stays flat instead of magnifying noise.
    static func fit(_ peak: Double, floor: Double) -> Double {
        max(peak, floor) * 1.08
    }
}
