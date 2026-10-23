import AppKit

// Renders the Stowaway app icon: menu bar items spilling out of the notch into
// a vertical list — the whole app in one picture.
let size: CGFloat = 1024
let inset: CGFloat = 100
let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let base = NSGraphicsContext(bitmapImageRep: rep)!
let cg = base.cgContext
cg.translateBy(x: 0, y: size)
cg.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Plate: mint-teal into deep indigo.
let squircle = NSBezierPath(roundedRect: plate, xRadius: plate.width * 0.225, yRadius: plate.width * 0.225)
NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(colors: [color(0x3FE0C5), color(0x2A8FBF), color(0x3A2A8C)],
           atLocations: [0, 0.5, 1], colorSpace: .sRGB)?.draw(in: plate, angle: -62)

// A soft light from the top-left, and the menu bar band itself.
// Radial over the whole plate, so it fades out instead of ending on an edge.
NSGradient(colors: [color(0xFFFFFF, 0.30), color(0xFFFFFF, 0.0)])?
    .draw(in: plate, relativeCenterPosition: NSPoint(x: -0.75, y: 0.85))
color(0xFFFFFF, 0.16).setFill()
CGRect(x: plate.minX, y: plate.minY, width: plate.width, height: 118).fill()

// The notch.
let notch = CGRect(x: size / 2 - 150, y: plate.minY, width: 300, height: 118)
let notchPath = NSBezierPath()
notchPath.move(to: CGPoint(x: notch.minX - 26, y: notch.minY))
notchPath.curve(to: CGPoint(x: notch.minX, y: notch.minY + 26),
                controlPoint1: CGPoint(x: notch.minX - 4, y: notch.minY), controlPoint2: CGPoint(x: notch.minX, y: notch.minY + 6))
notchPath.line(to: CGPoint(x: notch.minX, y: notch.maxY - 52))
notchPath.curve(to: CGPoint(x: notch.minX + 52, y: notch.maxY),
                controlPoint1: CGPoint(x: notch.minX, y: notch.maxY - 22), controlPoint2: CGPoint(x: notch.minX + 22, y: notch.maxY))
notchPath.line(to: CGPoint(x: notch.maxX - 52, y: notch.maxY))
notchPath.curve(to: CGPoint(x: notch.maxX, y: notch.maxY - 52),
                controlPoint1: CGPoint(x: notch.maxX - 22, y: notch.maxY), controlPoint2: CGPoint(x: notch.maxX, y: notch.maxY - 22))
notchPath.line(to: CGPoint(x: notch.maxX, y: notch.minY + 26))
notchPath.curve(to: CGPoint(x: notch.maxX + 26, y: notch.minY),
                controlPoint1: CGPoint(x: notch.maxX, y: notch.minY + 6), controlPoint2: CGPoint(x: notch.maxX + 4, y: notch.minY))
notchPath.close()
color(0x05060A).setFill()
notchPath.fill()

// Items cascading out of the notch: each pill a menu bar item, now in a list.
let pills: [(CGFloat, CGFloat, UInt32, CGFloat)] = [   // y, width, dot colour, opacity
    (300, 420, 0xFFA24C, 0.80),
    (440, 520, 0x8B7BFF, 0.94),
    (580, 520, 0x2FD8BC, 1.00),
]
for (y, width, dot, alpha) in pills {
    let rect = CGRect(x: size / 2 - width / 2, y: y, width: width, height: 108)
    let shadow = NSShadow()
    shadow.shadowColor = color(0x0A0A2A, 0.35)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color(0xFFFFFF, alpha).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 34, yRadius: 34).fill()
    NSGraphicsContext.restoreGraphicsState()

    color(dot, alpha).setFill()
    NSBezierPath(ovalIn: CGRect(x: rect.minX + 30, y: rect.midY - 30, width: 60, height: 60)).fill()
    color(0x2A2F45, 0.22 * alpha).setFill()
    NSBezierPath(roundedRect: CGRect(x: rect.minX + 116, y: rect.midY - 12, width: width - 176, height: 24),
                 xRadius: 12, yRadius: 12).fill()
}
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
