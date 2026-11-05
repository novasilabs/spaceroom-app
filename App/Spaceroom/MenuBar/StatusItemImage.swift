// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SpaceroomCore

/// Draws menu bar item images. Images draw lazily, so `labelColor` follows the menu bar's
/// light or dark appearance; warning colours are only used for the storage ring itself.
enum StatusItemImage {
    private static let height: CGFloat = 18
    private static var font: NSFont { .monospacedDigitSystemFont(ofSize: 12.5, weight: .medium) }

    static func storage(_ volume: VolumeInfo?, style: MenuBarModel.StorageStyle) -> NSImage {
        let fraction = volume?.usedFraction ?? 0
        let level = volume?.level ?? .ok
        let text: String? = switch style {
        case .ringOnly: nil
        case .ringAndFree, .freeOnly: volume.map { compactBytes($0.availableBytes) } ?? "–"
        case .percentUsed: volume.map { _ in "\(Int((fraction * 100).rounded()))%" } ?? "–"
        }
        let showsRing = style != .freeOnly
        return compose(text: text, leading: showsRing ? ring(fraction: fraction, level: level) : nil,
                       isTemplate: level == .ok)
    }

    static func cpu(_ usage: Double?, history: [Double]) -> NSImage {
        let text = usage.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        return compose(text: text, leading: bars(history.suffix(5)), isTemplate: true)
    }

    static func memory(_ snapshot: MemorySnapshot?) -> NSImage {
        let text = snapshot.map { compactBytes($0.usedBytes) } ?? "–"
        let color: NSColor? = switch snapshot?.pressure {
        case .critical: .systemRed
        case .warning: .systemOrange
        default: nil
        }
        return compose(text: text, leading: dot(color: color), isTemplate: color == nil)
    }

    /// Several readings in one menu bar item, side by side. Template only if every part is, so a
    /// warning colour (low disk, memory pressure) survives.
    static func combined(_ parts: [NSImage]) -> NSImage {
        guard parts.count > 1 else { return parts.first ?? compose(text: nil, leading: dot(color: nil), isTemplate: true) }
        let spacing: CGFloat = 10
        let width = parts.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(parts.count - 1)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for part in parts {
                part.draw(in: NSRect(x: x, y: 0, width: part.size.width, height: height))
                x += part.size.width + spacing
            }
            return true
        }
        image.isTemplate = parts.allSatisfy(\.isTemplate)
        image.accessibilityDescription = parts.compactMap(\.accessibilityDescription).joined(separator: ", ")
        return image
    }

    /// "128 GB" with no decimals above 10 GB, to keep the item narrow.
    static func compactBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1000 { return String(format: "%.1f TB", gb / 1000) }
        if gb >= 10 { return "\(Int(gb.rounded())) GB" }
        return bytes.formatted(.byteCount(style: .file))
    }

    // MARK: Drawing

    typealias Glyph = (width: CGFloat, draw: (NSRect) -> Void)

    private static func compose(text: String?, leading: Glyph?, isTemplate: Bool) -> NSImage {
        let attributes: () -> [NSAttributedString.Key: Any] = { [.font: font, .foregroundColor: NSColor.labelColor] }
        let textWidth = text.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) } ?? 0
        let gap: CGFloat = (leading != nil && text != nil) ? 4 : 0
        let width = (leading?.width ?? 0) + gap + textWidth
        let image = NSImage(size: NSSize(width: max(width, 1), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            if let leading {
                leading.draw(NSRect(x: 0, y: 0, width: leading.width, height: height))
                x += leading.width + gap
            }
            if let text {
                let size = (text as NSString).size(withAttributes: attributes())
                (text as NSString).draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: attributes())
            }
            return true
        }
        image.isTemplate = isTemplate
        image.accessibilityDescription = text
        return image
    }

    private static func ring(fraction: Double, level: StorageLevel) -> Glyph {
        (15, { rect in
            let lineWidth: CGFloat = 2.2
            let box = NSRect(x: rect.midX - 6.5, y: rect.midY - 6.5, width: 13, height: 13)
            let track = NSBezierPath(ovalIn: box.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            track.lineWidth = lineWidth
            NSColor.labelColor.withAlphaComponent(0.3).setStroke()
            track.stroke()

            let accent: NSColor = switch level {
            case .ok: .labelColor
            case .low: .systemOrange
            case .critical: .systemRed
            }
            let arc = NSBezierPath()
            let radius = box.width / 2 - lineWidth / 2
            arc.appendArc(withCenter: NSPoint(x: box.midX, y: box.midY), radius: radius,
                          startAngle: 90, endAngle: 90 - 360 * CGFloat(min(1, max(0.02, fraction))), clockwise: true)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            accent.setStroke()
            arc.stroke()
        })
    }

    private static func bars(_ values: ArraySlice<Double>) -> Glyph {
        let values = Array(values)
        return (CGFloat(max(values.count, 1)) * 3, { rect in
            NSColor.labelColor.setFill()
            for (index, value) in values.enumerated() {
                let barHeight = max(2, CGFloat(value) * 12)
                NSBezierPath(roundedRect: NSRect(x: CGFloat(index) * 3, y: rect.midY - 6, width: 2, height: barHeight),
                             xRadius: 1, yRadius: 1).fill()
            }
        })
    }

    private static func dot(color: NSColor?) -> Glyph {
        (8, { rect in
            (color ?? .labelColor).setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: rect.midY - 3.5, width: 7, height: 7)).fill()
        })
    }
}
