// Renders the 1024px app icon: a heartbeat trace on a dark instrument face, ending in the glowing
// "now" point every trace in the app ends in. Usage: swift scripts/make_icon.swift out.png
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: stops.map { color($0.0, $0.1) } as CFArray,
               locations: stops.map { $0.2 })!
}

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
let mid: CGFloat = 500

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x000000, 0.4))
ctx.addPath(shape); ctx.setFillColor(color(0x0E1218)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape); ctx.clip()

// Instrument face
ctx.drawLinearGradient(gradient([(0x1B222D, 1, 0), (0x10141B, 1, 0.55), (0x0A0D12, 1, 1)]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// Glow in the state colour, as behind the window's header
ctx.drawRadialGradient(gradient([(0x4FE3A6, 0.34, 0), (0x4FE3A6, 0.10, 0.5), (0x4FE3A6, 0, 1)]),
                       startCenter: CGPoint(x: 250, y: 860), startRadius: 0,
                       endCenter: CGPoint(x: 250, y: 860), endRadius: 640, options: [])

// Baseline
ctx.setFillColor(color(0xFFFFFF, 0.10))
ctx.fill(CGRect(x: 100, y: mid - 2, width: 824, height: 4))

// The beat
let beat = CGMutablePath()
beat.move(to: CGPoint(x: 100, y: mid))
beat.addLine(to: CGPoint(x: 352, y: mid))
beat.addLine(to: CGPoint(x: 398, y: mid + 62))
beat.addLine(to: CGPoint(x: 438, y: mid - 52))
beat.addLine(to: CGPoint(x: 506, y: mid + 268))
beat.addLine(to: CGPoint(x: 586, y: mid - 214))
beat.addLine(to: CGPoint(x: 636, y: mid + 40))
beat.addLine(to: CGPoint(x: 668, y: mid))
beat.addLine(to: CGPoint(x: 800, y: mid))

func strokeBeat(width: CGFloat) -> CGPath {
    beat.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

// Soft halo first, then the line itself with a gradient from mint to sky blue.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 46, color: color(0x4FE3A6, 0.75))
ctx.addPath(strokeBeat(width: 30)); ctx.setFillColor(color(0x4FE3A6, 0.9)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(strokeBeat(width: 34)); ctx.clip()
ctx.drawLinearGradient(gradient([(0x4FE3A6, 1, 0), (0x5FD8C4, 1, 0.55), (0x62B4FF, 1, 1)]),
                       start: CGPoint(x: 300, y: mid), end: CGPoint(x: 820, y: mid), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

// "Now"
let now = CGPoint(x: 800, y: mid)
ctx.drawRadialGradient(gradient([(0x9CCBFF, 0.95, 0), (0x62B4FF, 0.35, 0.4), (0x62B4FF, 0, 1)]),
                       startCenter: now, startRadius: 0, endCenter: now, endRadius: 120, options: [])
ctx.setFillColor(color(0xFFFFFF))
ctx.fillEllipse(in: CGRect(x: now.x - 34, y: now.y - 34, width: 68, height: 68))

ctx.restoreGState()

// Thin light edge
ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
ctx.setStrokeColor(color(0xFFFFFF, 0.10)); ctx.setLineWidth(4); ctx.strokePath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
