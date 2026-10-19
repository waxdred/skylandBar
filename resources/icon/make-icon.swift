// make-icon <skyland.icns> <out.png>: skyland's icon (resources/Skyland.icns of skyland)
// with a bar badge in its accent, 1024 px, for skylandbar: the bar's capsule with its
// workspaces, the menu bar's row dropped under it.
import AppKit
let a = CommandLine.arguments
guard a.count == 3, let base = NSImage(contentsOfFile: a[1]) else { print("usage: make-icon <skyland.icns> <out.png>"); exit(2) }
let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
base.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
let dark = NSColor(srgbRed: 0.06, green: 0.05, blue: 0.12, alpha: 1)
let glow = NSGradient(colors: [NSColor(srgbRed: 0.35, green: 0.85, blue: 1, alpha: 1), NSColor(srgbRed: 1, green: 0.35, blue: 0.8, alpha: 1)])!
let cg = NSGraphicsContext.current!.cgContext

/// `path` stroked `width` wide with the neon gradient over `area`.
func neon(_ path: NSBezierPath, _ width: Double, _ area: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    cg.addPath(path.cgPath)
    cg.setLineWidth(width)
    cg.setLineJoin(.round)
    cg.setLineCap(.round)
    cg.replacePathWithStrokedPath()
    cg.clip()
    glow.draw(in: area, angle: -45)
    NSGraphicsContext.restoreGraphicsState()
}

// the badge: a dark rounded square with a neon rim, bottom right (as skyland files')
let badge = NSRect(x: 590, y: 90, width: 340, height: 340)
dark.withAlphaComponent(0.96).setFill()
NSBezierPath(roundedRect: badge, xRadius: 78, yRadius: 78).fill()
neon(NSBezierPath(roundedRect: badge.insetBy(dx: 7, dy: 7), xRadius: 71, yRadius: 71), 14, badge)
// the bar: a capsule with three workspaces, the first one lit
let bar = NSRect(x: badge.minX + 52, y: badge.maxY - 150, width: badge.width - 104, height: 72)
neon(NSBezierPath(roundedRect: bar, xRadius: 36, yRadius: 36), 16, badge)
for index in 0 ..< 3 {
    let dot = NSRect(x: bar.minX + 46 + Double(index) * 64 - 13, y: bar.midY - 13, width: 26, height: 26)
    let path = NSBezierPath(ovalIn: dot)
    if index == 0 {
        NSGraphicsContext.saveGraphicsState(); path.setClip(); glow.draw(in: badge, angle: -45); NSGraphicsContext.restoreGraphicsState()
    } else {
        neon(path, 8, badge)
    }
}
// the menu bar's row under it, two titles
let row = NSRect(x: bar.minX, y: bar.minY - 104, width: bar.width * 0.78, height: 64)
neon(NSBezierPath(roundedRect: row, xRadius: 32, yRadius: 32), 16, badge)
for (x, width) in [(row.minX + 34, 52.0), (row.minX + 110, 44.0)] {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: x, y: row.midY))
    line.line(to: NSPoint(x: x + width, y: row.midY))
    neon(line, 12, badge)
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
