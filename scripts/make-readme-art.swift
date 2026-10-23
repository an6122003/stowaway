import AppKit
import CoreImage

// Renders the README artwork into docs/images. Everything is drawn natively —
// real SF Symbols, the system font — with illustrative demo data rather than a
// real machine's apps, so the images carry nobody's personal setup.
//
//   swiftc -O -o /tmp/art scripts/make-readme-art.swift && /tmp/art docs/images Resources/AppIcon.icns

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images"
let iconPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/AppIcon.icns"
try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

// MARK: - Basics

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

enum Brand {
    static let mint = hex(0x3FE0C5)
    static let teal = hex(0x2BB5A8)
    static let indigo = hex(0x4B3BB8)
    static let selection = hex(0x2F6BF0)
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

/// A 2× bitmap with a flipped (y-down) drawing context.
final class Canvas {
    let size: CGSize
    let rep: NSBitmapImageRep

    init(_ width: CGFloat, _ height: CGFloat, scale: CGFloat = 2) {
        size = CGSize(width: width, height: height)
        rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: width, height: height)
    }

    func draw(_ body: (CGRect) -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let base = NSGraphicsContext(bitmapImageRep: rep)!
        let cg = base.cgContext
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        body(CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
    }

    func save(_ name: String) {
        let path = (outputDirectory as NSString).appendingPathComponent(name)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}

func drawImage(_ image: NSImage, in rect: CGRect, alpha: CGFloat = 1) {
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
}

@discardableResult
func text(_ string: String, at point: CGPoint, font: NSFont, color: NSColor,
          kern: CGFloat = 0, width: CGFloat? = nil, alignment: NSTextAlignment = .left) -> CGSize {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    let attributed = NSAttributedString(string: string, attributes: [
        .font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: paragraph,
    ])
    let measured = attributed.size()
    if let width {
        attributed.draw(in: CGRect(x: point.x, y: point.y, width: width, height: measured.height + 4))
    } else {
        attributed.draw(at: point)
    }
    return measured
}

func textSize(_ string: String, font: NSFont) -> CGSize {
    NSAttributedString(string: string, attributes: [.font: font]).size()
}

func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
}

func drawSymbol(_ name: String, center: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular,
                color: NSColor = .white, alpha: CGFloat = 1) {
    guard let image = symbol(name, size: size, weight: weight, color: color) else { return }
    let s = image.size
    drawImage(image, in: CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height), alpha: alpha)
}

func shadowed(_ color: NSColor, blur: CGFloat, offset: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: -offset)
    shadow.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Wallpaper

/// A dark aurora, rendered once per image so the glass panels can blur it.
func wallpaper(_ size: CGSize, scale: CGFloat = 2, variant: Int = 0) -> NSImage {
    let width = Int(size.width * scale), height = Int(size.height * scale)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                       space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let w = CGFloat(width), h = CGFloat(height)

    let base = CGGradient(colorsSpace: space, colors: [hex(0x0A0F2C).cgColor, hex(0x170F3D).cgColor, hex(0x0B1A33).cgColor] as CFArray,
                          locations: [0, 0.55, 1])!
    cg.drawLinearGradient(base, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])

    let blobs: [(CGFloat, CGFloat, CGFloat, UInt32, CGFloat)] = variant == 0
        ? [(0.82, 0.18, 0.55, 0x22D3B6, 0.55), (0.18, 0.35, 0.60, 0x6D4CFF, 0.50),
           (0.55, 0.95, 0.45, 0x3A7BFF, 0.40), (0.95, 0.85, 0.40, 0xFF5D9E, 0.22)]
        : [(0.25, 0.20, 0.55, 0x22D3B6, 0.45), (0.80, 0.40, 0.65, 0x6D4CFF, 0.50),
           (0.45, 0.90, 0.50, 0x3A7BFF, 0.35), (0.05, 0.85, 0.40, 0xFF7A59, 0.18)]
    for (fx, fy, fr, color, alpha) in blobs {
        let center = CGPoint(x: w * fx, y: h * (1 - fy))
        let radius = max(w, h) * fr
        let gradient = CGGradient(colorsSpace: space, colors: [hex(color, alpha).cgColor, hex(color, 0).cgColor] as CFArray,
                                  locations: [0, 1])!
        cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
    return NSImage(cgImage: cg.makeImage()!, size: size)
}

func blurred(_ image: NSImage, radius: CGFloat) -> NSImage {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
    let input = CIImage(cgImage: cgImage)
    let output = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
    let context = CIContext()
    guard let result = context.createCGImage(output, from: input.extent) else { return image }
    return NSImage(cgImage: result, size: image.size)
}

/// Frosted glass: the blurred backdrop clipped to a shape, then tinted.
func glass(_ path: NSBezierPath, backdrop: NSImage, canvas: CGRect, tint: NSColor, border: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    drawImage(backdrop, in: canvas)
    tint.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    border.setStroke()
    path.lineWidth = 1
    path.stroke()
}

// MARK: - Menu bar model

/// Geometry measured on a real notched MacBook: a 1710pt-wide bar, 33pt tall,
/// with the notch spanning 763–948.
enum Bar {
    static let width: CGFloat = 1710
    static let height: CGFloat = 33
    static let notch: ClosedRange<CGFloat> = 763...948
}

struct Item {
    enum Kind { case symbol(String), input(String), clock(String), stowaway }
    let kind: Kind
    let width: CGFloat
    var isSystem = false
}

let thirdParty: [Item] = [
    Item(kind: .symbol("bubble.left.and.bubble.right.fill"), width: 34),
    Item(kind: .symbol("shippingbox.fill"), width: 30),
    Item(kind: .symbol("cup.and.saucer.fill"), width: 30),
    Item(kind: .symbol("icloud.fill"), width: 32),
    Item(kind: .symbol("paperplane.fill"), width: 28),
    Item(kind: .symbol("character.bubble.fill"), width: 30),
    Item(kind: .symbol("sparkle"), width: 26),
    Item(kind: .symbol("network"), width: 28),
    Item(kind: .symbol("gauge.with.dots.needle.67percent"), width: 30),
    Item(kind: .symbol("lock.shield.fill"), width: 28),
    Item(kind: .symbol("waveform"), width: 28),
    Item(kind: .symbol("camera.aperture"), width: 28),
    Item(kind: .symbol("doc.on.clipboard.fill"), width: 28),
].reversed()   // listed left to right; packing works right to left

let transientSystem: [Item] = [
    Item(kind: .symbol("moon.fill"), width: 26, isSystem: true),
    Item(kind: .symbol("play.circle"), width: 26, isSystem: true),
]
let coreSystem: [Item] = [   // right to left
    Item(kind: .clock("Fri 23 Oct  14:13"), width: 124, isSystem: true),
    Item(kind: .symbol("switch.2"), width: 32, isSystem: true),
    Item(kind: .symbol("magnifyingglass"), width: 32, isSystem: true),
    Item(kind: .symbol("battery.75percent"), width: 36, isSystem: true),
    Item(kind: .symbol("wifi"), width: 30, isSystem: true),
    Item(kind: .input("A"), width: 36, isSystem: true),
]

/// Packs items from the right edge leftward, the way macOS does.
func pack(_ items: [Item], from right: CGFloat = Bar.width - 6, gap: CGFloat = 6) -> [(Item, CGFloat)] {
    var x = right
    return items.map { item in
        x -= item.width
        defer { x -= gap }
        return (item, x)
    }
}

struct BarScene {
    var placed: [(Item, CGFloat)]
    var ghosts: [(Item, CGFloat)] = []
    var spacer: ClosedRange<CGFloat>? = nil
    var spacerExpanded = false
    var glowStowaway = false
}

/// Draws a slice of the menu bar (model x range `crop`) into `dest`.
func drawBar(_ scene: BarScene, dest: CGRect, crop: ClosedRange<CGFloat>, leftMenus: Bool = true) {
    let k = dest.width / (crop.upperBound - crop.lowerBound)
    func x(_ modelX: CGFloat) -> CGFloat { dest.minX + (modelX - crop.lowerBound) * k }
    let barHeight = Bar.height * k
    let midY = dest.minY + barHeight / 2

    // macOS 26 draws status items straight onto the wallpaper; a faint shade
    // keeps them legible.
    NSGradient(colors: [hex(0x000000, 0.34), hex(0x000000, 0)])?
        .draw(in: CGRect(x: dest.minX, y: dest.minY, width: dest.width, height: barHeight * 1.6), angle: 90)

    if leftMenus {
        let menuFont = NSFont.systemFont(ofSize: 13 * k, weight: .regular)
        let boldFont = NSFont.systemFont(ofSize: 13 * k, weight: .bold)
        var cursor: CGFloat = 400
        let appleFont = NSFont.systemFont(ofSize: 15 * k, weight: .regular)
        if x(cursor) >= dest.minX - 4 {
            text("\u{F8FF}", at: CGPoint(x: x(cursor), y: midY - textSize("\u{F8FF}", font: appleFont).height / 2), font: appleFont, color: .white)
        }
        cursor += 34
        for (index, title) in ["Finder", "File", "Edit", "View", "Go", "Window", "Help"].enumerated() {
            let font = index == 0 ? boldFont : menuFont
            let size = textSize(title, font: font)
            if x(cursor) >= dest.minX - 4, cursor + size.width / k < Bar.notch.lowerBound - 10 {
                text(title, at: CGPoint(x: x(cursor), y: midY - size.height / 2), font: font, color: .white)
            }
            cursor += size.width / k + 20
        }
    }

    for (item, modelX) in scene.placed {
        guard modelX + item.width > crop.lowerBound else { continue }
        drawGlyph(item, center: CGPoint(x: x(modelX + item.width / 2), y: midY), k: k, alpha: 1)
        if case .stowaway = item.kind, scene.glowStowaway {
            let ring = CGRect(x: x(modelX) - 1, y: dest.minY + 3 * k, width: item.width * k + 2, height: barHeight - 6 * k)
            shadowed(Brand.mint.withAlphaComponent(0.9), blur: 14, offset: 0) {
                Brand.mint.withAlphaComponent(0.22).setFill()
                NSBezierPath(roundedRect: ring, xRadius: 7 * k, yRadius: 7 * k).fill()
            }
            Brand.mint.withAlphaComponent(0.9).setStroke()
            let outline = NSBezierPath(roundedRect: ring, xRadius: 7 * k, yRadius: 7 * k)
            outline.lineWidth = 1.2
            outline.stroke()
        }
    }

    if let spacer = scene.spacer {
        let rect = CGRect(x: x(spacer.lowerBound), y: dest.minY + 4 * k,
                          width: (spacer.upperBound - spacer.lowerBound) * k, height: barHeight - 8 * k)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6 * k, yRadius: 6 * k)
        shadowed(Brand.mint.withAlphaComponent(0.8), blur: 16, offset: 0) {
            Brand.mint.withAlphaComponent(scene.spacerExpanded ? 0.18 : 0.55).setFill()
            path.fill()
        }
        Brand.mint.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 1.4
        path.stroke()
        if scene.spacerExpanded {
            var arrowX = rect.minX + 26
            while arrowX < rect.maxX - 20 {
                drawSymbol("chevron.left.2", center: CGPoint(x: arrowX, y: midY), size: 12 * k, weight: .bold,
                           color: Brand.mint, alpha: 0.85)
                arrowX += 46 * k
            }
        }
    }

    // The notch is drawn last: anything beneath it is exactly what macOS hides.
    let notch = CGRect(x: x(Bar.notch.lowerBound), y: dest.minY,
                       width: (Bar.notch.upperBound - Bar.notch.lowerBound) * k, height: barHeight)
    hex(0x020204).setFill()
    let radius = 9 * k
    let path = NSBezierPath()
    path.move(to: CGPoint(x: notch.minX, y: notch.minY))
    path.line(to: CGPoint(x: notch.maxX, y: notch.minY))
    path.line(to: CGPoint(x: notch.maxX, y: notch.maxY - radius))
    path.curve(to: CGPoint(x: notch.maxX - radius, y: notch.maxY),
               controlPoint1: CGPoint(x: notch.maxX, y: notch.maxY - radius * 0.45),
               controlPoint2: CGPoint(x: notch.maxX - radius * 0.45, y: notch.maxY))
    path.line(to: CGPoint(x: notch.minX + radius, y: notch.maxY))
    path.curve(to: CGPoint(x: notch.minX, y: notch.maxY - radius),
               controlPoint1: CGPoint(x: notch.minX + radius * 0.45, y: notch.maxY),
               controlPoint2: CGPoint(x: notch.minX, y: notch.maxY - radius * 0.45))
    path.close()
    path.fill()

    // Lost icons, shown as a row of ghosts on the notch: present, but with
    // nowhere to be drawn. Laid out evenly rather than at their packed
    // positions, so every lost icon is shown and the count always matches.
    let pitch = 32 * k
    let capacity = Int((notch.width - 10 * k) / pitch)
    for (index, (item, _)) in scene.ghosts.prefix(capacity).enumerated() {
        let center = CGPoint(x: notch.maxX - 8 * k - pitch / 2 - CGFloat(index) * pitch, y: midY)
        let slot = CGRect(x: center.x - 11 * k, y: midY - 9 * k, width: 22 * k, height: 18 * k)
        let dashed = NSBezierPath(roundedRect: slot, xRadius: 5 * k, yRadius: 5 * k)
        dashed.setLineDash([3, 3], count: 2, phase: 0)
        dashed.lineWidth = 1
        hex(0xFF6B6B, 0.75).setStroke()
        dashed.stroke()
        drawGlyph(item, center: center, k: k * 0.85, alpha: 0.32)
    }
}

func drawGlyph(_ item: Item, center: CGPoint, k: CGFloat, alpha: CGFloat) {
    switch item.kind {
    case .symbol(let name):
        drawSymbol(name, center: center, size: 14.5 * k, weight: .medium, alpha: alpha)
    case .stowaway:
        drawSymbol("ellipsis.rectangle", center: center, size: 15 * k, weight: .medium, alpha: alpha)
    case .input(let letter):
        let badge = CGRect(x: center.x - 11 * k, y: center.y - 8.5 * k, width: 22 * k, height: 17 * k)
        hex(0xFFFFFF, 0.92 * alpha).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 4.5 * k, yRadius: 4.5 * k).fill()
        let font = NSFont.systemFont(ofSize: 11 * k, weight: .bold)
        let size = textSize(letter, font: font)
        text(letter, at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), font: font,
             color: hex(0x15151A, alpha))
    case .clock(let string):
        let font = NSFont.systemFont(ofSize: 13 * k, weight: .medium)
        let size = textSize(string, font: font)
        text(string, at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), font: font,
             color: hex(0xFFFFFF, alpha))
    }
}

// MARK: - Scenes

let stowawayItem = Item(kind: .stowaway, width: 32)

/// The overflowing bar: everything packed, the leftmost icons lost under the notch.
func overflowingScene() -> BarScene {
    let packed = pack(coreSystem + transientSystem + Array(thirdParty))
    let visible = packed.filter { $0.1 >= Bar.notch.upperBound + 2 }
    let lost = packed.filter { $0.1 < Bar.notch.upperBound + 2 }
    return BarScene(placed: visible, ghosts: lost)
}

/// Stowaway's spacer pinned between the two clusters, nothing hidden yet.
func pinnedScene() -> BarScene {
    let right = Array(coreSystem.prefix(2)) + [stowawayItem] + Array(coreSystem.dropFirst(2))
    let system = pack(right + transientSystem)
    let systemLeft = system.last!.1
    let spacerRange = (systemLeft - 22)...(systemLeft - 8)
    let rest = pack(Array(thirdParty), from: spacerRange.lowerBound - 6)
    let visible = (system + rest).filter { $0.1 >= Bar.notch.upperBound + 2 }
    let lost = (system + rest).filter { $0.1 < Bar.notch.upperBound + 2 }
    return BarScene(placed: visible, ghosts: lost, spacer: spacerRange)
}

/// After: the spacer widened, third-party icons pushed behind the notch,
/// Apple's indicators exactly where they were.
func tidyScene(showSpacer: Bool) -> BarScene {
    let right = Array(coreSystem.prefix(2)) + [stowawayItem] + Array(coreSystem.dropFirst(2))
    let system = pack(right)
    let systemLeft = system.last!.1
    let spacerRange = (Bar.notch.upperBound + 2)...(systemLeft - 8)
    let pushed = pack(transientSystem + Array(thirdParty), from: Bar.notch.upperBound - 4)
    return BarScene(placed: system, ghosts: showSpacer ? pushed : [], spacer: showSpacer ? spacerRange : nil,
                    spacerExpanded: true, glowStowaway: !showSpacer)
}

// MARK: - The list panel

struct Row {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    let colors: [UInt32]
    var glyph: UInt32 = 0xFFFFFF
    var selected = false
}

let demoRows: [Row] = [
    Row(title: "Team Chat", symbol: "bubble.left.and.bubble.right.fill", colors: [0x7C83FF, 0x5249E0]),
    Row(title: "Containers", symbol: "shippingbox.fill", colors: [0x3AA0FF, 0x1C6FE0]),
    Row(title: "Sleeps on lid close", subtitle: "SleepGuard", symbol: "cup.and.saucer.fill", colors: [0x6A5CFF, 0x3D2FB8]),
    Row(title: "Cloud Drive", symbol: "icloud.fill", colors: [0x5FC4FF, 0x2A8FE6], selected: true),
    Row(title: "Messenger", symbol: "paperplane.fill", colors: [0x4FD2FF, 0x1AA2E0]),
    Row(title: "Translator", symbol: "character.bubble.fill", colors: [0x6BD66B, 0x2E9E4A]),
    Row(title: "Assistant", symbol: "sparkle", colors: [0xFFB15C, 0xF0703A]),
    Row(title: "Tailnet", symbol: "network", colors: [0x5A6275, 0x2E3442]),
    Row(title: "Running unrestricted", subtitle: "ThrottleWatch", symbol: "gauge.with.dots.needle.67percent", colors: [0xFF8A5C, 0xD9413A]),
    Row(title: "Now Playing", subtitle: "Control Center", symbol: "play.fill", colors: [0xF2F3F7, 0xD9DBE3], glyph: 0x3A7BFF),
    Row(title: "Focus", subtitle: "Control Center", symbol: "moon.fill", colors: [0xF2F3F7, 0xD9DBE3], glyph: 0x6D4CFF),
    Row(title: "Wi‑Fi, connected", subtitle: "Control Center", symbol: "wifi", colors: [0xF2F3F7, 0xD9DBE3], glyph: 0x2F6BF0),
    Row(title: "Battery", subtitle: "Control Center", symbol: "battery.100percent", colors: [0xF2F3F7, 0xD9DBE3], glyph: 0x2BB56A),
    Row(title: "Search", subtitle: "Spotlight", symbol: "magnifyingglass", colors: [0x5AA9FF, 0x2F6BF0]),
    Row(title: "Clock", subtitle: "Control Center", symbol: "clock.fill", colors: [0xF2F3F7, 0xD9DBE3], glyph: 0x3A3F4F),
]

func rowHeight(_ row: Row) -> CGFloat { row.subtitle == nil ? 26 : 38 }

func panelHeight(rows: [Row]) -> CGFloat {
    44 + rows.map(rowHeight).reduce(0, +) + 12 + 3 * 26 + 10
}

func drawPanel(origin: CGPoint, width: CGFloat, rows: [Row], header: String,
               backdrop: NSImage, canvas: CGRect) -> CGRect {
    let height = panelHeight(rows: rows)
    let rect = CGRect(x: origin.x, y: origin.y, width: width, height: height)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
    shadowed(hex(0x000000, 0.55), blur: 40, offset: 18) {
        hex(0x000000, 0.01).setFill()
        shape.fill()
    }
    glass(shape, backdrop: backdrop, canvas: canvas, tint: hex(0x1B1F2C, 0.66), border: hex(0xFFFFFF, 0.14))

    var y = rect.minY + 13
    text(header, at: CGPoint(x: rect.minX + 18, y: y), font: .systemFont(ofSize: 12.5, weight: .medium),
         color: hex(0xFFFFFF, 0.46))
    y += 23
    hex(0xFFFFFF, 0.10).setFill()
    CGRect(x: rect.minX + 14, y: y, width: width - 28, height: 1).fill()
    y += 6

    for row in rows {
        let height = rowHeight(row)
        if row.selected {
            Brand.selection.setFill()
            NSBezierPath(roundedRect: CGRect(x: rect.minX + 6, y: y, width: width - 12, height: height),
                         xRadius: 7, yRadius: 7).fill()
        }
        let tile = CGRect(x: rect.minX + 16, y: y + (height - 18) / 2, width: 18, height: 18)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: 4.6, yRadius: 4.6)
        NSGradient(colors: row.colors.map { hex($0) })?.draw(in: tilePath, angle: -90)
        drawSymbol(row.symbol, center: CGPoint(x: tile.midX, y: tile.midY), size: 9.5, weight: .semibold, color: hex(row.glyph))

        let titleFont = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        if let subtitle = row.subtitle {
            text(row.title, at: CGPoint(x: rect.minX + 44, y: y + 3), font: titleFont, color: .white)
            text(subtitle, at: CGPoint(x: rect.minX + 44, y: y + 20), font: .systemFont(ofSize: 11.5),
                 color: row.selected ? hex(0xFFFFFF, 0.82) : hex(0xFFFFFF, 0.46))
        } else {
            text(row.title, at: CGPoint(x: rect.minX + 44, y: y + (height - 17) / 2), font: titleFont, color: .white)
        }
        y += height
    }

    y += 6
    hex(0xFFFFFF, 0.10).setFill()
    CGRect(x: rect.minX + 14, y: y, width: width - 28, height: 1).fill()
    y += 6
    for (title, shortcut) in [("Show Other Icons in the Bar", "⌃⌥⌘B"), ("Settings…", ""), ("Quit Stowaway", "⌘Q")] {
        text(title, at: CGPoint(x: rect.minX + 44, y: y + 4), font: .systemFont(ofSize: 13.5), color: .white)
        if !shortcut.isEmpty {
            text(shortcut, at: CGPoint(x: rect.maxX - 18 - 80, y: y + 5), font: .systemFont(ofSize: 12.5),
                 color: hex(0xFFFFFF, 0.42), width: 80, alignment: .right)
        }
        y += 26
    }
    return rect
}

// MARK: - Shared bits

func pill(_ symbolName: String, _ label: String, at point: CGPoint, tint: NSColor) {
    let font = rounded(13, .semibold)
    let size = textSize(label, font: font)
    let rect = CGRect(x: point.x, y: point.y, width: size.width + 40, height: 26)
    tint.withAlphaComponent(0.20).setFill()
    let path = NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13)
    path.fill()
    tint.withAlphaComponent(0.55).setStroke()
    path.lineWidth = 1
    path.stroke()
    drawSymbol(symbolName, center: CGPoint(x: rect.minX + 15, y: rect.midY), size: 11, weight: .bold, color: tint)
    text(label, at: CGPoint(x: rect.minX + 27, y: rect.midY - size.height / 2), font: font, color: .white)
}

func caps(_ label: String, at point: CGPoint, color: NSColor = hex(0xFFFFFF, 0.62)) {
    text(label, at: point, font: rounded(12, .heavy), color: color, kern: 2.4)
}

/// A rounded slice of screen-top: wallpaper with the bar along its top edge.
func screenCard(_ rect: CGRect, scene: BarScene, crop: ClosedRange<CGFloat>, variant: Int = 0) {
    let shape = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
    shadowed(hex(0x000000, 0.45), blur: 30, offset: 12) {
        hex(0x000000, 0.01).setFill()
        shape.fill()
    }
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    drawImage(wallpaper(rect.size, variant: variant), in: rect)
    drawBar(scene, dest: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 60), crop: crop)
    NSGraphicsContext.restoreGraphicsState()
    hex(0xFFFFFF, 0.10).setStroke()
    shape.lineWidth = 1
    shape.stroke()
}

let appIcon = NSImage(contentsOfFile: iconPath)

struct Copy {
    let suffix: String
    let taglineTop: String
    let taglineBottom: String
    let chips: [String]
    let before: String
    let after: String
    let unreachable: (Int) -> String
    let reachable: (Int) -> String
}

let copies = [
    Copy(suffix: "en",
         taglineTop: "Every menu bar icon —", taglineBottom: "even the ones behind the notch.",
         chips: ["No root", "No screen recording", "Native Swift"],
         before: "BEFORE", after: "AFTER",
         unreachable: { "\($0) unreachable" }, reachable: { "all \($0) one click away" }),
    Copy(suffix: "vi",
         taglineTop: "Mọi biểu tượng trên thanh menu —", taglineBottom: "kể cả những cái bị tai thỏ che mất.",
         chips: ["Không cần root", "Không ghi màn hình", "Swift thuần"],
         before: "TRƯỚC", after: "SAU",
         unreachable: { "\($0) biểu tượng không thể mở" }, reachable: { "cả \($0), chỉ một cú nhấp" }),
    Copy(suffix: "zh",
         taglineTop: "每一个菜单栏图标——", taglineBottom: "包括被刘海挡住的那些。",
         chips: ["无需 root", "无需录屏权限", "原生 Swift"],
         before: "之前", after: "之后",
         unreachable: { "\($0) 个无法点击" }, reachable: { "全部 \($0) 个，一键直达" }),
]

// MARK: - 1. Hero

/// The hero's list: the nine apps Stowaway pushed away plus two Apple
/// indicators still on show — so its header can say exactly that.
let heroRows = Array(demoRows.prefix(9)) + demoRows.filter { $0.title.hasPrefix("Wi") || $0.title == "Battery" }

for copy in copies {
    let canvas = Canvas(1280, 640)
    canvas.draw { bounds in
        let paper = wallpaper(bounds.size)
        drawImage(paper, in: bounds)
        let frosted = blurred(paper, radius: 22)

        drawBar(tidyScene(showSpacer: false), dest: CGRect(x: 0, y: 0, width: bounds.width, height: 40), crop: 0...Bar.width)
        _ = drawPanel(origin: CGPoint(x: 914, y: 36), width: 318, rows: heroRows,
                      header: "11 items · 9 with no room in the bar", backdrop: frosted, canvas: bounds)

        if let appIcon { drawImage(appIcon, in: CGRect(x: 64, y: 150, width: 132, height: 132)) }
        text("Stowaway", at: CGPoint(x: 80, y: 290), font: rounded(84, .bold), color: .white, kern: -1.5)
        text(copy.taglineTop, at: CGPoint(x: 84, y: 396), font: rounded(28, .medium), color: hex(0xFFFFFF, 0.86))
        text(copy.taglineBottom, at: CGPoint(x: 84, y: 432), font: rounded(28, .medium), color: hex(0xFFFFFF, 0.86))

        var chipX: CGFloat = 84
        for (glyph, label) in zip(["lock.open.fill", "eye.slash.fill", "bolt.fill"], copy.chips) {
            pill(glyph, label, at: CGPoint(x: chipX, y: 500), tint: Brand.mint)
            chipX += textSize(label, font: rounded(13, .semibold)).width + 52
        }
    }
    canvas.save("hero-\(copy.suffix).png")
}

// MARK: - 2. Before / after

for copy in copies {
    let canvas = Canvas(1280, 380)
    canvas.draw { bounds in
        hex(0x0B0E1E).setFill()
        bounds.fill()
        let crop: ClosedRange<CGFloat> = 420...Bar.width
        let labelFont = rounded(12, .heavy)

        let lost = overflowingScene().ghosts.count
        let before = CGRect(x: 32, y: 28, width: bounds.width - 64, height: 150)
        screenCard(before, scene: overflowingScene(), crop: crop)
        caps(copy.before, at: CGPoint(x: before.minX + 26, y: before.maxY - 40))
        let beforeWidth = textSize(copy.before, font: labelFont).width + CGFloat(copy.before.count) * 2.4
        pill("eye.slash.fill", copy.unreachable(lost), at: CGPoint(x: before.minX + 44 + beforeWidth, y: before.maxY - 45),
             tint: hex(0xFF6B6B))

        let after = CGRect(x: 32, y: 202, width: bounds.width - 64, height: 150)
        screenCard(after, scene: tidyScene(showSpacer: false), crop: crop, variant: 1)
        caps(copy.after, at: CGPoint(x: after.minX + 26, y: after.maxY - 40))
        let afterWidth = textSize(copy.after, font: labelFont).width + CGFloat(copy.after.count) * 2.4
        pill("checkmark", copy.reachable(demoRows.count), at: CGPoint(x: after.minX + 44 + afterWidth, y: after.maxY - 45),
             tint: Brand.mint)
    }
    canvas.save("before-after-\(copy.suffix).png")
}

// MARK: - 3. The list

do {
    let canvas = Canvas(760, 760)
    canvas.draw { bounds in
        let paper = wallpaper(bounds.size, variant: 1)
        drawImage(paper, in: bounds)
        let frosted = blurred(paper, radius: 22)
        drawBar(tidyScene(showSpacer: false), dest: CGRect(x: 0, y: 0, width: bounds.width, height: 50),
                crop: 1100...Bar.width, leftMenus: false)
        let width: CGFloat = 330
        _ = drawPanel(origin: CGPoint(x: (bounds.width - width) / 2 + 40, y: 58), width: width, rows: demoRows,
                      header: "15 items · 11 with no room in the bar", backdrop: frosted, canvas: bounds)
    }
    canvas.save("list.png")
}

// MARK: - 4. How it works

do {
    let canvas = Canvas(1280, 476)
    canvas.draw { bounds in
        hex(0x0B0E1E).setFill()
        bounds.fill()
        let crop: ClosedRange<CGFloat> = 640...Bar.width
        let scenes = [overflowingScene(), pinnedScene(), tidyScene(showSpacer: true)]
        let pitch: CGFloat = 148
        let cardHeight: CGFloat = 124

        // The stepper's spine, behind the badges.
        let spine = CGRect(x: 69, y: 28 + cardHeight / 2, width: 4, height: pitch * 2)
        NSGradient(colors: [Brand.mint.withAlphaComponent(0.7), Brand.indigo.withAlphaComponent(0.7)])?
            .draw(in: NSBezierPath(roundedRect: spine, xRadius: 2, yRadius: 2), angle: -90)

        for (index, scene) in scenes.enumerated() {
            let card = CGRect(x: 120, y: 28 + CGFloat(index) * pitch, width: bounds.width - 152, height: cardHeight)
            screenCard(card, scene: scene, crop: crop, variant: index % 2)

            let badge = CGRect(x: 45, y: card.midY - 26, width: 52, height: 52)
            shadowed(hex(0x000000, 0.5), blur: 12, offset: 4) {
                NSGradient(colors: [Brand.mint, Brand.indigo])?.draw(in: NSBezierPath(ovalIn: badge), angle: -45)
            }
            let number = "\(index + 1)"
            let font = rounded(26, .heavy)
            let size = textSize(number, font: font)
            text(number, at: CGPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), font: font, color: .white)
        }
    }
    canvas.save("how-it-works.png")
}

// MARK: - 5. Icon

if let appIcon {
    let canvas = Canvas(256, 256, scale: 1)
    canvas.draw { bounds in drawImage(appIcon, in: bounds) }
    canvas.save("icon.png")
}
