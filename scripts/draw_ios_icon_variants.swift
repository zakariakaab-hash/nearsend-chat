// Draws the Nearsend Chat app icon ("Bubble arrow": a chat bubble with Nearsend's dot-and-arrow inside)
// as the three iOS icons, 1024x1024 PNG:
//   icon-1024.png         light/default: white glyph on solid Nearsend blue, opaque (App Store needs no alpha)
//   icon-dark-1024.png    dark: blue glyph on a transparent background (iOS supplies the dark backdrop)
//   icon-tinted-1024.png  tinted: white glyph on black; iOS maps brightness to the user's tint colour
// Geometry is in a 240x240 design grid (same as the design canvas), scaled to 1024.
// Usage (from the repo root): swift scripts/draw_ios_icon_variants.swift NearsendChatiOS/Sources/Resources/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let grid: CGFloat = 240

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// The bubble outline: a rounded square with its tail at the bottom right.
func bubblePath() -> CGPath {
    let p = CGMutablePath()
    let deg = CGFloat.pi / 180
    p.move(to: CGPoint(x: 92, y: 58))
    p.addLine(to: CGPoint(x: 148, y: 58))
    p.addArc(center: CGPoint(x: 148, y: 98), radius: 40, startAngle: 270 * deg, endAngle: 360 * deg, clockwise: false)
    p.addLine(to: CGPoint(x: 188, y: 122))
    p.addArc(center: CGPoint(x: 148, y: 122), radius: 40, startAngle: 0, endAngle: atan2(32, 24), clockwise: false)
    p.addLine(to: CGPoint(x: 184, y: 186))
    p.addLine(to: CGPoint(x: 142, y: 162))
    p.addLine(to: CGPoint(x: 92, y: 162))
    p.addArc(center: CGPoint(x: 92, y: 122), radius: 40, startAngle: 90 * deg, endAngle: 180 * deg, clockwise: false)
    p.addLine(to: CGPoint(x: 52, y: 98))
    p.addArc(center: CGPoint(x: 92, y: 98), radius: 40, startAngle: 180 * deg, endAngle: 270 * deg, clockwise: false)
    p.closeSubpath()
    return p
}

func draw(background: CGColor?, glyph: CGColor, opaque: Bool, to url: URL) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: info)!
    // Top-left origin like the SVG design grid, then scale 240 -> 1024.
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)
    ctx.scaleBy(x: CGFloat(size) / grid, y: CGFloat(size) / grid)
    if let background { ctx.setFillColor(background); ctx.fill(CGRect(x: 0, y: 0, width: grid, height: grid)) }

    ctx.setStrokeColor(glyph); ctx.setFillColor(glyph)
    ctx.setLineWidth(14); ctx.setLineJoin(.round); ctx.setLineCap(.round)
    ctx.addPath(bubblePath()); ctx.strokePath()

    ctx.fillEllipse(in: CGRect(x: 94 - 13, y: 110 - 13, width: 26, height: 26))   // Nearsend's dot
    ctx.move(to: CGPoint(x: 94, y: 110)); ctx.addLine(to: CGPoint(x: 150, y: 110))  // arrow shaft
    ctx.move(to: CGPoint(x: 132, y: 92)); ctx.addLine(to: CGPoint(x: 150, y: 110)); ctx.addLine(to: CGPoint(x: 132, y: 128))
    ctx.strokePath()

    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    precondition(CGImageDestinationFinalize(dest), "could not write \(url.path)")
    print("wrote", url.lastPathComponent)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
draw(background: rgb(0x2F7BF5), glyph: rgb(0xFFFFFF), opaque: true, to: out.appendingPathComponent("icon-1024.png"))
draw(background: nil, glyph: rgb(0x5B96F7), opaque: false, to: out.appendingPathComponent("icon-dark-1024.png"))
draw(background: rgb(0x000000), glyph: rgb(0xFFFFFF), opaque: false, to: out.appendingPathComponent("icon-tinted-1024.png"))
