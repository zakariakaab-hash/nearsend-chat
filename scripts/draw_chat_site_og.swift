// Draws website/chat/og.png (1200x630 share image) for chat.nearsend.app.
// Usage: swift scripts/draw_chat_site_og.swift   (run from the repo root)
import AppKit
let W: CGFloat = 1200, H: CGFloat = 630
let root = FileManager.default.currentDirectoryPath
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: root + "/website/chat/fonts/Anton-Regular.ttf") as CFURL, .process, nil)
func c(_ h: Int, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a) }
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
NSGradient(colorsAndLocations: (c(0xECD2B0), 0), (c(0xA9C4E6), 0.2), (c(0x6D9BD6), 0.55), (c(0x356CB5), 1))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)
// logo
let icon = NSImage(contentsOfFile: root + "/website/chat/favicon.svg")!
icon.draw(in: NSRect(x: 64, y: H - 64 - 72, width: 72, height: 72))
NSAttributedString(string: "Nearsend Chat", attributes: [.font: NSFont.systemFont(ofSize: 40, weight: .semibold), .foregroundColor: NSColor.white]).draw(at: NSPoint(x: 156, y: H - 64 - 56))
// headline
let anton = NSFont(name: "Anton-Regular", size: 92)!
let shadow = NSShadow(); shadow.shadowColor = c(0x0C2444, 0.35); shadow.shadowBlurRadius = 10; shadow.shadowOffset = NSSize(width: 0, height: -3)
for (i, line) in ["MESSAGING THAT", "WORKS WITHOUT", "THE INTERNET."].enumerated() {
  NSAttributedString(string: line, attributes: [.font: anton, .foregroundColor: NSColor.white, .shadow: shadow]).draw(at: NSPoint(x: 64, y: H - 210 - CGFloat(i) * 104 - 60))
}
// pill
let pill = NSRect(x: 64, y: 52, width: 560, height: 64)
c(0x0E2855, 0.8).setFill(); NSBezierPath(roundedRect: pill, xRadius: 32, yRadius: 32).fill()
NSAttributedString(string: "Bluetooth  ·  No account  ·  No internet", attributes: [.font: NSFont.systemFont(ofSize: 28, weight: .medium), .foregroundColor: NSColor.white]).draw(at: NSPoint(x: 92, y: 68))
// phone with the real Nearby screen
let shot = NSImage(contentsOfFile: root + "/NearsendChatiOS/appstore-screenshots/iphone-6.3/1-nearby.png")!
let ph: CGFloat = 560, pw = ph * 1206 / 2622
let frame = NSRect(x: W - 80 - pw, y: 35, width: pw, height: ph)
let sh = NSShadow(); sh.shadowColor = c(0x143C78, 0.45); sh.shadowBlurRadius = 30; sh.shadowOffset = NSSize(width: 0, height: -10)
NSGraphicsContext.saveGraphicsState(); sh.set(); c(0x0C1A36).setFill(); NSBezierPath(roundedRect: frame.insetBy(dx: -10, dy: -10), xRadius: 52, yRadius: 52).fill(); NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect: frame, xRadius: 42, yRadius: 42).addClip(); shot.draw(in: frame); NSGraphicsContext.restoreGraphicsState()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let px = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: px); rep.draw(in: NSRect(x: 0, y: 0, width: W, height: H)); NSGraphicsContext.restoreGraphicsState()
try! px.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: root + "/website/chat/og.png"))
print("wrote website/chat/og.png")
