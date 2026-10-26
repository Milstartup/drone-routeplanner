// Draws the Veldvlucht app icon: a field with crop rows, a lawnmower flight path and a drone.
// Usage (in ios/): swift Scripts/AppIcon.swift Veldvlucht/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(dark: Bool) -> CGImage {
    let size = 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)

    // Background: a sunny field, lighter at the top left.
    let colors = dark ? [color(0x173A27), color(0x07170E)] : [color(0x4CD68A), color(0x0F6B3B)]
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [])

    // Crop rows, slightly turned.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512)
    ctx.rotate(by: -0.38)
    ctx.setFillColor(dark ? color(0xFFFFFF, 0.035) : color(0xFFFFFF, 0.09))
    var x = -900.0
    while x < 900 {
        ctx.fill(CGRect(x: x, y: -900, width: 46, height: 1800))
        x += 112
    }

    // The flight path: three lines across the field, like the planner makes them.
    let path = CGMutablePath()
    let legs: [CGFloat] = [-245, -75, 95]
    let low: CGFloat = 300
    let high: CGFloat = -240
    path.move(to: CGPoint(x: legs[0], y: low))
    path.addLine(to: CGPoint(x: legs[0], y: high))
    path.addArc(center: CGPoint(x: (legs[0] + legs[1]) / 2, y: high), radius: (legs[1] - legs[0]) / 2,
                startAngle: .pi, endAngle: 0, clockwise: false)
    path.addLine(to: CGPoint(x: legs[1], y: low))
    path.addArc(center: CGPoint(x: (legs[1] + legs[2]) / 2, y: low), radius: (legs[2] - legs[1]) / 2,
                startAngle: .pi, endAngle: 0, clockwise: true)
    path.addLine(to: CGPoint(x: legs[2], y: -130))
    let pathColor = dark ? color(0x5BE59A) : color(0xFFFFFF)
    ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: color(0x03321A, dark ? 0.6 : 0.35))
    ctx.addPath(path)
    ctx.setStrokeColor(pathColor)
    ctx.setLineWidth(30)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // Photo points along the lines.
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setFillColor(dark ? color(0x07170E) : color(0x0F6B3B))
    for leg in legs {
        var y = leg == legs[2] ? high + 40 + 62 * 4 : high + 40
        while y <= low - 30 {
            ctx.fillEllipse(in: CGRect(x: leg - 6, y: y - 6, width: 12, height: 12))
            y += 62
        }
    }

    // The drone at the end of the path, heading on.
    let center = CGPoint(x: legs[2], y: -190)
    ctx.translateBy(x: center.x, y: center.y)
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 26, color: color(0x03321A, dark ? 0.7 : 0.4))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    let droneColor = dark ? color(0x5BE59A) : color(0xFFFFFF)
    ctx.setStrokeColor(droneColor)
    ctx.setFillColor(droneColor)
    let arm: CGFloat = 112
    ctx.setLineWidth(30)
    ctx.setLineCap(.round)
    for (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
        ctx.move(to: .zero)
        ctx.addLine(to: CGPoint(x: dx * arm * 0.72, y: dy * arm * 0.72))
        ctx.strokePath()
        let rotor = CGRect(x: dx * arm * 0.72 - 58, y: dy * arm * 0.72 - 58, width: 116, height: 116)
        ctx.setLineWidth(20)
        ctx.strokeEllipse(in: rotor.insetBy(dx: 10, dy: 10))
        ctx.setLineWidth(30)
    }
    let body = CGPath(roundedRect: CGRect(x: -58, y: -66, width: 116, height: 132), cornerWidth: 44, cornerHeight: 44, transform: nil)
    ctx.addPath(body)
    ctx.fillPath()
    // The camera at the front.
    ctx.setFillColor(dark ? color(0x07170E) : color(0x0F6B3B))
    ctx.fillEllipse(in: CGRect(x: -22, y: -60, width: 44, height: 44))
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func save(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
save(drawIcon(dark: false), to: folder.appendingPathComponent("AppIcon.png"))
save(drawIcon(dark: true), to: folder.appendingPathComponent("AppIcon-dark.png"))
print("ok")
