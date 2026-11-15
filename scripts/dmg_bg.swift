import AppKit
// usage: swift dmg_bg.swift out.png "AppName" topHex bottomHex
// Rendered at 2x (1320x800 px for a 660x400 pt window) so it is sharp on Retina screens.
// Light background with dark text, because Finder always draws the icon labels in black.
let a = CommandLine.arguments
let out = a[1], name = a[2]
func col(_ h: String) -> NSColor {
    let v = UInt32(h.dropFirst(), radix: 16) ?? 0
    return NSColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
let W = 660, H = 400
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W * 2, pixelsHigh: H * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)   // points; pixels are 2x
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGradient(colors: [col(a[3]), col(a[4])])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
let ink = col(a.count > 5 ? a[5] : "#1e1b4b")
let para = NSMutableParagraphStyle(); para.alignment = .center
func text(_ s: String, size: CGFloat, weight: NSFont.Weight, y: CGFloat, alpha: CGFloat) {
    s.draw(in: NSRect(x: 0, y: y, width: CGFloat(W), height: size + 10), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink.withAlphaComponent(alpha), .paragraphStyle: para])
}
text("Drag \(name) into Applications", size: 26, weight: .semibold, y: 318, alpha: 1)
text("Then open it from your Applications folder or Launchpad", size: 13, weight: .regular, y: 288, alpha: 0.65)
let p = NSBezierPath(); p.lineWidth = 7; p.lineCapStyle = .round; p.lineJoinStyle = .round
p.move(to: NSPoint(x: 268, y: 200)); p.line(to: NSPoint(x: 392, y: 200))
p.move(to: NSPoint(x: 366, y: 226)); p.line(to: NSPoint(x: 392, y: 200)); p.line(to: NSPoint(x: 366, y: 174))
ink.withAlphaComponent(0.55).setStroke(); p.stroke()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
