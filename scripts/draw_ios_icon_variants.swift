// Draws the Nearsend Chat radar icon as iOS 26 dark and tinted variants (1024x1024 PNG).
// Geometry matches icon-1024.png: rings r=378/257/137, centre dot, sweep to 0° from -62°, three peer dots.
// Usage (from the repo root): swift scripts/draw_ios_icon_variants.swift NearsendChatiOS/Sources/Resources/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let c = CGPoint(x: 512, y: 512)

struct Palette {
    var background: CGColor?          // nil = transparent (system supplies the backdrop)
    var ring: [CGColor]               // outer, middle, inner
    var sweep: CGColor
    var line: CGColor
    var dotRing: CGColor
    var dotFill: CGColor
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
func gray(_ w: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(gray: w, alpha: a) }

func draw(_ p: Palette, to url: URL) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Work in top-left coordinates like the source artwork.
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)
    if let bg = p.background { ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size)) }

    // Sweep wedge: from the horizontal line (0°) up to 62° above it.
    ctx.setFillColor(p.sweep)
    ctx.move(to: c)
    ctx.addArc(center: c, radius: 378, startAngle: -62 * .pi / 180, endAngle: 0, clockwise: false)
    ctx.closePath(); ctx.fillPath()

    // Rings.
    for (r, col) in zip([378.0, 257.0, 137.0], p.ring) {
        ctx.setStrokeColor(col); ctx.setLineWidth(26)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
    // Sweep line.
    ctx.setStrokeColor(p.line); ctx.setLineWidth(13); ctx.setLineCap(.butt)
    ctx.move(to: c); ctx.addLine(to: CGPoint(x: 903, y: 512)); ctx.strokePath()

    func dot(_ x: CGFloat, _ y: CGFloat, outer: CGFloat, inner: CGFloat) {
        ctx.setFillColor(p.dotRing); ctx.fillEllipse(in: CGRect(x: x - outer, y: y - outer, width: 2 * outer, height: 2 * outer))
        ctx.setFillColor(p.dotFill); ctx.fillEllipse(in: CGRect(x: x - inner, y: y - inner, width: 2 * inner, height: 2 * inner))
    }
    dot(512, 512, outer: 62, inner: 40)
    dot(741, 318, outer: 30, inner: 18)
    dot(325, 619, outer: 30, inner: 18)
    dot(631, 840, outer: 30, inner: 18)

    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    precondition(CGImageDestinationFinalize(dest), "could not write \(url.path)")
    print("wrote", url.lastPathComponent)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])

// Dark: transparent background, bright radar so it reads on the system's dark backdrop.
draw(Palette(background: nil,
             ring: [rgb(0.55, 0.72, 1.0, 0.45), rgb(0.62, 0.78, 1.0, 0.70), rgb(0.80, 0.88, 1.0, 0.95)],
             sweep: rgb(0.35, 0.58, 1.0, 0.35),
             line: rgb(0.92, 0.95, 1.0),
             dotRing: rgb(0.92, 0.95, 1.0),
             dotFill: rgb(0.25, 0.52, 1.0)),
     to: out.appendingPathComponent("icon-dark-1024.png"))

// Tinted: grayscale on black; iOS maps brightness to the user's tint colour.
draw(Palette(background: gray(0),
             ring: [gray(0.45), gray(0.65), gray(0.85)],
             sweep: gray(0.30),
             line: gray(1),
             dotRing: gray(1),
             dotFill: gray(0.55)),
     to: out.appendingPathComponent("icon-tinted-1024.png"))
