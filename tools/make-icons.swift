// Development-only helper that renders the workflow's PNG icons.
// The generated PNGs are committed; nothing here runs at workflow runtime.
//
//   swift tools/make-icons.swift src
//
// Shapes are drawn with plain Core Graphics paths (no SF Symbols, no emoji),
// so the artwork carries no third-party licence.

import AppKit

let size: CGFloat = 256

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

func render(_ path: String, background: NSColor, draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    background.setFill()
    NSBezierPath(roundedRect: NSRect(x: 12, y: 12, width: size - 24, height: size - 24),
                 xRadius: 52, yRadius: 52).fill()
    NSColor.white.setFill()
    NSColor.white.setStroke()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func person(cx: CGFloat, cy: CGFloat, s: CGFloat) {
    NSBezierPath(ovalIn: NSRect(x: cx - 0.2 * s, y: cy + 0.05 * s, width: 0.4 * s, height: 0.4 * s)).fill()
    let body = NSBezierPath()
    body.move(to: NSPoint(x: cx - 0.38 * s, y: cy - 0.45 * s))
    body.curve(to: NSPoint(x: cx + 0.38 * s, y: cy - 0.45 * s),
               controlPoint1: NSPoint(x: cx - 0.38 * s, y: cy + 0.05 * s),
               controlPoint2: NSPoint(x: cx + 0.38 * s, y: cy + 0.05 * s))
    body.close()
    body.fill()
}

func line(_ a: NSPoint, _ b: NSPoint, width: CGFloat) {
    let p = NSBezierPath()
    p.move(to: a)
    p.line(to: b)
    p.lineWidth = width
    p.lineCapStyle = .round
    p.stroke()
}

func hash() {
    let w: CGFloat = 20
    line(NSPoint(x: 112, y: 60), NSPoint(x: 128, y: 196), width: w)
    line(NSPoint(x: 152, y: 60), NSPoint(x: 168, y: 196), width: w)
    line(NSPoint(x: 72, y: 150), NSPoint(x: 196, y: 150), width: w)
    line(NSPoint(x: 64, y: 106), NSPoint(x: 188, y: 106), width: w)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "src"

render("\(out)/icon.png", background: hex(0x4A154B)) { hash() }

render("\(out)/icons/person.png", background: hex(0x2EB67D)) {
    person(cx: 128, cy: 120, s: 150)
}

render("\(out)/icons/group.png", background: hex(0xECB22E)) {
    NSColor.white.withAlphaComponent(0.7).setFill()
    person(cx: 160, cy: 132, s: 120)
    NSColor.white.setFill()
    person(cx: 104, cy: 112, s: 130)
}

render("\(out)/icons/channel.png", background: hex(0x36C5F0)) { hash() }

render("\(out)/icons/private.png", background: hex(0x611F69)) {
    let shackle = NSBezierPath()
    shackle.appendArc(withCenter: NSPoint(x: 128, y: 150), radius: 38, startAngle: 0, endAngle: 180)
    shackle.move(to: NSPoint(x: 90, y: 150))
    shackle.line(to: NSPoint(x: 90, y: 128))
    shackle.move(to: NSPoint(x: 166, y: 150))
    shackle.line(to: NSPoint(x: 166, y: 128))
    shackle.lineWidth = 18
    shackle.stroke()
    NSBezierPath(roundedRect: NSRect(x: 66, y: 56, width: 124, height: 88), xRadius: 14, yRadius: 14).fill()
}

render("\(out)/icons/connect.png", background: hex(0xE01E5A)) {
    for (x, y) in [(102.0, 128.0), (154.0, 128.0)] {
        let ring = NSBezierPath(ovalIn: NSRect(x: x - 44, y: y - 44, width: 88, height: 88))
        ring.lineWidth = 18
        ring.stroke()
    }
}

render("\(out)/icons/warning.png", background: hex(0xC2410C)) {
    let tri = NSBezierPath()
    tri.move(to: NSPoint(x: 128, y: 204))
    tri.line(to: NSPoint(x: 50, y: 62))
    tri.line(to: NSPoint(x: 206, y: 62))
    tri.close()
    tri.lineWidth = 16
    tri.lineJoinStyle = .round
    tri.stroke()
    line(NSPoint(x: 128, y: 160), NSPoint(x: 128, y: 112), width: 18)
    NSBezierPath(ovalIn: NSRect(x: 118, y: 78, width: 20, height: 20)).fill()
}

render("\(out)/icons/refresh.png", background: hex(0x4B5563)) {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: 128, y: 128), radius: 62, startAngle: 60, endAngle: 350)
    arc.lineWidth = 18
    arc.lineCapStyle = .round
    arc.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 204, y: 140))
    head.line(to: NSPoint(x: 160, y: 136))
    head.line(to: NSPoint(x: 194, y: 96))
    head.close()
    head.fill()
}

render("\(out)/icons/key.png", background: hex(0x4B5563)) {
    let ring = NSBezierPath(ovalIn: NSRect(x: 52, y: 92, width: 72, height: 72))
    ring.lineWidth = 18
    ring.stroke()
    line(NSPoint(x: 124, y: 128), NSPoint(x: 206, y: 128), width: 18)
    line(NSPoint(x: 184, y: 128), NSPoint(x: 184, y: 100), width: 18)
    line(NSPoint(x: 160, y: 128), NSPoint(x: 160, y: 106), width: 18)
}
