// SPDX-License-Identifier: GPL-3.0-or-later
//
// Draws the disk image window background (1x and 2x) and a preview with the icons placed,
// so the layout can be checked without opening Finder.
//
//   swift scripts/dmg-background.swift <output-dir> [path/to/Spaceroom.app]
//
// Layout (points, top-left origin) must match the positions in make-dmg.sh.

import AppKit

let size = NSSize(width: 660, height: 500)
let appSlot = NSPoint(x: 180, y: 185)
let applicationsSlot = NSPoint(x: 480, y: 185)
let readMeSlot = NSPoint(x: 590, y: 412)
let iconSize: CGFloat = 112

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func radialGlow(center: NSPoint, radius: CGFloat, color: NSColor) {
    let gradient = NSGradient(colors: [color, color.withAlphaComponent(0)])!
    gradient.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

/// Deterministic film grain so the gradient doesn't band.
func grain(in rect: NSRect, scale: CGFloat) {
    var seed: UInt64 = 0x5BACE_0000
    func next() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) & 0xFFFF) / 65535
    }
    let count = Int(rect.width * rect.height / 9)
    for _ in 0..<count {
        let point = NSPoint(x: next() * rect.width, y: next() * rect.height)
        let light = next() > 0.5
        (light ? NSColor.white : NSColor.black).withAlphaComponent(0.035).setFill()
        NSRect(x: point.x, y: point.y, width: 1 / scale, height: 1 / scale).fill()
    }
}

func drawBackground(scale: CGFloat) {
    let rect = NSRect(origin: .zero, size: size)
    NSGradient(colors: [color(0x33246A), color(0x1C1240), color(0x0E0822)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: rect, angle: -90)
    radialGlow(center: NSPoint(x: 90, y: 40), radius: 330, color: color(0x8B6BE8, 0.55))
    radialGlow(center: NSPoint(x: 610, y: 120), radius: 280, color: color(0xB86AE6, 0.38))
    radialGlow(center: NSPoint(x: 360, y: 520), radius: 300, color: color(0x4F6FE8, 0.30))
    // Soft halos where the two icons sit.
    radialGlow(center: appSlot, radius: 120, color: NSColor.white.withAlphaComponent(0.10))
    radialGlow(center: applicationsSlot, radius: 120, color: NSColor.white.withAlphaComponent(0.07))
    grain(in: rect, scale: scale)

    // Dotted arc from the app towards Applications, ending in an arrowhead.
    let start = NSPoint(x: appSlot.x + 86, y: appSlot.y - 6)
    let end = NSPoint(x: applicationsSlot.x - 86, y: applicationsSlot.y - 6)
    let control = NSPoint(x: (start.x + end.x) / 2, y: appSlot.y - 78)
    func point(_ t: CGFloat) -> NSPoint {
        let u = 1 - t
        return NSPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                       y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
    }
    let dots = 15
    for index in 0...dots {
        let t = CGFloat(index) / CGFloat(dots)
        let p = point(t)
        let radius: CGFloat = 2.2 + 1.0 * t
        NSColor.white.withAlphaComponent(0.25 + 0.6 * t).setFill()
        NSBezierPath(ovalIn: NSRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)).fill()
    }
    // A rounded chevron along the curve's final direction.
    let before = point(0.9)
    let angle = atan2(end.y - before.y, end.x - before.x)
    let tip = NSPoint(x: end.x + cos(angle) * 6, y: end.y + sin(angle) * 6)
    let chevron = NSBezierPath()
    for (index, side) in [-1.0, 1.0].enumerated() {
        let wing = angle + .pi + side * 0.62
        let p = NSPoint(x: tip.x + cos(wing) * 13, y: tip.y + sin(wing) * 13)
        if index == 0 { chevron.move(to: p); chevron.line(to: tip) } else { chevron.line(to: p) }
    }
    chevron.lineWidth = 3.2
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    NSColor.white.withAlphaComponent(0.9).setStroke()
    chevron.stroke()

    // Headline: "Drag Spaceroom to Applications", with the name in the brand colour.
    let bold = NSFont.systemFont(ofSize: 23, weight: .bold)
    let headline = NSMutableAttributedString()
    headline.append(NSAttributedString(string: "Drag ", attributes: [.font: bold, .foregroundColor: NSColor.white]))
    headline.append(NSAttributedString(string: "Spaceroom", attributes: [.font: bold, .foregroundColor: color(0xC8B2FF)]))
    headline.append(NSAttributedString(string: " to Applications", attributes: [.font: bold, .foregroundColor: NSColor.white]))
    let headlineSize = headline.size()
    headline.draw(at: NSPoint(x: (size.width - headlineSize.width) / 2, y: 308))

    let hint = NSAttributedString(
        string: "First launch: System Settings › Privacy & Security › Open Anyway",
        attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                     .foregroundColor: NSColor.white.withAlphaComponent(0.62)])
    let hintSize = hint.size()
    hint.draw(at: NSPoint(x: (size.width - hintSize.width) / 2, y: 342))
}

func render(scale: CGFloat, extra: (() -> Void)? = nil) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // Flip so coordinates match Finder's top-left icon positions.
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1)
    let flipped = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    NSGraphicsContext.current = flipped
    drawBackground(scale: scale)
    extra?()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: dmg-background.swift <output-dir> [Spaceroom.app]\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
write(render(scale: 1), to: output.appendingPathComponent("background.png"))
write(render(scale: 2), to: output.appendingPathComponent("background@2x.png"))

// Preview with icons and labels roughly as Finder will show them (for checking the layout only).
// Read the icon file directly: a fresh build isn't registered with Launch Services yet.
let appIcon: NSImage = arguments.count >= 3
    ? (NSImage(contentsOfFile: arguments[2] + "/Contents/Resources/AppIcon.icns") ?? NSWorkspace.shared.icon(forFile: arguments[2]))
    : NSImage(size: .zero)
let items: [(NSImage, String, NSPoint)] = [
    (appIcon, "Spaceroom", appSlot),
    (NSWorkspace.shared.icon(forFile: "/Applications"), "Applications", applicationsSlot),
    (NSWorkspace.shared.icon(for: .plainText), "Read Me First.txt", readMeSlot),
]
let preview = render(scale: 2) {
    for (icon, label, center) in items {
        icon.draw(in: NSRect(x: center.x - iconSize / 2, y: center.y - iconSize / 2, width: iconSize, height: iconSize),
                  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let text = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 13),
                                                                    .foregroundColor: NSColor.white])
        let textSize = text.size()
        text.draw(at: NSPoint(x: center.x - textSize.width / 2, y: center.y + iconSize / 2 + 4))
    }
}
write(preview, to: output.appendingPathComponent("preview.png"))
print("wrote background.png, background@2x.png and preview.png to \(output.path)")
