// Draws the app icon and writes a 1024×1024 PNG.  usage: swift scripts/make-icon.swift out.png
import AppKit

let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}
func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
}

// background: the standard macOS rounded square (824 pt inside a 1024 pt canvas)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
ctx.drawLinearGradient(gradient([color(0x2c3648), color(0x0e1219)]),
                       start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
// warm glow rising from the bulb
ctx.drawRadialGradient(gradient([color(0xff5a1f, 0.55), color(0xff5a1f, 0)]),
                       startCenter: CGPoint(x: 512, y: 330), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 330), endRadius: 430, options: [])
ctx.restoreGState()

// thermometer: a stem with a round bulb at the bottom
let bulb = CGPoint(x: 512, y: 345)
func thermometer(stemWidth: CGFloat, bulbRadius: CGFloat, top: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.addRoundedRect(in: CGRect(x: bulb.x - stemWidth / 2, y: bulb.y, width: stemWidth, height: top - bulb.y),
                     cornerWidth: stemWidth / 2, cornerHeight: stemWidth / 2)
    p.addEllipse(in: CGRect(x: bulb.x - bulbRadius, y: bulb.y - bulbRadius, width: bulbRadius * 2, height: bulbRadius * 2))
    return p
}

ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x000000, 0.45))
ctx.addPath(thermometer(stemWidth: 132, bulbRadius: 128, top: 800))
ctx.setFillColor(color(0xf4f6fa))
ctx.fillPath(using: .winding)
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// empty part of the tube
ctx.addPath(thermometer(stemWidth: 60, bulbRadius: 86, top: 764))
ctx.setFillColor(color(0xd3d9e3))
ctx.fillPath(using: .winding)

// the liquid, two thirds up
ctx.saveGState()
ctx.addPath(thermometer(stemWidth: 60, bulbRadius: 86, top: 640))
ctx.clip(using: .winding)
ctx.drawLinearGradient(gradient([color(0xff9a2e), color(0xf0342b)]),
                       start: CGPoint(x: 512, y: 640), end: CGPoint(x: 512, y: 260), options: [.drawsAfterEndLocation])
ctx.restoreGState()

// scale marks
ctx.setFillColor(color(0xf4f6fa, 0.9))
for (i, y) in [730.0, 640, 550].enumerated() {
    let w = i == 1 ? 86.0 : 56.0
    ctx.addPath(CGPath(roundedRect: CGRect(x: 616, y: y - 11, width: w, height: 22), cornerWidth: 11, cornerHeight: 11, transform: nil))
}
ctx.fillPath()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
