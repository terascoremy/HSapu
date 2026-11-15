import AppKit
// usage: swift dmg_bg.swift out.png "AppName" topHex bottomHex
let a = CommandLine.arguments
let out = a[1], name = a[2]
func col(_ h: String) -> NSColor {
    let v = UInt32(h.dropFirst(), radix: 16) ?? 0
    return NSColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
let W = 660, H = 400
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGradient(colors: [col(a[3]), col(a[4])])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
let para = NSMutableParagraphStyle(); para.alignment = .center
func text(_ s: String, size: CGFloat, weight: NSFont.Weight, y: CGFloat, alpha: CGFloat) {
    s.draw(in: NSRect(x: 0, y: y, width: CGFloat(W), height: size + 10), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor.white.withAlphaComponent(alpha), .paragraphStyle: para])
}
text("Drag \(name) into Applications", size: 26, weight: .semibold, y: 318, alpha: 1)
text("Then open it from your Applications folder or Launchpad", size: 13, weight: .regular, y: 288, alpha: 0.7)
// arrow between the two icons (icons sit at y=200 from the top, i.e. y=200 from the bottom here too)
let p = NSBezierPath(); p.lineWidth = 7; p.lineCapStyle = .round; p.lineJoinStyle = .round
p.move(to: NSPoint(x: 268, y: 200)); p.line(to: NSPoint(x: 392, y: 200))
p.move(to: NSPoint(x: 366, y: 226)); p.line(to: NSPoint(x: 392, y: 200)); p.line(to: NSPoint(x: 366, y: 174))
NSColor.white.withAlphaComponent(0.85).setStroke(); p.stroke()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
